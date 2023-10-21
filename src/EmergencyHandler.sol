// SPDX-License-Identifier: BUSL-1.1
/*
██████╗░██╗░░░░░░█████╗░░█████╗░███╗░░░███╗
██╔══██╗██║░░░░░██╔══██╗██╔══██╗████╗░████║
██████╦╝██║░░░░░██║░░██║██║░░██║██╔████╔██║
██╔══██╗██║░░░░░██║░░██║██║░░██║██║╚██╔╝██║
██████╦╝███████╗╚█████╔╝╚█████╔╝██║░╚═╝░██║
╚═════╝░╚══════╝░╚════╝░░╚════╝░╚═╝░░░░░╚═╝
*/

pragma solidity ^0.8.19;

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {IEmergencyHandler, IOracle} from "./interfaces/IEmergencyHandler.sol";
import {ExchangeRateRegistry} from "./helpers/ExchangeRateRegistry.sol";
import {AssetCommitment} from "./lib/CommitmentsLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IBloomPool} from "./interfaces/IBloomPool.sol";

/**
 * @title EmergencyHandler
 * @notice Allows users to redeem their funds from a Bloom Pool in emergency mode
 * @dev This contract must correspond to a specific ExchangeRateRegistry
 */
contract EmergencyHandler is IEmergencyHandler, Ownable2Step {
    using SafeTransferLib for address;
    // =================== Storage ===================

    ExchangeRateRegistry public immutable REGISTRY;
    mapping(address => RedemptionInfo) public redemptionInfo;
    mapping(address => mapping(uint256 => bool)) public borrowerClaimStatus;
    event log(string message, uint256 value);
    // ================== Modifiers ==================

    modifier onlyPool() {
        (bool registered, , ) = REGISTRY.tokenInfos(msg.sender);
        if (!registered) revert CallerNotBloomPool();
        _;
    }

    constructor(ExchangeRateRegistry _registry) Ownable2Step() {
        REGISTRY = _registry;
    }

    /**
     * @inheritdoc IEmergencyHandler
     */
    function redeem(IBloomPool pool) external override returns (uint256) {
        RedemptionInfo memory info = redemptionInfo[address(pool)];
        address redeemToken = info.token;
        if (redeemToken == address(0)) revert PoolNotRegistered();
        
        uint256 tokenAmount = ERC20(address(pool)).balanceOf(msg.sender);
        if (tokenAmount == 0) revert NoTokensToRedeem();
        pool.executeEmergencyBurn(msg.sender, tokenAmount);

        // BloomPool decimals are the same as the underlying token, so we scale down by the oracle's decimals
        uint256 amount = tokenAmount * info.rate / 10**info.rateDecimals;
        
        redeemToken.safeTransfer(msg.sender, amount);

        return amount;
    }

    /**
     * @inheritdoc IEmergencyHandler
     */
    function redeem(
        IBloomPool pool,
        uint256 id
    ) external override returns (uint256) {
        uint256 amount;
        RedemptionInfo memory info = redemptionInfo[address(pool)];
        address redeemToken = info.token;

        AssetCommitment memory commitment = pool.getBorrowCommitment(id);
        if (commitment.owner != msg.sender) revert InvalidOwner();

        if (borrowerClaimStatus[address(pool)][id]) {
            revert BorrowerAlreadyClaimed();
        } else {
            borrowerClaimStatus[address(pool)][id] = true;
        }

        uint256 redeemDecimals = ERC20(redeemToken).decimals();
        uint256 underlyingDecimals = ERC20(address(pool)).decimals();

        // Check if this logic is needed or is overkill
        if (redeemDecimals == underlyingDecimals) {
            amount = commitment.committedAmount * info.rate / 10**info.rateDecimals;
        } else if (redeemDecimals > underlyingDecimals) {
            uint256 scalingFactor = 10 ** (redeemDecimals - underlyingDecimals);
            amount = commitment.committedAmount * info.rate * scalingFactor / 10**info.rateDecimals;
        } else {
            uint256 scalingFactor = 10 ** (underlyingDecimals - redeemDecimals);
            amount = commitment.committedAmount * info.rate / 10**info.rateDecimals / scalingFactor;
        }

        redeemToken.safeTransfer(msg.sender, amount);
        
        return amount;
    }

    /**
     * @inheritdoc IEmergencyHandler
     */
    // TODO: Maybe add more checks on rates and update times
    // TODO: Add support for multiple registrations of a single pool
    function registerPool(IOracle _tokenOracle, address _asset) external override onlyPool {
        (, int256 answer,, uint256 updatedAt,) = _tokenOracle.latestRoundData();
        if (answer <= 0) revert OracleAnswerNegative();
        redemptionInfo[msg.sender] = RedemptionInfo(_asset, uint256(answer), _tokenOracle.decimals());
    }
}