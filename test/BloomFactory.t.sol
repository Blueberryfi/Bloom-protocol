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
import {MockERC20} from "./mock/MockERC20.sol";
import {MockOracle} from "./mock/MockOracle.sol";

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {LibRLP} from "solady/utils/LibRLP.sol";

import {BloomFactory, BloomPool, IWhitelist, IBloomFactory} from "src/BloomFactory.sol";
import {ExchangeRateRegistry} from "src/helpers/ExchangeRateRegistry.sol";

contract BloomFactoryTest is Test {
    BloomFactory public factory;
    ExchangeRateRegistry public registry;

    MockERC20 public underlyingToken;
    MockERC20 public billToken;
    MockOracle internal underlyingOracle;
    MockOracle internal billOracle;

    IBloomFactory.PoolParams public poolParams;
    IBloomFactory.SwapFacilityParams public swapFacilityParams;

    bool internal _setWrongNonce;

    function setUp() public {
        address multisig = makeAddr("multisig");

        factory = new BloomFactory();
        registry = new ExchangeRateRegistry(multisig, address(factory));

        underlyingToken = new MockERC20(8);
        billToken = new MockERC20(18);

        underlyingOracle = new MockOracle(8);
        billOracle = new MockOracle(8);

        poolParams = IBloomFactory.PoolParams({
            treasury: address(1), // Set to address(1) b/c irrelevant for tests
            borrowerWhiteList: address(2),  // Set to address(2) b/c irrelevant for tests
            lenderReturnBpsFeed: address(3), // Set to address(3) b/c irrelevant for tests
            emergencyHandler: address(4), // Set to address(4) b/c irrelevant for tests
            leverageBps: 0,
            minBorrowDeposit: 100e18,
            commitPhaseDuration: 3 days,
            preHoldSwapTimeout: 7 days,
            poolPhaseDuration: 180 days,
            lenderReturnFee: 1000,
            borrowerReturnFee: 300
        });

        swapFacilityParams = IBloomFactory.SwapFacilityParams({
            underlyingTokenOracle: address(underlyingOracle), 
            billyTokenOracle: address(billOracle), 
            swapWhitelist: address(5), // Set to address(5) b/c irrelevant for tests
            spread: 0.002e4,
            minStableValue: 0,
            maxBillyValue: type(uint256).max
        });
    }

    function testFactoryOwner() public {
        assertEq(factory.owner(), address(this));
    }

    function testCreatePool() public {
        BloomPool pool = _newPoolInstance();

        assertNotEq(address(pool), address(0));
        assertEq(factory.getLastCreatedPool(), address(pool));
        assertEq(factory.isPoolFromFactory(address(pool)), true);
    }

    function testCreatePoolFailure() public {
        _setWrongNonce = true;

        vm.expectRevert(IBloomFactory.InvalidPoolAddress.selector);
        _newPoolInstance();
    }

    function testRandomUserCreatePoolFailure() public {
        address rando = makeAddr("rando");

        vm.startPrank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        _newPoolInstance();
    }

    function testVerifyTokenActivation() public {
        BloomPool pool = _newPoolInstance();

        // Verfiy that the the factory registers and activates the token on deployment
        (bool isRegistered, bool isActive, ,) = registry.tokenInfos(address(pool));
        assertEq(isRegistered, true);
        assertEq(isActive, true);

    }

    function _newPoolInstance() private returns (BloomPool) {
        uint256 nonce = vm.getNonce(address(factory));

        if (_setWrongNonce) {
            nonce = nonce + 10;
        }

        BloomPool pool = factory.create(
            "Test TBY",
            'TBY',
            address(underlyingToken),
            address(billToken),
            registry,
            poolParams,
            swapFacilityParams,
            nonce
        );

        return pool;
    }
}