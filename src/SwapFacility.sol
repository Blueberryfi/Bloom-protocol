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

    /// @notice Price oracle for billy token
    address public immutable billyTokenOracle;

    /// @notice Whitelist contract
    IWhitelist public immutable whitelist;

    /// @notice Spread price
    uint256 public spreadPrice;

    /// @dev Pool address
    address public pool;

    uint256 internal constant ORACLE_STALE_THRESHOLD = 1 hours;

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

    error OracleAnswerNegative();
    error OracleStale();

    // =================== Events ===================

    /// @notice Pool Updated Event
    /// @param oldPool Old pool address
    /// @param newPool New pool address
    event PoolUpdated(address indexed oldPool, address indexed newPool);

    /// @notice Spread Price Updated Event
    /// @param oldPrice Old spread price
    /// @param newPrice New spread price
    event SpreadPriceUpdated(uint256 indexed oldPrice, uint256 indexed newPrice);

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
    /// @param _spreadPrice Spread price
    constructor(
        address _underlyingToken,
        address _billyToken,
        address _underlyingTokenOracle,
        address _billyTokenOracle,
        IWhitelist _whitelist,
        uint256 _spreadPrice
    ) Owned(msg.sender) {
        underlyingToken = _underlyingToken;
        billyToken = _billyToken;
        underlyingTokenOracle = _underlyingTokenOracle;
        billyTokenOracle = _billyTokenOracle;
        whitelist = _whitelist;
        spreadPrice = _spreadPrice;
    }

    /// @notice Set Pool Address
    /// @param _pool New pool address
    function setPool(address _pool) external onlyOwner {
        address oldPool = pool;
        pool = _pool;
        emit PoolUpdated(oldPool, _pool);
    }

    /// @notice Set Spread Price
    /// @param _spreadPrice New spread price
    function setSpreadPrice(uint256 _spreadPrice) external onlyOwner {
        uint256 oldSpreadPrice = spreadPrice;
        spreadPrice = _spreadPrice;
        emit SpreadPriceUpdated(oldSpreadPrice, _spreadPrice);
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
            ? (underlyingTokenPrice, billyTokenPrice + spreadPrice)
            : (billyTokenPrice - spreadPrice, underlyingTokenPrice);
        outAmount = (_inAmount * inTokenPrice) / outTokenPrice;
        if (_swapAmount < outAmount) {
            outAmount = _swapAmount;
            _inAmount = (outAmount * outTokenPrice) / inTokenPrice;
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
        }

        emit Swap(_inToken, _outToken, _inAmount, outAmount, _to);
    }

    /// @dev Get prices of underlying and billy tokens
    /// @return underlyingTokenPrice Underlying token price
    /// @return billyTokenPrice Billy token price
    function _getTokenPrices() internal view returns (uint256 underlyingTokenPrice, uint256 billyTokenPrice) {
        underlyingTokenPrice = _readOracle(underlyingTokenOracle) * 1e12;
        billyTokenPrice = _readOracle(billyTokenOracle);
    }

    function _readOracle(address _oracle) internal view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = IOracle(_oracle).latestRoundData();
        if (answer <= 0) revert OracleAnswerNegative();
        if (block.timestamp - updatedAt >= ORACLE_STALE_THRESHOLD) revert OracleStale();
        return uint256(answer);
    }
}
