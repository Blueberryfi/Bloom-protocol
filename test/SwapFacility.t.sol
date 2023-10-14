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
import {LibRLP} from "solady/utils/LibRLP.sol";

import {SwapFacility} from "src/SwapFacility.sol";
import {ISwapFacility} from "src/interfaces/ISwapFacility.sol";
import {IWhitelist} from "src/interfaces/IWhitelist.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {MockWhitelist} from "./mock/MockWhitelist.sol";
import {MockBloomPool} from "./mock/MockBloomPool.sol";
import {MockOracle} from "./mock/MockOracle.sol";

contract SwapFacilityTest is Test {
    SwapFacility internal swap;
    MockBloomPool internal pool;

    MockERC20 internal stableToken;
    MockERC20 internal billyToken;
    MockERC20 internal randomToken;
    MockWhitelist internal whitelist;
    MockOracle internal usdcOracle;
    MockOracle internal ib01Oracle;

    address internal user = makeAddr("user");
    address internal user2 = makeAddr("user2");

    // ============== Redefined Errors ===============
    error InvalidAddress();
    error InvalidToken();
    error NotPool();
    error NotWhitelisted();
    error ExtremePrice();

    // ============== Redefined Events ===============
    event PoolUpdated(address indexed oldPool, address indexed newPool);
    event Swap(address inToken, address outToken, uint256 inAmount, uint256 outAmount, address indexed user);

    function setUp() public {
        stableToken = new MockERC20(6);
        vm.label(address(stableToken), "StableToken");
        billyToken = new MockERC20(18);
        vm.label(address(billyToken), "BillyToken");
        randomToken = new MockERC20(18);
        vm.label(address(randomToken), "RandomToken");
        usdcOracle = new MockOracle(8);
        vm.label(address(usdcOracle), "StableTokenOracle");
        ib01Oracle = new MockOracle(8);
        vm.label(address(ib01Oracle), "BillyTokenOracle");
        usdcOracle.setAnswer(100000000);
        ib01Oracle.setAnswer(10000000000);
        whitelist = new MockWhitelist();

        uint256 deployerNonce = vm.getNonce(address(this));

        swap = new SwapFacility(
            address(stableToken),
            address(billyToken),
            address(usdcOracle),
            address(ib01Oracle),
            IWhitelist(address(whitelist)),
            0.002e4,
            LibRLP.computeAddress(address(this), deployerNonce + 1),
            0.995e8,
            type(uint256).max
        );
        vm.label(address(swap), "SwapFacility");

        assertEq(swap.underlyingToken(), address(stableToken));
        assertEq(swap.billyToken(), address(billyToken));
        assertEq(swap.underlyingTokenOracle(), address(usdcOracle));
        assertEq(swap.billyTokenOracle(), address(ib01Oracle));

        pool = new MockBloomPool(
            address(stableToken),
            address(billyToken),
            address(swap)
        );
        vm.label(address(pool), "MockBloomPool");

        assertEq(swap.pool(), address(pool));
    }

    function initPreHoldSwap() public {
        stableToken.mint(address(pool), 10000_000000);
        pool.initiatePreHoldSwap();
    }

    function completePreHoldSwap() public {
        initPreHoldSwap();
        whitelist.add(user);

        billyToken.mint(user, 100.2 ether);
        startHoax(user);
        billyToken.approve(address(swap), 100.2 ether);
        swap.swap(address(billyToken), address(stableToken), 100.2 ether, new bytes32[](0));
        vm.stopPrank();
    }

    function test_swap_fail_with_InvalidToken_stage_0() public {
        whitelist.add(user);
        startHoax(user);

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(randomToken), address(billyToken), 100 ether, new bytes32[](0));

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(stableToken), address(randomToken), 100 ether, new bytes32[](0));

        vm.stopPrank();
    }

    function test_swap_fail_with_NotPool_stage_0() public {
        whitelist.add(user);
        startHoax(user);

        vm.expectRevert(NotPool.selector);
        swap.swap(address(stableToken), address(billyToken), 100 ether, new bytes32[](0));

        vm.stopPrank();
    }

    function test_swap_success_stage_0() public {
        initPreHoldSwap();
    }

    function test_swap_fail_with_NotWhitelisted_stage_1() public {
        initPreHoldSwap();

        startHoax(user);

        vm.expectRevert(NotWhitelisted.selector);
        swap.swap(address(randomToken), address(stableToken), 100 ether, new bytes32[](0));

        vm.stopPrank();
    }

    function test_swap_fail_with_InvalidToken_stage_1() public {
        initPreHoldSwap();
        whitelist.add(user);
        startHoax(user);

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(randomToken), address(stableToken), 100 ether, new bytes32[](0));

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(billyToken), address(randomToken), 100 ether, new bytes32[](0));

        vm.stopPrank();
    }

    function test_swap_success_stage_1() public {
        initPreHoldSwap();
        whitelist.add(user);

        startHoax(user);
        uint256 inAmount = 10e18;
        billyToken.mint(user, inAmount);
        billyToken.approve(address(swap), inAmount);

        vm.expectEmit(true, true, true, true, address(swap));
        uint256 outAmount = inAmount * (1e4 + swap.spread()) / 1e14;
        emit Swap(address(billyToken), address(stableToken), inAmount, outAmount, user);
        swap.swap(address(billyToken), address(stableToken), inAmount, new bytes32[](0));

        assertEq(stableToken.balanceOf(user), outAmount);
        assertEq(billyToken.balanceOf(address(pool)), inAmount);

        vm.stopPrank();
    }

    function test_swap_fail_with_InvalidPrice_stage_1() public {
        initPreHoldSwap();
        whitelist.add(user);

        startHoax(user);
        uint256 inAmount = 10e18;
        billyToken.mint(user, inAmount);
        billyToken.approve(address(swap), inAmount);
        usdcOracle.setAnswer(90_000_000);
        vm.expectRevert(ExtremePrice.selector);
        swap.swap(address(billyToken), address(stableToken), 100 ether, new bytes32[](0));

        vm.stopPrank();
    }

    function test_swap_fail_with_InvalidToken_stage_2() public {
        completePreHoldSwap();

        startHoax(user);

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(randomToken), address(billyToken), 100 ether, new bytes32[](0));

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(stableToken), address(randomToken), 100 ether, new bytes32[](0));

        vm.stopPrank();
    }

    function test_swap_fail_with_NotPool_stage_2() public {
        completePreHoldSwap();
        whitelist.add(user);
        startHoax(user);

        vm.expectRevert(NotPool.selector);
        swap.swap(address(billyToken), address(stableToken), 100 ether, new bytes32[](0));

        vm.stopPrank();
    }

    function test_swap_success_stage_2() public {
        completePreHoldSwap();

        pool.initiatePostHoldSwap();
    }

    function test_swap_fail_with_NotWhitelisted_stage_3() public {
        completePreHoldSwap();
        pool.initiatePostHoldSwap();

        startHoax(user2);

        vm.expectRevert(NotWhitelisted.selector);
        swap.swap(address(randomToken), address(stableToken), 100 ether, new bytes32[](0));

        vm.stopPrank();
    }

    function test_swap_fail_with_InvalidToken_stage_3() public {
        completePreHoldSwap();
        pool.initiatePostHoldSwap();

        startHoax(user);

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(randomToken), address(stableToken), 100 ether, new bytes32[](0));

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(billyToken), address(randomToken), 100 ether, new bytes32[](0));

        vm.stopPrank();
    }

    function test_swap_success_stage_3() public {
        completePreHoldSwap();
        pool.initiatePostHoldSwap();

        startHoax(user);
        uint256 inAmount = 1001_500000;
        stableToken.mint(user, inAmount);
        stableToken.approve(address(swap), inAmount);

        uint256 beforeBalance = billyToken.balanceOf(user);
        vm.expectEmit(true, true, true, true, address(swap));
        uint256 outAmount = inAmount * (1e4 + swap.spread()) * 1e6;
        emit Swap(address(stableToken), address(billyToken), inAmount, outAmount, user);
        swap.swap(address(stableToken), address(billyToken), inAmount, new bytes32[](0));

        assertEq(billyToken.balanceOf(user), beforeBalance + outAmount);
        assertEq(stableToken.balanceOf(address(pool)), 1001_500000);

        vm.stopPrank();
    }
}
