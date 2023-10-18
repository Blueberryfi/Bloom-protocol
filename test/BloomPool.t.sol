// SPDX-License-Identifier: BUSL-1.1
/*
██████╗░██╗░░░░░░█████╗░░█████╗░███╗░░░███╗
██╔══██╗██║░░░░░██╔══██╗██╔══██╗████╗░████║
██████╦╝██║░░░░░██║░░██║██║░░██║██╔████╔██║
██╔══██╗██║░░░░░██║░░██║██║░░██║██║╚██╔╝██║
██████╦╝███████╗╚█████╔╝╚█████╔╝██║░╚═╝░██║
╚═════╝░╚══════╝░╚════╝░░╚════╝░╚═╝░░░░░╚═╝
*/

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {FixedPointMathLib as Math} from "solady/utils/FixedPointMathLib.sol";

import {BloomPool, State, AssetCommitment} from "src/BloomPool.sol";
import {IBloomPool} from "src/interfaces/IBloomPool.sol";
import {IWhitelist} from "src/interfaces/IWhitelist.sol";
import {IBPSFeed} from "src/interfaces/IBPSFeed.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {MockWhitelist} from "./mock/MockWhitelist.sol";
import {MockSwapFacility} from "./mock/MockSwapFacility.sol";
import {MockBPSFeed} from "./mock/MockBPSFeed.sol";

contract BloomPoolTest is Test {
    BloomPool internal pool;

    MockERC20 internal stableToken;
    MockERC20 internal billyToken;
    MockWhitelist internal whitelist;
    MockSwapFacility internal swap;
    address internal treasury = makeAddr("treasury");
    address internal emergencyHandler = makeAddr("emergencyHandler");
    MockBPSFeed internal feed;

    uint256 internal commitPhaseDuration;
    uint256 internal poolPhaseDuration;

    uint256 internal constant BPS = 1e4;
    uint256 internal constant BPS_FEED_VALUE = 1.04e4;

    // ============== Redefined Events ===============
    event BorrowerCommit(address indexed owner, uint256 indexed id, uint256 amount, uint256 cumulativeAmountEnd);
    event LenderCommit(address indexed owner, uint256 indexed id, uint256 amount, uint256 cumulativeAmountEnd);
    event BorrowerCommitmentProcessed(
        address indexed owner, uint256 indexed id, uint256 includedAmount, uint256 excludedAmount
    );
    event LenderCommitmentProcessed(
        address indexed owner, uint256 indexed id, uint256 includedAmount, uint256 excludedAmount
    );
    event ExplictStateTransition(State prevState, State newState);
    event BorrowerWithdraw(address indexed owner, uint256 indexed id, uint256 amount);
    event LenderWithdraw(address indexed owner, uint256 sharesRedeemed, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event EmergencyWithdraw(address indexed owner);

    function setUp() public {
        stableToken = new MockERC20(6);
        vm.label(address(stableToken), "StableToken");
        billyToken = new MockERC20(18);
        vm.label(address(billyToken), "BillyToken");
        whitelist = new MockWhitelist();
        swap = new MockSwapFacility(stableToken, billyToken);
        feed = new MockBPSFeed();

        feed.setRate(BPS_FEED_VALUE);

        pool = new BloomPool({
            underlyingToken: address(stableToken),
            billToken: address(billyToken),
            whitelist: IWhitelist(address(whitelist)),
            swapFacility: address(swap),
            treasury: treasury,
            leverageBps: 4 * BPS,
            emergencyHandler: emergencyHandler,
            minBorrowDeposit: 100.0e6,
            commitPhaseDuration: commitPhaseDuration = 3 days,
            preHoldSwapTimeout: 7 days,
            poolPhaseDuration: poolPhaseDuration = 180 days,
            lenderReturnBpsFeed: address(feed),
            lenderReturnFee: 0,
            borrowerReturnFee: 0,
            name: "Term Bound Token 6 month 2023-06-1",
            symbol: "TBT-1"
        });
    }

    function testDefaultState() public {
        assertEq(pool.state(), State.Commit);
    }

    function test_fuzzingOnlyTransitionsFromCommitAfterDuration(uint256 forward) public {
        forward = bound(forward, 0, commitPhaseDuration - 1);
        // If not forwarding through full commit duration should still be in `State.Commit`.
        skip(forward);
        assertEq(pool.state(), State.Commit);
        // Forwarding remainder causes state transition.
        skip(commitPhaseDuration - forward);
        assertEq(pool.state(), State.ReadyPreHoldSwap);
    }

    function test_fuzzingBorrowerCannotDepositWithoutWhitelist(address user, uint256 amount) public {
        amount = uint128(bound(amount, pool.MIN_BORROW_DEPOSIT(), type(uint128).max));
        assertFalse(whitelist.includes(user));
        stableToken.mint(user, amount);
        vm.startPrank(user);
        stableToken.approve(address(pool), amount);
        vm.expectRevert(IBloomPool.NotWhitelisted.selector);
        pool.depositBorrower(amount, new bytes32[](0));
        vm.stopPrank();
    }

    function test_fuzzingWhitelistedBorrowerCanDeposit(address user, uint256 amount) public {
        amount = bound(amount, pool.MIN_BORROW_DEPOSIT(), type(uint128).max);
        whitelist.add(user);

        stableToken.mint(user, amount);
        uint256 expectedId = 0;

        vm.startPrank(user);
        stableToken.approve(address(pool), amount);
        vm.expectEmit(true, true, true, true);
        emit BorrowerCommit(user, expectedId, amount, amount);
        pool.depositBorrower(amount, new bytes32[](0));
        vm.stopPrank();

        AssetCommitment memory commitment = pool.getBorrowCommitment(expectedId);
        assertEq(commitment.owner, user);
        assertEq(commitment.committedAmount, amount);
        assertEq(commitment.cumulativeAmountEnd, amount);

        (uint256 totalAssetsCommitted, uint256 totalCommitments) = pool.getTotalBorrowCommitment();
        assertEq(totalAssetsCommitted, amount);
        assertEq(totalCommitments, 1);
    }

    function test_fuzzingLenderCanDeposit(address user, uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        stableToken.mint(user, amount);
        uint256 expectedId = 0;

        vm.startPrank(user);
        stableToken.approve(address(pool), amount);
        vm.expectEmit(true, true, true, true);
        emit LenderCommit(user, expectedId, amount, amount);
        pool.depositLender(amount);
        vm.stopPrank();

        AssetCommitment memory commitment = pool.getLenderCommitment(expectedId);
        assertEq(commitment.owner, user);
        assertEq(commitment.committedAmount, amount);
        assertEq(commitment.cumulativeAmountEnd, amount);

        (uint256 totalAssetsCommitted, uint256 totalCommitments) = pool.getTotalLendCommitment();
        assertEq(totalAssetsCommitted, amount);
        assertEq(totalCommitments, 1);
    }

    function test_fuzzingMintsSharesForLenderCommit(address user, uint256 lenderAmount) public {
        // Ensure that `lenderAmount` is in right range and matched amount will be equal `lenderAmount`
        uint256 leverage = pool.LEVERAGE_BPS();
        lenderAmount = bound(lenderAmount, pool.MIN_BORROW_DEPOSIT() * leverage / BPS, type(uint128).max);
        uint256 borrowerAmount = lenderAmount * BPS / leverage;
        if (borrowerAmount * leverage / BPS < lenderAmount) borrowerAmount += 1;
        assertGe(borrowerAmount * leverage / BPS, lenderAmount);

        // Setup matched amount.
        stableToken.mint(user, borrowerAmount + lenderAmount);
        vm.startPrank(user);
        stableToken.approve(address(pool), type(uint256).max);
        whitelist.add(user);
        pool.depositBorrower(borrowerAmount, new bytes32[](0));
        pool.depositLender(lenderAmount);
        vm.stopPrank();
        vm.warp(pool.COMMIT_PHASE_END());

        uint256 id = 0;

        vm.expectEmit(true, true, true, true, address(pool));
        emit Transfer(address(0), user, lenderAmount);
        vm.expectEmit(true, true, true, true, address(pool));
        emit LenderCommitmentProcessed(user, id, lenderAmount, 0);
        pool.processLenderCommit(id);

        assertEq(pool.balanceOf(user), lenderAmount);

        // Check that commit cannot be re-processed.
        vm.expectRevert(IBloomPool.NoCommitToProcess.selector);
        pool.processLenderCommit(id);
    }

    function test_fuzzingProcessesBorrowerCommit(address user, uint256 borrowerAmount) public {
        uint256 leverage = pool.LEVERAGE_BPS();
        borrowerAmount = bound(borrowerAmount, pool.MIN_BORROW_DEPOSIT(), type(uint128).max * BPS / leverage);
        uint256 lenderAmount = borrowerAmount * leverage / BPS;

        uint256 id = 0;
        // Setup matched amount.
        stableToken.mint(user, borrowerAmount + lenderAmount);
        vm.startPrank(user);
        stableToken.approve(address(pool), type(uint256).max);
        whitelist.add(user);
        pool.depositBorrower(borrowerAmount, new bytes32[](0));
        pool.depositLender(lenderAmount);
        vm.stopPrank();
        vm.warp(pool.COMMIT_PHASE_END());

        vm.expectEmit(true, true, true, true, address(pool));
        emit BorrowerCommitmentProcessed(user, id, borrowerAmount, 0);
        pool.processBorrowerCommit(id);

        AssetCommitment memory commitment = pool.getBorrowCommitment(id);
        assertEq(commitment.cumulativeAmountEnd, 0);
        assertEq(commitment.committedAmount, borrowerAmount);

        vm.expectRevert(IBloomPool.NoCommitToProcess.selector);
        pool.processBorrowerCommit(id);
    }

    function test_fuzzingPartialMatch(
        address borrower,
        address lender,
        uint256 borrowerAmount,
        uint256 lenderAmount
    ) public {
        borrowerAmount = bound(borrowerAmount, pool.MIN_BORROW_DEPOSIT(), type(uint128).max);
        lenderAmount = bound(lenderAmount, pool.MIN_BORROW_DEPOSIT(), type(uint128).max);
        // Require lender and borrower amount to not perfectly cover each other.
        uint256 leverage = pool.LEVERAGE_BPS();
        vm.assume(lenderAmount * BPS / leverage != lenderAmount);

        stableToken.mint(borrower, borrowerAmount);
        vm.startPrank(borrower);
        stableToken.approve(address(pool), type(uint256).max);
        whitelist.add(borrower);
        pool.depositBorrower(borrowerAmount, new bytes32[](0));
        vm.stopPrank();

        stableToken.mint(lender, lenderAmount);
        vm.startPrank(lender);
        stableToken.approve(address(pool), type(uint256).max);
        pool.depositLender(lenderAmount);
        vm.stopPrank();

        vm.warp(pool.COMMIT_PHASE_END());

        uint256 id = 0;
        if (borrowerAmount * leverage / BPS > lenderAmount) {
            uint256 allocatedBorrowerAmount = lenderAmount * BPS / leverage;

            vm.expectEmit(true, true, true, true, address(pool));
            emit Transfer(address(0), lender, lenderAmount);
            vm.expectEmit(true, true, true, true, address(pool));
            emit LenderCommitmentProcessed(lender, id, lenderAmount, 0);
            pool.processLenderCommit(id);
            assertEq(pool.balanceOf(lender), lenderAmount);

            vm.expectEmit(true, true, true, true, address(pool));
            emit BorrowerCommitmentProcessed(
                borrower, id, allocatedBorrowerAmount, borrowerAmount - allocatedBorrowerAmount
            );
            pool.processBorrowerCommit(id);

            AssetCommitment memory commitment = pool.getBorrowCommitment(id);
            assertEq(commitment.cumulativeAmountEnd, 0);
            assertEq(commitment.committedAmount, allocatedBorrowerAmount);
        } else {
            uint256 allocatedLenderAmount = borrowerAmount * leverage / BPS;

            vm.expectEmit(true, true, true, true, address(pool));
            emit BorrowerCommitmentProcessed(borrower, id, borrowerAmount, 0);
            pool.processBorrowerCommit(id);

            vm.expectEmit(true, true, true, true, address(pool));
            emit Transfer(address(0), lender, allocatedLenderAmount);
            vm.expectEmit(true, true, true, true, address(pool));
            emit LenderCommitmentProcessed(lender, id, allocatedLenderAmount, lenderAmount - allocatedLenderAmount);
            pool.processLenderCommit(id);
            assertEq(pool.balanceOf(lender), allocatedLenderAmount);
            assertEq(stableToken.balanceOf(lender), lenderAmount - allocatedLenderAmount);
        }

        vm.expectRevert(IBloomPool.NoCommitToProcess.selector);
        pool.processLenderCommit(id);
        vm.expectRevert(IBloomPool.NoCommitToProcess.selector);
        pool.processBorrowerCommit(id);
    }

    function testFullFlow() public {
        address userBorrower = makeWhitelistedAddr("userBorrower");
        address userLender = makeWhitelistedAddr("userLender");
        uint256 leverage = pool.LEVERAGE_BPS();

        // ############## High level Checks ##############
        uint256 startingBillPrice = 1.00e18;
        uint256 endingBillPrice = 1.025e18;

        uint256 borrowAmount = 100e6;
        uint256 lenderAmount = borrowAmount * leverage / BPS;
    
        uint256 total = lenderAmount + borrowAmount;
        uint256 lenderYield = lenderAmount * (BPS_FEED_VALUE - BPS) * poolPhaseDuration / 360 days / BPS;
        
        uint256 endValueLender = lenderAmount + lenderYield;
        uint256 appreciatedTBillValue = total * endingBillPrice / startingBillPrice;
        uint256 endValueBorrower = appreciatedTBillValue - endValueLender;
        // ###############################################
        
        stableToken.mint(userBorrower, borrowAmount);
        stableToken.mint(userLender, lenderAmount);

        vm.startPrank(userBorrower);
        stableToken.approve(address(pool), type(uint256).max);
        pool.depositBorrower(borrowAmount, new bytes32[](0));
        vm.stopPrank();

        vm.startPrank(userLender);
        stableToken.approve(address(pool), type(uint256).max);
        pool.depositLender(lenderAmount);
        vm.stopPrank();

        uint256 unusedLendAmount = 12.3801e18;
        {
            address otherUser = makeAddr("otherUser");
            stableToken.mint(otherUser, unusedLendAmount);
            vm.startPrank(otherUser);
            stableToken.approve(address(pool), type(uint256).max);
            pool.depositLender(unusedLendAmount);
            vm.stopPrank();
            vm.prank(otherUser);
            vm.expectRevert(abi.encodeWithSelector(IBloomPool.InvalidState.selector, (State.Commit)));
            pool.withdrawLender(unusedLendAmount);
        }

        vm.warp(pool.COMMIT_PHASE_END());

        assertEq(pool.state(), State.ReadyPreHoldSwap);

        pool.processLenderCommit(0);
        pool.processLenderCommit(1);
        pool.processBorrowerCommit(0);

        swap.setRate(startingBillPrice);
        vm.expectEmit(true, true, true, true);
        emit ExplictStateTransition(State.ReadyPreHoldSwap, State.PendingPreHoldSwap);
        pool.initiatePreHoldSwap(new bytes32[](0));
        assertEq(pool.state(), State.PendingPreHoldSwap);
        assertEq(stableToken.balanceOf(address(pool)), 0);

        vm.expectEmit(true, true, true, true);
        emit ExplictStateTransition(State.PendingPreHoldSwap, State.Holding);
        swap.completeNextSwap();

        assertEq(pool.state(), State.Holding);
        uint256 billsReceived = total * 1e18 / startingBillPrice;
        uint256 billBalance = billyToken.balanceOf(address(pool));
        assertEq(billBalance, billsReceived);

        vm.warp(pool.POOL_PHASE_END());
        assertEq(pool.state(), State.ReadyPostHoldSwap);

        swap.setRate(endingBillPrice = 1.025e18);
        vm.expectEmit(true, true, true, true);
        emit ExplictStateTransition(State.ReadyPostHoldSwap, State.PendingPostHoldSwap);
        pool.initiatePostHoldSwap(new bytes32[](0));
        assertEq(pool.state(), State.PendingPostHoldSwap);

        vm.expectEmit(true, true, true, true);
        emit ExplictStateTransition(State.PendingPostHoldSwap, State.FinalWithdraw);
        swap.completeNextSwap();
        assertEq(pool.state(), State.FinalWithdraw);

        uint256 lenderReceived;
        uint256 borrowerReceived;
        uint256 totalAmount;
        uint256 totalMatchAmount;
        uint256 lenderDistro;

        {
            (uint256 borrowerDist, uint256 borrowerShares, uint256 lenderDist, uint256 lenderShares) =
                pool.getDistributionInfo();
            lenderDistro = lenderDist;

            assertEq(borrowerShares, borrowAmount);
            assertEq(lenderShares, lenderAmount);

            totalAmount = billsReceived * endingBillPrice / 1e18;
            totalMatchAmount = pool.totalMatchAmount();

            uint256 rateAppreciation = IBPSFeed(pool.LENDER_RETURN_BPS_FEED()).getWeightedRate() - BPS;
            uint256 yield = totalMatchAmount * rateAppreciation * poolPhaseDuration / 360 days / BPS;
            
            lenderReceived = (totalMatchAmount + yield);
            borrowerReceived = totalAmount - lenderReceived;

            uint256 lenderFee = (lenderReceived - totalMatchAmount) * pool.LENDER_RETURN_FEE() / BPS;
            uint256 borrowerFee = borrowerReceived * pool.BORROWER_RETURN_FEE() / BPS;

            lenderReceived -= lenderFee;
            borrowerReceived -= borrowerFee;
            totalAmount = lenderReceived + borrowerReceived;

            assertEq(lenderDist, lenderReceived);
            assertEq(borrowerDist, borrowerReceived);

            assertEq(stableToken.balanceOf(treasury), lenderFee + borrowerFee);
        }

        // Lender Withdraw
        vm.expectEmit(true, true, true, true);
        emit Transfer(userLender, address(0), lenderAmount);
        vm.expectEmit(true, true, true, true);
        emit LenderWithdraw(userLender, lenderAmount, endValueLender);
        
        vm.startPrank(userLender);
        pool.withdrawLender(lenderAmount);
        vm.stopPrank();

        assertEq(stableToken.balanceOf(userLender), endValueLender);

        // Withdraw borrower
        uint256 borrowId = 0;
        vm.expectEmit(true, true, true, true);
        emit BorrowerWithdraw(userBorrower, borrowId, borrowerReceived);

        vm.startPrank(userBorrower);
        pool.withdrawBorrower(borrowId);
        vm.stopPrank();
        
        assertEq(stableToken.balanceOf(userBorrower), endValueBorrower);

        // Verify that the pool is empty
        assertEq(stableToken.balanceOf(address(pool)), 0);
        assertEq(billyToken.balanceOf(address(pool)), 0);
    }

    function testCannotDepositAfterCommit() public {
        vm.warp(pool.COMMIT_PHASE_END());
        assertEq(pool.state(), State.ReadyPreHoldSwap);

        address user1 = makeAddr("user1");
        uint256 amount1 = 10e18;
        stableToken.mint(user1, amount1);
        vm.startPrank(user1);
        stableToken.approve(address(pool), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IBloomPool.InvalidState.selector, (State.ReadyPreHoldSwap)));
        pool.depositLender(amount1);
        vm.stopPrank();

        address user2 = makeWhitelistedAddr("user2");
        uint256 amount2 = 120.2e18;
        stableToken.mint(user2, amount2);
        vm.startPrank(user2);
        stableToken.approve(address(pool), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IBloomPool.InvalidState.selector, (State.ReadyPreHoldSwap)));
        pool.depositBorrower(amount2, new bytes32[](0));
        vm.stopPrank();
    }

    function testEmergencyWithdraw() public {
        // Deposit Stables into pool
        address user = makeWhitelistedAddr("user");
        uint256 amount = 1000e18;
        stableToken.mint(user, amount);
        vm.startPrank(user);
        stableToken.approve(address(pool), type(uint256).max);
        whitelist.add(user);
        pool.depositBorrower(amount / 2, new bytes32[](0));
        pool.depositLender(amount / 2);
        vm.stopPrank();
        
        vm.warp(pool.COMMIT_PHASE_END());
        swap.setRate(1e18);
        pool.initiatePreHoldSwap(new bytes32[](0));

        // Fails to emergency withdraw before the pre-hold swap timeout
        vm.startPrank(emergencyHandler);
        vm.expectRevert(abi.encodeWithSelector(IBloomPool.InvalidState.selector, (State.PendingPreHoldSwap)));
        pool.emergencyWithdrawTo(emergencyHandler);
        vm.stopPrank();

        // Fast Forward to Emergency Exit Period
        vm.warp(pool.POOL_PHASE_END());
        assertEq(pool.state(), State.EmergencyExit);

        // Fails to revert with none emergency handler account
        vm.startPrank(user);
        vm.expectRevert(IBloomPool.NotEmergencyHandler.selector);
        pool.emergencyWithdrawTo(user);
        vm.stopPrank();

        uint256 billyBalance = billyToken.balanceOf(address(pool));

        vm.startPrank(emergencyHandler);
        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdraw(emergencyHandler);
        pool.emergencyWithdrawTo(emergencyHandler);
        vm.stopPrank();
        
        assertEq(billyToken.balanceOf(emergencyHandler), billyBalance);
        assertEq(billyToken.balanceOf(address(pool)), 0);
    }

    function assertEq(State a, State b) internal {
        assertEq(uint8(a), uint256(b));
    }

    function assertEq(State a, State b, string memory assertMsg) internal {
        assertEq(uint8(a), uint256(b), assertMsg);
    }

    function makeWhitelistedAddr(string memory label) internal returns (address addr) {
        addr = makeAddr(string(abi.encodePacked(label, " (whitelisted)")));
        whitelist.add(addr);
    }
}
