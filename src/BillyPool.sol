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
import {IBillyPool, State} from "./interfaces/IBillyPool.sol";
import {ISwapRecipient} from "./interfaces/ISwapRecipient.sol";

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {FixedPointMathLib as Math} from "solady/utils/FixedPointMathLib.sol";
import {CommitmentsLib, Commitments, AssetCommitment} from "./lib/CommitmentsLib.sol";

import {IWhitelist} from "./interfaces/IWhitelist.sol";
import {ISwapFacility} from "./interfaces/ISwapFacility.sol";
import {IBPSFeed} from "./interfaces/IBPSFeed.sol";

/// @author Blueberry protocol
contract BillyPool is IBillyPool, ISwapRecipient, ERC20 {
    using CommitmentsLib for Commitments;
    using CommitmentsLib for AssetCommitment;
    using SafeTransferLib for address;
    using SafeCastLib for uint256;

    uint256 internal constant BPS = 1e4;

    // =============== Core Parameters ===============

    address public immutable UNDERLYING_TOKEN;
    address public immutable BILL_TOKEN;
    IWhitelist public immutable WHITELIST;
    address public immutable SWAP_FACILITY;
    address public immutable TREASURY;
    address public immutable LENDER_RETURN_BPS_FEED;
    uint256 public immutable LEVERAGE_BPS;
    uint256 public immutable MIN_BORROW_DEPOSIT;
    uint256 public immutable COMMIT_PHASE_END;
    uint256 public immutable POOL_PHASE_END;
    uint256 public immutable POOL_PHASE_DURATION;
    uint256 public immutable LENDER_RETURN_FEE;
    uint256 public immutable BORROWER_RETURN_FEE;

    // =================== Storage ===================

    Commitments internal borrowers;
    Commitments internal lenders;
    State internal setState = State.Commit;
    uint128 internal borrowerDistribution;
    uint128 internal totalBorrowerShares;
    uint128 internal lenderDistribution;
    uint128 internal totalLenderShares;

    // ================== Modifiers ==================

    modifier onlyState(State expectedState) {
        State currentState = state();
        if (currentState != expectedState) revert InvalidState(currentState);
        _;
    }

    modifier onlyAfterState(State lastInvalidState) {
        State currentState = state();
        if (currentState <= lastInvalidState) revert InvalidState(currentState);
        _;
    }
    constructor(
        address underlyingToken,
        address billToken,
        IWhitelist whitelist,
        address swapFacility,
        address treasury,
        address lenderReturnBpsFeed,
        uint256 leverageBps,
        uint256 minBorrowDeposit,
        uint256 commitPhaseDuration,
        uint256 poolPhaseDuration,
        uint256 lenderReturnFee,
        uint256 borrowerReturnFee,
        string memory name,
        string memory symbol
    )
        ERC20(name, symbol, ERC20(underlyingToken).decimals())
    {

        UNDERLYING_TOKEN = underlyingToken;
        BILL_TOKEN = billToken;
        WHITELIST = whitelist;
        SWAP_FACILITY = swapFacility;
        TREASURY = treasury;
        LENDER_RETURN_BPS_FEED = lenderReturnBpsFeed;
        LEVERAGE_BPS = leverageBps;
        MIN_BORROW_DEPOSIT = minBorrowDeposit;
        COMMIT_PHASE_END = block.timestamp + commitPhaseDuration;
        POOL_PHASE_END = block.timestamp + commitPhaseDuration + poolPhaseDuration;
        POOL_PHASE_DURATION = poolPhaseDuration;
        LENDER_RETURN_FEE = lenderReturnFee;
        BORROWER_RETURN_FEE = borrowerReturnFee;
    }    

    // =============== Deposit Methods ===============

    /**
     * @inheritdoc IBillyPool
     */
    function depositBorrower(uint256 amount, bytes32[] calldata proof)
        external
        onlyState(State.Commit)
        returns (uint256 newId)
    {
        if (amount < MIN_BORROW_DEPOSIT) revert CommitTooSmall();
        if (!IWhitelist(WHITELIST).isWhitelisted(msg.sender, proof)) revert NotWhitelisted();
        UNDERLYING_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        uint256 cumulativeAmountEnd;
        (newId, cumulativeAmountEnd) = borrowers.add(msg.sender, amount);
        emit BorrowerCommit(msg.sender, newId, amount, cumulativeAmountEnd);
    }

    /**
     * @inheritdoc IBillyPool
     */
    function depositLender(uint256 amount) external onlyState(State.Commit) returns (uint256 newId) {
        if (amount == 0) revert CommitTooSmall();
        UNDERLYING_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        uint256 cumulativeAmountEnd;
        (newId, cumulativeAmountEnd) = lenders.add(msg.sender, amount);
        emit LenderCommit(msg.sender, newId, amount, cumulativeAmountEnd);
    }

    // =========== Further Deposit Methods ===========

    /**
     * @inheritdoc IBillyPool
     */
    function processBorrowerCommit(uint256 id) external onlyAfterState(State.Commit) {
        AssetCommitment storage commitment = borrowers.commitments[id];
        if (commitment.cumulativeAmountEnd == 0) revert NoCommitToProcess();
        uint256 commitedBorrowValue = lenders.totalAssetsCommited * BPS / LEVERAGE_BPS;
        (uint256 includedAmount, uint256 excludedAmount) = commitment.getAmountSplit(commitedBorrowValue);
        commitment.commitedAmount = includedAmount.toUint128();
        commitment.cumulativeAmountEnd = 0;
        address owner = commitment.owner;
        emit BorrowerCommitmentProcessed(owner, id, includedAmount, excludedAmount);
        if (excludedAmount > 0) UNDERLYING_TOKEN.safeTransfer(owner, excludedAmount);
    }

    /**
     * @inheritdoc IBillyPool
     */
    function processLenderCommit(uint256 id) external onlyAfterState(State.Commit) {
        AssetCommitment storage commitment = lenders.commitments[id];
        if (commitment.cumulativeAmountEnd == 0) revert NoCommitToProcess();
        uint256 commitedBorrowValue = borrowers.totalAssetsCommited * LEVERAGE_BPS / BPS;
        (uint256 includedAmount, uint256 excludedAmount) = commitment.getAmountSplit(commitedBorrowValue);
        address owner = commitment.owner;
        delete lenders.commitments[id];
        _mint(owner, includedAmount);
        emit LenderCommitmentProcessed(owner, id, includedAmount, excludedAmount);
        if (excludedAmount > 0) UNDERLYING_TOKEN.safeTransfer(owner, excludedAmount);
    }

    // ======== Swap State Management Methods ========

    /**
     * @inheritdoc IBillyPool
     */
    function initiatePreHoldSwap() external onlyState(State.ReadyPreHoldSwap) {
        uint256 amountToSwap = totalMatchAmount() * (LEVERAGE_BPS + BPS) / LEVERAGE_BPS;
        UNDERLYING_TOKEN.safeApprove(SWAP_FACILITY, amountToSwap);
        emit ExplictStateTransition(State.ReadyPreHoldSwap, setState = State.PendingPreHoldSwap);
        ISwapFacility(SWAP_FACILITY).swap(UNDERLYING_TOKEN, BILL_TOKEN, amountToSwap, new bytes32[](0));
    }

    /**
     * @inheritdoc IBillyPool
     */
    function initiatePostHoldSwap() external onlyState(State.ReadyPostHoldSwap) {
        uint256 amountToSwap = ERC20(BILL_TOKEN).balanceOf(address(this));
        BILL_TOKEN.safeApprove(SWAP_FACILITY, amountToSwap);
        setState = State.PendingPostHoldSwap;
        emit ExplictStateTransition(State.ReadyPostHoldSwap, setState = State.PendingPostHoldSwap);
        ISwapFacility(SWAP_FACILITY).swap(BILL_TOKEN, UNDERLYING_TOKEN, amountToSwap, new bytes32[](0));
    }

    /**
     * @inheritdoc ISwapRecipient
     */
    function completeSwap(address outToken, uint256 outAmount) external {
        if (msg.sender != SWAP_FACILITY) revert NotSwapFacility();
        State currentState = state();
        if (currentState == State.PendingPreHoldSwap) {
            if (outToken != BILL_TOKEN) revert InvalidOutToken(outToken);
            emit ExplictStateTransition(State.PendingPreHoldSwap, setState = State.Holding);
            return;
        }
        if (currentState == State.PendingPostHoldSwap) {
            if (outToken != UNDERLYING_TOKEN) revert InvalidOutToken(outToken);
            uint256 totalMatched = totalMatchAmount();

            // Lenders get paid first, borrowers carry any shortfalls/excesses due to slippage.
            uint256 lenderReturn = Math.min(totalMatched * IBPSFeed(LENDER_RETURN_BPS_FEED).getWeightedRate() * POOL_PHASE_DURATION / 360 days / BPS, outAmount);
            uint256 borrowerReturn = outAmount - lenderReturn;

            uint256 lenderReturnFee = (lenderReturn - totalMatched)  * LENDER_RETURN_FEE / BPS;
            uint256 borrowerReturnFee = borrowerReturn * BORROWER_RETURN_FEE / BPS;

            borrowerDistribution = (borrowerReturn - borrowerReturnFee).toUint128();
            totalBorrowerShares = uint256(totalMatched * BPS / LEVERAGE_BPS).toUint128();

            lenderDistribution = (lenderReturn - lenderReturnFee).toUint128();
            totalLenderShares = uint256(totalMatched).toUint128();

            UNDERLYING_TOKEN.safeTransfer(TREASURY, lenderReturnFee + borrowerReturnFee);

            emit ExplictStateTransition(State.PendingPostHoldSwap, setState = State.FinalWithdraw);
            return;
        }
        revert InvalidState(currentState);
    }

    // =========== Final Withdraw Methods ============

    /**
     * @inheritdoc IBillyPool
     */
    function withdrawBorrower(uint256 id) external onlyState(State.FinalWithdraw) {
        AssetCommitment storage commitment = borrowers.commitments[id];
        if (commitment.cumulativeAmountEnd != 0) revert CanOnlyWithdrawProcessedCommit(id);
        address owner = commitment.owner;
        if (owner == address(0)) revert NoCommitToWithdraw();
        uint256 shares = commitment.commitedAmount;
        uint256 currentBorrowerDist = borrowerDistribution;
        uint256 sharesLeft = totalBorrowerShares;
        uint256 claimAmount = shares * currentBorrowerDist / sharesLeft;
        borrowerDistribution = (currentBorrowerDist - claimAmount).toUint128();
        totalBorrowerShares = (sharesLeft - shares).toUint128();
        delete borrowers.commitments[id];
        emit BorrowerWithdraw(owner, id, claimAmount);
        UNDERLYING_TOKEN.safeTransfer(owner, claimAmount);
    }

    /**
     * @inheritdoc IBillyPool
     */
    function withdrawLender(uint256 shares) external onlyState(State.FinalWithdraw) {
        _burn(msg.sender, shares);
        uint256 currentLenderDist = lenderDistribution;
        uint256 sharesLeft = totalLenderShares;
        uint256 claimAmount = shares * currentLenderDist / sharesLeft;
        lenderDistribution = (currentLenderDist - claimAmount).toUint128();
        totalLenderShares = (sharesLeft - shares).toUint128();
        emit LenderWithdraw(msg.sender, shares, claimAmount);
        UNDERLYING_TOKEN.safeTransfer(msg.sender, claimAmount);
    }

    // ================ View Methods =================

    /// @notice Returns amount of lender-to-borrower demand that was matched.
    function totalMatchAmount() public view returns (uint256) {
        uint256 borrowDemand = borrowers.totalAssetsCommited * LEVERAGE_BPS / BPS;
        uint256 lendDemand = lenders.totalAssetsCommited;
        return Math.min(borrowDemand, lendDemand);
    }

    function state() public view returns (State) {
        if (block.timestamp < COMMIT_PHASE_END) {
            return State.Commit;
        }
        State lastState = setState;
        if (lastState == State.Commit && block.timestamp >= COMMIT_PHASE_END) {
            return State.ReadyPreHoldSwap;
        }
        if (lastState == State.Holding && block.timestamp >= POOL_PHASE_END) {
            return State.ReadyPostHoldSwap;
        }
        return lastState;
    }

    function getBorrowCommitment(uint256 id) external view returns (AssetCommitment memory) {
        return borrowers.get(id);
    }

    function getLenderCommitment(uint256 id) external view returns (AssetCommitment memory) {
        return lenders.get(id);
    }

    function getTotalBorrowCommitment()
        external
        view
        returns (uint256 totalAssetsCommited, uint256 totalCommitmentCount)
    {
        totalAssetsCommited = borrowers.totalAssetsCommited;
        totalCommitmentCount = borrowers.commitmentCount;
    }

    function getTotalLendCommitment()
        external
        view
        returns (uint256 totalAssetsCommited, uint256 totalCommitmentCount)
    {
        totalAssetsCommited = lenders.totalAssetsCommited;
        totalCommitmentCount = lenders.commitmentCount;
    }

    function getDistributionInfo() external view returns (uint256, uint256, uint256, uint256) {
        return (borrowerDistribution, totalBorrowerShares, lenderDistribution, totalLenderShares);
    }
}