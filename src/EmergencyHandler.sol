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

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

import {AssetCommitment} from "./lib/CommitmentsLib.sol";
import {ExchangeRateRegistry} from "./helpers/ExchangeRateRegistry.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {IBloomPool} from "./interfaces/IBloomPool.sol";
import {IEmergencyHandler, IOracle} from "./interfaces/IEmergencyHandler.sol";

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
        Token memory underlyingInfo = redemptionInfo[address(pool)].underlyingToken;
        address underlyingToken = underlyingInfo.token;
        if (underlyingToken == address(0)) revert PoolNotRegistered();
        
        uint256 tokenAmount = ERC20(address(pool)).balanceOf(msg.sender);
        if (tokenAmount == 0) revert NoTokensToRedeem();
        pool.executeEmergencyBurn(msg.sender, tokenAmount);

        // BloomPool decimals are the same as the underlying token, so we scale down by the oracle's decimals
        uint256 amount = tokenAmount * underlyingInfo.rate / 10**underlyingInfo.rateDecimals;
        underlyingToken.safeTransfer(msg.sender, amount);
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
        Token memory billTokenInfo = redemptionInfo[address(pool)].billToken;
        address billToken = billTokenInfo.token;
        uint256 billDecimals = ERC20(billToken).decimals();
        uint256 underlyingDecimals = ERC20(address(pool)).decimals();

        AssetCommitment memory commitment = pool.getBorrowCommitment(id);
        if (commitment.owner != msg.sender) revert InvalidOwner();

        if (borrowerClaimStatus[address(pool)][id]) {
            revert BorrowerAlreadyClaimed();
        } else {
            borrowerClaimStatus[address(pool)][id] = true;
        }

        if (billDecimals == underlyingDecimals) {
            amount = commitment.committedAmount * billTokenInfo.rate / 10**billTokenInfo.rateDecimals;
        } else if (billDecimals > underlyingDecimals) {
            uint256 scalingFactor = 10 ** (billDecimals - underlyingDecimals);
            amount = commitment.committedAmount * billTokenInfo.rate * scalingFactor / 10**billTokenInfo.rateDecimals;
        } else {
            uint256 scalingFactor = 10 ** (underlyingDecimals - billDecimals);
            amount = commitment.committedAmount * billTokenInfo.rate / 10**billTokenInfo.rateDecimals / scalingFactor;
        }

        billToken.safeTransfer(msg.sender, amount);
        return amount;
    }

    /**
     * @inheritdoc IEmergencyHandler
     */
    function registerPool(
        address underlyingToken,
        address billToken,
        IOracle underlyingOracle,
        IOracle billOracle
    ) external override onlyPool {
        if (redemptionInfo[msg.sender].underlyingToken.token != address(0)) revert PoolAlreadyRegistered();
        
        (, int256 underlyingAnswer,,,) = underlyingOracle.latestRoundData();
        (, int256 billAnswer,,,) = billOracle.latestRoundData();
        if (underlyingAnswer <= 0 || billAnswer <= 0) revert OracleAnswerNegative();

        redemptionInfo[msg.sender] = RedemptionInfo(
            Token(underlyingToken, uint256(underlyingAnswer), underlyingOracle.decimals()),
            Token(billToken, uint256(billAnswer), billOracle.decimals())
        );
    }
}