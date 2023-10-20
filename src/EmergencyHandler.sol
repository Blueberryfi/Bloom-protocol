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
import {BloomPool} from "./BloomPool.sol";

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
    mapping(address => mapping(uint256 => bool)) private borrowerClaimStatus;
    
    // ================== Modifiers ==================

    modifier onlyPool() {
        (bool registered, , ) = REGISTRY.tokenInfos(msg.sender);
        if (!registered) revert CallerNotBloomPool();
        _;
    }

    constructor(address _registry) Ownable2Step() {
        REGISTRY = ExchangeRateRegistry(_registry);
    }

    /**
     * @inheritdoc IEmergencyHandler
     */
    function redeem(BloomPool pool) external override returns (uint256) {
        RedemptionInfo memory info = redemptionInfo[address(pool)];
        address redeemToken = info.token;
        if (redeemToken == address(0)) revert PoolNotRegistered();
        
        uint256 tokenAmount = pool.balanceOf(msg.sender);
        if (tokenAmount == 0) revert NoTokensToRedeem();
        pool.executeEmergencyBurn(msg.sender, tokenAmount);

        uint256 amount = tokenAmount * info.rate / token.decimals();
        redeemToken.safeTransfer(msg.sender, amount);

        return amount;
    }

    /**
     * @inheritdoc IEmergencyHandler
     */
    function redeem(
        BloomPool pool,
        uint256 id
    ) external override returns (uint256) {
        RedemptionInfo memory info = redemptionInfo[address(pool)];
        address reedemToken = info.token;

        AssetCommitment memory commitment = pool.getBorrowCommitment(id);
        if (commitment.owner != msg.sender) revert InvalidOwner();

        if (borrowerClaimStatus[address(pool)][id] == false) {
            revert BorrowerAlreadyClaimed();
        } else {
            borrowerClaimStatus[address(pool)][id] = true;
        }

        uint256 amount = commitment.committedAmount * info.rate / ERC20(reedemToken).decimals();
        reedemToken.safeTransfer(msg.sender, amount);
        
        return amount;
    }

    /**
     * @inheritdoc IEmergencyHandler
     */
    // TODO: Maybe add more checks on rates and update times
    function registerPool(IOracle _tokenOracle, address _asset) external override onlyPool {
        (, int256 answer,, uint256 updatedAt,) = _tokenOracle.latestRoundData();
        if (answer <= 0) revert OracleAnswerNegative();
        redemptionInfo[msg.sender] = RedemptionInfo(_asset, uint256(answer));
    }
}