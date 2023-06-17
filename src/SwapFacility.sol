// SPDX-License-Identifier: BUSL-1.1
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {IWhitelist} from "./interfaces/IWhitelist.sol";
import {ISwapFacility} from "./interfaces/ISwapFacility.sol";
import {ISwapRecipient} from "./interfaces/ISwapRecipient.sol";
import {IBloomPool, State} from "./interfaces/IBloomPool.sol";
import {IOracle} from "./interfaces/IOracle.sol";

/// @author Blueberry protocol
contract SwapFacility is ISwapFacility, Owned {
    using SafeTransferLib for ERC20;
    // =================== Storage ===================

    /// @notice Underlying token
    address public immutable underlyingToken;

    /// @notice Billy token
    address public immutable billyToken;

    /// @notice Price oracle for underlying token
    address public immutable underlyingTokenOracle;
    uint256 public immutable underlyingScale;

    /// @notice Price oracle for billy token
    address public immutable billyTokenOracle;
    uint256 public immutable billyScale;

    /// @notice Whitelist contract
    IWhitelist public immutable whitelist;

    /// @notice Spread in basis points
    uint256 public immutable spread;

    /// @dev Pool address
    address public immutable pool;

    uint256 internal constant ORACLE_STALE_THRESHOLD = 24 hours;
    uint256 internal constant BPS = 1e4;
    uint internal constant MAX_SPREAD = 0.1e4; // 10%


    /// @dev Current swap stage
    /// 0: Not started
    /// 1: Underlying -> Billy swap initiated
    /// 2: Underlying -> Billy swap completed
    /// 3: Billy -> Underlying swap initiated
    /// 4: Billy -> Underlying swap completed
    uint8 internal _stage;

    /// @dev Total swap amount
    uint256 internal _swapAmount;

    /// @dev Total out amount
    uint256 internal _totalAmount;

    // =================== Errors ===================

    /// @notice Invalid Address
    error InvalidAddress();

    /// @notice Invalid Token
    error InvalidToken();

    /// Pool Not Set
    error PoolNotSet();

    /// @notice Not Pool
    error NotPool();

    /// @notice Not Whitelisted
    error NotWhitelisted();

    /// @dev Oracle reported negative `answer`.
    error OracleAnswerNegative();

    /// @dev Oracle response is more than `ORACLE_STALE_THRESHOLD` old.
    error OracleStale();

    /// @dev Given `spread` parameter is >=100%
    error InvalidSpread();

    // =================== Events ===================

    /// @notice Swap Event
    /// @param inToken In token address
    /// @param outToken Out token address
    /// @param inAmount In token amount
    /// @param user To address
    event Swap(address inToken, address outToken, uint256 inAmount, uint256 outAmount, address indexed user);

    // =================== Modifiers ===================

    modifier onlyWhitelisted(bytes32[] calldata proof) {
        if (msg.sender != pool && !IWhitelist(whitelist).isWhitelisted(msg.sender, proof)) {
            revert NotWhitelisted();
        }
        _;
    }

    // =================== Functions ===================

    /// @notice SwapFacility Constructor
    /// @param _underlyingToken Underlying token address
    /// @param _billyToken Billy token address
    /// @param _underlyingTokenOracle Price oracle for underlying token
    /// @param _billyTokenOracle Price oracle for billy token
    /// @param _whitelist Whitelist contract
    /// @param _spread Spread price
    constructor(
        address _underlyingToken,
        address _billyToken,
        address _underlyingTokenOracle,
        address _billyTokenOracle,
        IWhitelist _whitelist,
        uint256 _spread,
        address _pool
    ) Owned(msg.sender) {
        if (_spread > MAX_SPREAD) revert InvalidSpread();
        underlyingToken = _underlyingToken;
        billyToken = _billyToken;
        underlyingTokenOracle = _underlyingTokenOracle;
        underlyingScale = 10 ** IOracle(_underlyingTokenOracle).decimals();
        billyTokenOracle = _billyTokenOracle;
        billyScale = 10 ** IOracle(_billyTokenOracle).decimals();
        whitelist = _whitelist;
        spread = _spread;
        pool = _pool;
    }

    /// @notice Swap tokens UNDERLYING <-> BILLY
    /// @param _inToken In token address
    /// @param _outToken Out token address
    /// @param _inAmount In token amount
    /// @param _proof Whitelist proof
    function swap(address _inToken, address _outToken, uint256 _inAmount, bytes32[] calldata _proof)
        external
        onlyWhitelisted(_proof)
    {
        if (_stage == 0) {
            if (_inToken != underlyingToken || _outToken != billyToken) {
                revert InvalidToken();
            }
            if (pool != msg.sender) revert NotPool();
            _stage = 1;
            _swapAmount = _inAmount;
        } else if (_stage == 1) {
            if (_inToken != billyToken || _outToken != underlyingToken) {
                revert InvalidToken();
            }
            _swap(_inToken, _outToken, _inAmount, msg.sender);
        } else if (_stage == 2) {
            if (_inToken != billyToken || _outToken != underlyingToken) {
                revert InvalidToken();
            }
            if (pool != msg.sender) revert NotPool();
            _stage = 3;
            _swapAmount = _inAmount;
        } else if (_stage == 3) {
            if (_inToken != underlyingToken || _outToken != billyToken) {
                revert InvalidToken();
            }
            _swap(_inToken, _outToken, _inAmount, msg.sender);
        }
    }

    /// @dev Perform swap between pool and user
    ///     Transfer `outToken` from `to` to Pool and `inToken` from Pool to `to`
    ///     outAmount is calculated based on the prices of both tokens
    ///     No swap fee is applied
    ///     Once entire swap is done, notify Pool contract by calling `completeSwap` function
    /// @param _inToken In token address
    /// @param _outToken Out token address
    /// @param _inAmount In token amount
    /// @param _to To address
    function _swap(address _inToken, address _outToken, uint256 _inAmount, address _to)
        internal
        returns (uint256 outAmount)
    {
        (uint256 underlyingTokenPrice, uint256 billyTokenPrice) = _getTokenPrices();
        (uint256 inTokenPrice, uint256 outTokenPrice) = _inToken == underlyingToken
            ? (underlyingTokenPrice, billyTokenPrice)
            : (billyTokenPrice, underlyingTokenPrice);
        outAmount = (_inAmount * inTokenPrice * (BPS + spread)) / outTokenPrice / BPS;
        if (_swapAmount < outAmount) {
            outAmount = _swapAmount;
            _inAmount = (outAmount * outTokenPrice * BPS) / inTokenPrice / (BPS + spread);
        }
        unchecked {
            _swapAmount -= outAmount;
        }
        _totalAmount += _inAmount;
        ERC20(_inToken).safeTransferFrom(_to, pool, _inAmount);
        ERC20(_outToken).safeTransferFrom(pool, _to, outAmount);
        if (_swapAmount == 0) {
            ++_stage;
            ISwapRecipient(pool).completeSwap(_inToken, _totalAmount);
            _totalAmount = 0;
        }

        emit Swap(_inToken, _outToken, _inAmount, outAmount, _to);
    }

    /// @dev Get prices of underlying and billy tokens
    /// @return underlyingTokenPrice Underlying token price
    /// @return billyTokenPrice Billy token price
    function _getTokenPrices() internal view returns (uint256 underlyingTokenPrice, uint256 billyTokenPrice) {
        // Scaled with each other's decimals so they cancel out when calculating `x * priceA / priceB`.
        underlyingTokenPrice = uint256(IOracle(underlyingTokenOracle).latestAnswer()) * billyScale;
        billyTokenPrice = uint256(IOracle(billyTokenOracle).latestAnswer()) * underlyingScale;
    }
}
