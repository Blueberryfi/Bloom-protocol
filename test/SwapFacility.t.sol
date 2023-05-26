// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {SwapFacility} from "src/SwapFacility.sol";
import {ISwapFacility} from "src/interfaces/ISwapFacility.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {MockWhitelist} from "./mock/MockWhitelist.sol";
import {MockBillyPool} from "./mock/MockBillyPool.sol";
import {MockOracle} from "./mock/MockOracle.sol";

contract SwapFacilityTest is Test {
    SwapFacility internal swap;
    MockBillyPool internal pool;

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
    error PoolNotSet();
    error NotPool();
    error NotWhitelisted();

    // ============== Redefined Events ===============
    event PoolUpdated(address indexed oldPool, address indexed newPool);
    event Swap(
        address inToken,
        address outToken,
        uint256 inAmount,
        uint256 outAmount,
        address indexed user
    );

    function setUp() public {
        stableToken = new MockERC20();
        vm.label(address(stableToken), "StableToken");
        billyToken = new MockERC20();
        vm.label(address(billyToken), "BillyToken");
        randomToken = new MockERC20();
        vm.label(address(randomToken), "RandomToken");
        usdcOracle = new MockOracle();
        vm.label(address(usdcOracle), "StableTokenOracle");
        ib01Oracle = new MockOracle();
        vm.label(address(ib01Oracle), "BillyTokenOracle");
        usdcOracle.setAnswer(100000000);
        ib01Oracle.setAnswer(10000000000);
        whitelist = new MockWhitelist();

        swap = new SwapFacility(
            address(stableToken),
            address(billyToken),
            address(usdcOracle),
            address(ib01Oracle),
            address(whitelist),
            15000000
        );
        vm.label(address(swap), "SwapFacility");

        assertEq(swap.underlyingToken(), address(stableToken));
        assertEq(swap.billyToken(), address(billyToken));
        assertEq(swap.underlyingTokenOracle(), address(usdcOracle));
        assertEq(swap.billyTokenOracle(), address(ib01Oracle));

        pool = new MockBillyPool(
            address(stableToken),
            address(billyToken),
            address(swap)
        );
        vm.label(address(pool), "MockBillyPool");
    }

    function initPreHoldSwap() public {
        swap.setPool(address(pool));
        stableToken.mint(address(pool), 10000_000000);
        pool.initiatePreHoldSwap();
    }

    function completePreHoldSwap() public {
        initPreHoldSwap();
        whitelist.add(user);

        billyToken.mint(user, 100.2 ether);
        startHoax(user);
        billyToken.approve(address(swap), 100.2 ether);
        swap.swap(address(billyToken), address(stableToken), 100.2 ether, "");
        vm.stopPrank();
    }

    function test_setPool_fail_with_UNAUTHORIZED() public {
        vm.prank(user);
        vm.expectRevert("UNAUTHORIZED");
        swap.setPool(address(pool));
    }

    function test_setPool() public {
        swap.setPool(address(pool));
        assertEq(swap.pool(), address(pool));
    }

    function test_setSpreadPrice_fail_with_UNAUTHORIZED() public {
        vm.prank(user);
        vm.expectRevert("UNAUTHORIZED");
        swap.setSpreadPrice(20000000);
    }

    function test_setSpreadPrice() public {
        swap.setSpreadPrice(20000000);
        assertEq(swap.spreadPrice(), 20000000);
    }

    function test_swap_fail_with_PoolNotSet() public {
        startHoax(user);

        vm.expectRevert(PoolNotSet.selector);
        pool.initiatePreHoldSwap();

        vm.stopPrank();
    }

    function test_swap_fail_with_InvalidToken_stage_0() public {
        swap.setPool(address(pool));
        whitelist.add(user);
        startHoax(user);

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(randomToken), address(billyToken), 100 ether, "");

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(stableToken), address(randomToken), 100 ether, "");

        vm.stopPrank();
    }

    function test_swap_fail_with_NotPool_stage_0() public {
        swap.setPool(address(pool));
        whitelist.add(user);
        startHoax(user);

        vm.expectRevert(NotPool.selector);
        swap.swap(address(stableToken), address(billyToken), 100 ether, "");

        vm.stopPrank();
    }

    function test_swap_success_stage_0() public {
        initPreHoldSwap();
    }

    function test_swap_fail_with_NotWhitelisted_stage_1() public {
        initPreHoldSwap();

        startHoax(user);

        vm.expectRevert(NotWhitelisted.selector);
        swap.swap(address(randomToken), address(stableToken), 100 ether, "");

        vm.stopPrank();
    }

    function test_swap_fail_with_InvalidToken_stage_1() public {
        initPreHoldSwap();
        whitelist.add(user);
        startHoax(user);

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(randomToken), address(stableToken), 100 ether, "");

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(billyToken), address(randomToken), 100 ether, "");

        vm.stopPrank();
    }

    function test_swap_success_stage_1() public {
        initPreHoldSwap();
        whitelist.add(user);

        startHoax(user);
        billyToken.mint(user, 10 ether);
        billyToken.approve(address(swap), 10 ether);

        vm.expectEmit(true, true, true, true, address(swap));
        emit Swap(address(billyToken), address(stableToken), 10 ether, 998_500000, user);
        swap.swap(address(billyToken), address(stableToken), 10 ether, "");

        assertEq(stableToken.balanceOf(user), 998_500000);
        assertEq(billyToken.balanceOf(address(pool)), 10 ether);

        vm.stopPrank();
    }

    function test_swap_fail_with_InvalidToken_stage_2() public {
        completePreHoldSwap();

        startHoax(user);

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(randomToken), address(billyToken), 100 ether, "");

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(stableToken), address(randomToken), 100 ether, "");

        vm.stopPrank();
    }

    function test_swap_fail_with_NotPool_stage_2() public {
        completePreHoldSwap();
        whitelist.add(user);
        startHoax(user);

        vm.expectRevert(NotPool.selector);
        swap.swap(address(billyToken), address(stableToken), 100 ether, "");

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
        swap.swap(address(randomToken), address(stableToken), 100 ether, "");

        vm.stopPrank();
    }

    function test_swap_fail_with_InvalidToken_stage_3() public {
        completePreHoldSwap();
        pool.initiatePostHoldSwap();

        startHoax(user);

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(randomToken), address(stableToken), 100 ether, "");

        vm.expectRevert(InvalidToken.selector);
        swap.swap(address(billyToken), address(randomToken), 100 ether, "");

        vm.stopPrank();
    }

    function test_swap_success_stage_3() public {
        completePreHoldSwap();
        pool.initiatePostHoldSwap();

        startHoax(user);
        stableToken.mint(user, 1001_500000);
        stableToken.approve(address(swap), 1001_500000);

        uint256 beforeBalance = billyToken.balanceOf(user);
        vm.expectEmit(true, true, true, true, address(swap));
        emit Swap(address(stableToken), address(billyToken), 1001_500000, 10 ether, user);
        swap.swap(address(stableToken), address(billyToken), 1001_500000, "");

        assertEq(billyToken.balanceOf(user), beforeBalance + 10 ether);
        assertEq(stableToken.balanceOf(address(pool)), 1001_500000);

        vm.stopPrank();
    }
}
