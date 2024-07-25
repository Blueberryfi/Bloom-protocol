// SPDX-License-Identifier: BUSL-1.1
/*
██████╗░██╗░░░░░░█████╗░░█████╗░███╗░░░███╗
██╔══██╗██║░░░░░██╔══██╗██╔══██╗████╗░████║
██████╦╝██║░░░░░██║░░██║██║░░██║██╔████╔██║
██╔══██╗██║░░░░░██║░░██║██║░░██║██║╚██╔╝██║
██████╦╝███████╗╚█████╔╝╚█████╔╝██║░╚═╝░██║
╚═════╝░╚══════╝░╚════╝░░╚════╝░╚═╝░░░░░╚═╝
*/

pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MockERC20} from "./mock/MockERC20.sol";
import {MockOracle} from "./mock/MockOracle.sol";

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

        BloomFactory factoryInstance = new BloomFactory();
        address factoryProxy = address(new TransparentUpgradeableProxy(address(factoryInstance), multisig, ""));
        factory = BloomFactory(factoryProxy);
        factory.initialize(address(this));

        registry = new ExchangeRateRegistry(multisig, address(factory));

        underlyingToken = new MockERC20("USDC", "USDC", 6);
        billToken = new MockERC20("ib01", "ib01", 18);

        underlyingOracle = new MockOracle(8);
        billOracle = new MockOracle(8);

        poolParams = IBloomFactory.PoolParams({
            borrowerWhiteList: address(2),  // Set to address(2) b/c irrelevant for tests
            lenderReturnBpsFeed: address(3), // Set to address(3) b/c irrelevant for tests
            emergencyHandler: address(4), // Set to address(4) b/c irrelevant for tests
            leverageBps: 0,
            minBorrowDeposit: 100e18,
            commitPhaseDuration: 3 days,
            swapTimeout: 7 days,
            poolPhaseDuration: 180 days
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

        assertFalse(address(pool) == address(0));
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
        (bool isRegistered, bool isActive, bool emergency, ) = registry.tokenInfos(address(pool));
        assertEq(isRegistered, true);
        assertEq(isActive, true);
        assertEq(emergency, false);
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