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

import {MockERC20, ERC20} from "./mock/MockERC20.sol";
import {MockBloomPool} from "./mock/MockBloomPool.sol";
import {MockSwapFacility} from "./mock/MockSwapFacility.sol";
import {MockOracle} from "./mock/MockOracle.sol";
import {MockBPSFeed} from "./mock/MockBPSFeed.sol";
import {MockWhitelist} from "./mock/MockWhitelist.sol";

import {AssetCommitment} from "src/lib/CommitmentsLib.sol";
import {EmergencyHandler, IEmergencyHandler} from "src/EmergencyHandler.sol";
import {ExchangeRateRegistry} from "src/helpers/ExchangeRateRegistry.sol";

import {IBloomPool} from "src/interfaces/IBloomPool.sol";
import {IWhitelist} from "src/interfaces/IWhitelist.sol";

contract EmergencyHandlerTest is Test {
    address internal multisig = makeAddr("multisig");
    address internal rando = makeAddr("rando");
    MockERC20 internal stableToken;
    MockERC20 internal billyToken;
    MockBloomPool internal pool;
    MockSwapFacility internal swap;
    MockBPSFeed internal bpsFeed;
    MockOracle internal stableOracle;
    MockOracle internal billyOracle;
    MockWhitelist internal whitelist;

    ExchangeRateRegistry internal registry;
    EmergencyHandler internal handler;

    uint256 internal constant BPS = 1e4;
    uint256 internal constant BPS_FEED_VALUE = 1.04e4;  
    uint256 internal constant LEVERAGE_BPS = 4e4;

    function setUp() public {
        stableToken = new MockERC20(6);
        vm.label(address(stableToken), "stableToken");
        billyToken = new MockERC20(18);
        vm.label(address(billyToken), "billyToken");
        stableOracle = new MockOracle(8);
        billyOracle = new MockOracle(8);
        bpsFeed = new MockBPSFeed();
        swap = new MockSwapFacility(stableToken, billyToken, stableOracle, billyOracle);
        whitelist = new MockWhitelist();
        swap.setWhitelist(IWhitelist(address(whitelist)));
        pool = new MockBloomPool(address(stableToken), address(billyToken), address(swap));
        vm.label(address(pool), "pool");
        pool.setCommitPhaseEnd(block.timestamp + 100000);
        address factory = makeAddr("factory");
        registry = new ExchangeRateRegistry(multisig, factory);

        vm.startPrank(multisig);
        registry.registerToken(IBloomPool(address(pool)));
        handler = new EmergencyHandler();
        handler.initialize(registry, multisig);
        
        vm.stopPrank();
    }

    function test_getRegistry() public {
        assertEq(address(registry), address(handler.REGISTRY()));
    }

    // function test_redemptionInfo() public {
    //     _registerPool(stableToken, 100e6);

    //     (IEmergencyHandler.Token memory underlyingInfo, ) = handler.redemptionInfo(address(pool));
    //     assertEq(underlyingInfo.token, address(stableToken));
    //     assertEq(underlyingInfo.rate, 1e8);
    // }

    function test_failedRegistrations() public {
        // Fail if non BloomPool address tries to register a pool
        // empty data
        IEmergencyHandler.RedemptionInfo memory redemptionInfo = IEmergencyHandler.RedemptionInfo(
            IEmergencyHandler.Token(address(stableToken), 1e8, stableToken.decimals()),
            IEmergencyHandler.Token(address(billyToken), 100e8, billyToken.decimals()),
            IEmergencyHandler.PoolAccounting(
                0,
                0,
                0,
                0 * BPS / LEVERAGE_BPS,
                stableToken.balanceOf(address(handler)),
                billyToken.balanceOf(address(handler))
            ),
            false
        );
        vm.startPrank(rando);
        vm.expectRevert(IEmergencyHandler.CallerNotBloomPool.selector);
        handler.registerPool(redemptionInfo);
        vm.stopPrank();

        // Register pool for next test
        _registerPool(100e6);

        // Fail if pool tries to register again
        vm.expectRevert(IEmergencyHandler.PoolAlreadyRegistered.selector);
        vm.startPrank(address(pool));
        handler.registerPool(redemptionInfo);
        vm.stopPrank();
    }

    function test_borrowerClaimStatus() public {
        _registerPool(100e6);
        (bool hasClaimed, ) = handler.borrowerClaimStatus(address(pool), 0);
        assertEq(hasClaimed, false);
    }

    function test_redeemLender() public {
        address lender = makeAddr("lender");
        uint256 borrowAmount = 100e6;
        pool.mint(lender, borrowAmount * LEVERAGE_BPS / BPS);
        _registerPool(borrowAmount);

        // Fails if lender tries to redeem from a non-registered pool
        MockBloomPool pool2 = new MockBloomPool(address(stableToken), address(billyToken), address(swap));
        vm.startPrank(lender);
        vm.expectRevert(IEmergencyHandler.PoolNotRegistered.selector);
        handler.redeem(IBloomPool(address(pool2)));
        vm.stopPrank();

        // Successfully redeem
        vm.startPrank(lender);
        uint256 amountRedeemed = handler.redeem(IBloomPool(address(pool)));
        vm.stopPrank();

        assertEq(amountRedeemed, 408000000);
        assertEq(stableToken.balanceOf(lender), 408000000);
        assertEq(stableToken.balanceOf(address(handler)), 92000000);
        assertEq(ERC20(address(pool)).balanceOf(lender), 0);

        // Lender tries to redeem again
        vm.startPrank(lender);
        vm.expectRevert(IEmergencyHandler.NoTokensToRedeem.selector);
        handler.redeem(IBloomPool(address(pool)));
        vm.stopPrank();
    }

    function test_redeemBorrower() public {
        address borrower = makeAddr("borrower");
        _registerPool(100e6);

        uint256 id = 0;

        MockBloomPool.AssetCommitment memory commitment = MockBloomPool.AssetCommitment({
            owner: borrower,
            committedAmount: 100e6,
            cumulativeAmountEnd: 100e6
        });

        pool.setBorrowerCommitment(id, commitment);

        // Fail if rando tries to redeem
        vm.startPrank(rando);
        vm.expectRevert(IEmergencyHandler.InvalidOwner.selector);
        handler.redeem(IBloomPool(address(pool)), id);
        vm.stopPrank();
        
        // Successfully redeem
        vm.startPrank(borrower);
        uint256 amountRedeemed = handler.redeem(IBloomPool(address(pool)), id);
        vm.stopPrank();

        assertEq(amountRedeemed, 92000000);
        assertEq(stableToken.balanceOf(borrower), 92000000);
        assertEq(stableToken.balanceOf(address(handler)), 408000000);

        // Fail if borrower tries to redeem again
        vm.startPrank(borrower);
        vm.expectRevert(IEmergencyHandler.NoTokensToRedeem.selector);
        handler.redeem(IBloomPool(address(pool)), id);
        vm.stopPrank();
    }

    function test_marketMakerSwap() public {
        address marketMaker = _makeWhitelistedAddr("marketMaker");
        uint256 stableAmount = (100e6 * LEVERAGE_BPS / BPS) * 1e18 / 1.025e18;
        stableToken.mint(marketMaker, stableAmount);
        _registerPoolWithBillTokens(100e6);
        uint256 startingStableBalance = stableToken.balanceOf(address(handler));
        uint256 startingBillyBalance = billyToken.balanceOf(address(handler));
        // Successfully swap
        vm.startPrank(marketMaker);
        stableToken.approve(address(handler), stableAmount);
        uint256 outAmount = handler.swap(IBloomPool(address(pool)), stableAmount, new bytes32[](0));
        vm.stopPrank();

        assertEq(stableToken.balanceOf(address(handler)), startingStableBalance + stableAmount);
        assertEq(billyToken.balanceOf(address(handler)), startingBillyBalance - outAmount);
        assertEq(billyToken.balanceOf(marketMaker), outAmount);
        assertEq(stableToken.balanceOf(marketMaker), 0);
    }

    function _registerPool(uint256 borrowAmount) internal {
        pool.setState(MockBloomPool.State.EmergencyExit);
        pool.setEmergencyHandler(address(handler));

        stableOracle.setAnswer(1e8);
        billyOracle.setAnswer(102.5e8);
        bpsFeed.setRate(1e4);

        uint256 lenderAmount = borrowAmount * LEVERAGE_BPS / BPS;
        stableToken.mint(address(handler), lenderAmount);
        stableToken.mint(address(handler), borrowAmount);

        uint256 scalingFactor = 10 ** (billyToken.decimals() - stableToken.decimals());
        uint256 additionalValue = billyToken.balanceOf(address(handler)) * uint256(billyOracle.latestAnswer()) / 1e8 / scalingFactor;
        uint256 expectedTotalBalance = stableToken.balanceOf(address(handler)) + additionalValue;

        uint256 lenderYield = lenderAmount * (BPS_FEED_VALUE - BPS) * 180 days / 360 days / BPS;
        uint256 lenderDistro = lenderAmount + lenderYield;
        uint256 borrowerDistro = expectedTotalBalance - lenderDistro;

        IEmergencyHandler.RedemptionInfo memory redemptionInfo = IEmergencyHandler.RedemptionInfo(
            IEmergencyHandler.Token(address(stableToken), 1e8, stableToken.decimals()),
            IEmergencyHandler.Token(address(billyToken), 102.5e8, billyToken.decimals()),
            IEmergencyHandler.PoolAccounting(
                lenderDistro,
                borrowerDistro,
                lenderAmount,
                lenderAmount * BPS / LEVERAGE_BPS,
                stableToken.balanceOf(address(handler)),
                billyToken.balanceOf(address(handler))
            ),
            true
        );

        vm.startPrank(address(pool));
        handler.registerPool(redemptionInfo);
        vm.stopPrank();
    }

    function _registerPoolWithBillTokens(uint256 borrowAmount) public {
        pool.setState(MockBloomPool.State.EmergencyExit);
        pool.setEmergencyHandler(address(handler));

        stableOracle.setAnswer(1e8);
        billyOracle.setAnswer(102.5e8);
        bpsFeed.setRate(1e4);

        uint256 lenderAmount = borrowAmount * LEVERAGE_BPS / BPS;
        stableToken.mint(address(handler), lenderAmount * 1e18 / 1.025e18);
        billyToken.mint(address(handler), lenderAmount * 1e12 / 2);

        uint256 scalingFactor = 10 ** (billyToken.decimals() - stableToken.decimals());
        uint256 additionalValue = billyToken.balanceOf(address(handler)) * uint256(billyOracle.latestAnswer()) / 1e8 / scalingFactor;
        uint256 expectedTotalBalance = stableToken.balanceOf(address(handler)) + additionalValue;

        uint256 lenderYield = lenderAmount * (BPS_FEED_VALUE - BPS) * 180 days / 360 days / BPS;
        uint256 lenderDistro = lenderAmount + lenderYield;
        uint256 borrowerDistro = expectedTotalBalance - lenderDistro;

        IEmergencyHandler.RedemptionInfo memory redemptionInfo = IEmergencyHandler.RedemptionInfo(
            IEmergencyHandler.Token(address(stableToken), 1e8, stableToken.decimals()),
            IEmergencyHandler.Token(address(billyToken), uint256(billyOracle.latestAnswer()), billyToken.decimals()),
            IEmergencyHandler.PoolAccounting(
                lenderDistro,
                borrowerDistro,
                lenderAmount,
                lenderAmount * BPS / LEVERAGE_BPS,
                stableToken.balanceOf(address(handler)),
                billyToken.balanceOf(address(handler))
            ),
            true
        );

        vm.startPrank(address(pool));
        handler.registerPool(redemptionInfo);
        vm.stopPrank();
    }

    function _makeWhitelistedAddr(string memory label) internal returns (address addr) {
        addr = makeAddr(string(abi.encodePacked(label, " (whitelisted)")));
        whitelist.add(addr);
    }
    
}