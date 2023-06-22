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

import {Test} from "forge-std/Test.sol";

import {BloomPool, State, AssetCommitment} from "src/BloomPool.sol";
import {IBloomPool} from "src/interfaces/IBloomPool.sol";
import {IWhitelist} from "src/interfaces/IWhitelist.sol";
import {IBPSFeed} from "src/interfaces/IBPSFeed.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {MockWhitelist} from "./mock/MockWhitelist.sol";
import {MockSwapFacility} from "./mock/MockSwapFacility.sol";
import {MockBPSFeed} from "./mock/MockBPSFeed.sol";

/// @author Blueberry protocol
contract BloomPoolTest is Test {
    BloomPool internal pool;

    MockERC20 internal stableToken;
    MockERC20 internal billyToken;
    MockWhitelist internal whitelist;
    MockSwapFacility internal swap;
    address internal treasury = makeAddr("treasury");
    MockBPSFeed internal feed;

    uint256 internal commitPhaseDuration;
    uint256 internal poolPhaseDuration;

    uint256 internal constant BPS = 1e4;

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

    function setUp() public {
        stableToken = new MockERC20(6);
        vm.label(address(stableToken), "StableToken");
        billyToken = new MockERC20(18);
        vm.label(address(billyToken), "BillyToken");
        whitelist = new MockWhitelist();
        swap = new MockSwapFacility(stableToken, billyToken);
        feed = new MockBPSFeed();

        feed.setRate((BPS + 30) * 12);

        pool = new BloomPool({
            underlyingToken: address(stableToken),
            billToken: address(billyToken),
            whitelist: IWhitelist(address(whitelist)),
            swapFacility: address(swap),
            treasury: treasury,
            leverageBps: 4 * BPS,
            minBorrowDeposit: 100.0e18,
            commitPhaseDuration: commitPhaseDuration = 3 days,
            poolPhaseDuration: poolPhaseDuration = 30 days,
            lenderReturnBpsFeed: address(feed),
            lenderReturnFee: 1000,
            borrowerReturnFee: 3000,
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
        assertEq(commitment.commitedAmount, amount);
        assertEq(commitment.cumulativeAmountEnd, amount);

        (uint256 totalAssetsCommited, uint256 totalCommitments) = pool.getTotalBorrowCommitment();
        assertEq(totalAssetsCommited, amount);
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
        assertEq(commitment.commitedAmount, amount);
        assertEq(commitment.cumulativeAmountEnd, amount);

        (uint256 totalAssetsCommited, uint256 totalCommitments) = pool.getTotalLendCommitment();
        assertEq(totalAssetsCommited, amount);
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
        assertEq(commitment.commitedAmount, borrowerAmount);

        vm.expectRevert(IBloomPool.NoCommitToProcess.selector);
        pool.processBorrowerCommit(id);
    }

    function test_fuzzingPartialMatch(address borrower, address lender, uint256 borrowerAmount, uint256 lenderAmount)
        public
    {
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
            assertEq(commitment.commitedAmount, allocatedBorrowerAmount);
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
        address user = makeWhitelistedAddr("user");
        uint256 leverage = pool.LEVERAGE_BPS();
        uint256 borrowAmount = 20_000e18;
        uint256 lenderAmount = borrowAmount * leverage / BPS;
        uint256 total = lenderAmount + borrowAmount;
        stableToken.mint(user, total);
        vm.startPrank(user);
        stableToken.approve(address(pool), type(uint256).max);
        pool.depositBorrower(borrowAmount, new bytes32[](0));
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
        uint256 billPrice = 1.01e18;
        swap.setRate(billPrice);
        vm.expectEmit(true, true, true, true);
        emit ExplictStateTransition(State.ReadyPreHoldSwap, State.PendingPreHoldSwap);
        pool.initiatePreHoldSwap();
        assertEq(pool.state(), State.PendingPreHoldSwap);
        assertEq(stableToken.balanceOf(address(pool)), unusedLendAmount);

        pool.processLenderCommit(0);
        pool.processLenderCommit(1);
        pool.processBorrowerCommit(0);

        vm.expectEmit(true, true, true, true);
        emit ExplictStateTransition(State.PendingPreHoldSwap, State.Holding);
        swap.completeNextSwap();

        assertEq(pool.state(), State.Holding);
        uint256 billsReceived = total * 1e18 / billPrice;
        assertEq(billyToken.balanceOf(address(pool)), billsReceived);

        vm.warp(pool.POOL_PHASE_END());
        assertEq(pool.state(), State.ReadyPostHoldSwap);

        swap.setRate(billPrice = 1.298e18);
        vm.expectEmit(true, true, true, true);
        emit ExplictStateTransition(State.ReadyPostHoldSwap, State.PendingPostHoldSwap);
        pool.initiatePostHoldSwap();
        assertEq(pool.state(), State.PendingPostHoldSwap);

        vm.expectEmit(true, true, true, true);
        emit ExplictStateTransition(State.PendingPostHoldSwap, State.FinalWithdraw);
        swap.completeNextSwap();
        assertEq(pool.state(), State.FinalWithdraw);

        uint256 lenderReceived;
        uint256 borrowerReceived;
        uint256 totalAmount;
        {
            (uint256 borrowerDist, uint256 borrowerShares, uint256 lenderDist, uint256 lenderShares) =
                pool.getDistributionInfo();
            assertEq(borrowerShares, borrowAmount);
            assertEq(lenderShares, lenderAmount);
            totalAmount = billsReceived * billPrice / 1e18;
            lenderReceived = lenderAmount * IBPSFeed(pool.LENDER_RETURN_BPS_FEED()).getWeightedRate() / 12 / BPS;
            borrowerReceived = totalAmount - lenderReceived;
            uint256 totalMatchAmount = pool.totalMatchAmount();
            uint256 lenderFee = (lenderReceived - totalMatchAmount) * pool.LENDER_RETURN_FEE() / BPS;
            uint256 borrowerFee = borrowerReceived * pool.BORROWER_RETURN_FEE() / BPS;
            lenderReceived -= lenderFee;
            borrowerReceived -= borrowerFee;
            totalAmount = lenderReceived + borrowerReceived;
            assertEq(lenderDist, lenderReceived);
            assertEq(borrowerDist, borrowerReceived);

            assertEq(stableToken.balanceOf(treasury), lenderFee + borrowerFee);
        }

        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        emit Transfer(user, address(0), lenderAmount / 2);
        vm.expectEmit(true, true, true, true);
        emit LenderWithdraw(user, lenderAmount / 2, lenderReceived / 2);
        pool.withdrawLender(lenderAmount / 2);
        assertEq(stableToken.balanceOf(user), lenderReceived / 2);
        assertEq(pool.balanceOf(user), lenderAmount - lenderAmount / 2);

        vm.expectEmit(true, true, true, true);
        emit Transfer(user, address(0), lenderAmount - lenderAmount / 2);
        vm.expectEmit(true, true, true, true);
        emit LenderWithdraw(user, lenderAmount - lenderAmount / 2, lenderReceived - lenderReceived / 2);
        pool.withdrawLender(lenderAmount - lenderAmount / 2);
        assertEq(stableToken.balanceOf(user), lenderReceived);
        assertEq(pool.balanceOf(user), 0);

        uint256 borrowId = 0;
        vm.expectEmit(true, true, true, true);
        emit BorrowerWithdraw(user, borrowId, borrowerReceived);
        pool.withdrawBorrower(borrowId);
        assertEq(stableToken.balanceOf(user), totalAmount);

        AssetCommitment memory commitment = pool.getBorrowCommitment(borrowId);
        assertEq(commitment.cumulativeAmountEnd, 0);
        assertEq(commitment.commitedAmount, 0);
        assertEq(commitment.owner, address(0));

        vm.stopPrank();
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
