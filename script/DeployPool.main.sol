// SPDX-License-Identifier: BUSL-1.1
/*
██████╗░██╗░░░░░░█████╗░░█████╗░███╗░░░███╗
██╔══██╗██║░░░░░██╔══██╗██╔══██╗████╗░████║
██████╦╝██║░░░░░██║░░██║██║░░██║██╔████╔██║
██╔══██╗██║░░░░░██║░░██║██║░░██║██║╚██╔╝██║
██████╦╝███████╗╚█████╔╝╚█████╔╝██║░╚═╝░██║
╚═════╝░╚══════╝░╚════╝░░╚════╝░╚═╝░░░░░╚═╝
*/

pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Script, console2} from "forge-std/Script.sol";
import {LibRLP} from "solady/utils/LibRLP.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {MerkleWhitelist} from "../src/MerkleWhitelist.sol";
import {BPSFeed} from "../src/BPSFeed.sol";
import {BloomPool} from "../src/BloomPool.sol";
import {SwapFacility} from "../src/SwapFacility.sol";
import {ExchangeRateRegistry} from "../src/helpers/ExchangeRateRegistry.sol";
import {TBYRateProviderFactory} from "../src/helpers/TBYRateProviderFactory.sol";
import {BloomFactory, IBloomFactory} from "../src/BloomFactory.sol";
import {EmergencyHandler} from "../src/EmergencyHandler.sol";

import {ISwapFacility} from "../src/interfaces/ISwapFacility.sol";
import {IWhitelist} from "../src/interfaces/IWhitelist.sol";
import {IRegistry} from "../src/interfaces/IRegistry.sol";


contract Deploy is Test, Script {
    address internal constant DEPLOYER = 0x21c2bd51f230D69787DAf230672F70bAA1826F67;
    address internal constant MULTISIG = 0x91797a79fEA044D165B00D236488A0f2D22157BC;
    address internal constant TREASURY = 0xFdC004B6B92b45B224d37dc45dBA5cA82c1e08f2;

    address internal constant UNDERLYING_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address internal constant BILL_TOKEN = 0xCA30c93B02514f86d5C86a6e375E3A330B435Fb5; //bIB01

    // chainlink feeds
    address internal constant USDCUSD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal constant IB01USD = 0x32d1463EB53b73C095625719Afa544D5426354cB;
                            
    IWhitelist internal constant WHITELIST_BORROW = IWhitelist(0x95e67b8d297C2E65B6385D9786CDb172B9554f00);
    IWhitelist internal constant WHITELIST_SWAP = IWhitelist(0x1AE4EE9205Be92b8fc96f9C613f0486a4d9496Ae);
    address internal constant LENDER_RETURN_BPS_FEED = 0xDe1f5F2d69339171D679FB84E4562febb71F36E6;

    uint256 internal constant SPREAD = 0.0125e4; // 0.125%
    uint256 internal constant MIN_STABLE_VALUE = 0.995e8;
    uint256 internal constant MAX_BILL_VALUE = 112.6e8;
    uint256 internal constant BPS = 1e4;
    uint256 internal constant commitPhaseDuration = 57 hours;
    uint256 internal constant poolPhaseDuration = 180 days;
    uint256 internal constant swapTimeout = 7 days;

    // Protocol
    BloomPool internal pool;
    SwapFacility internal swap;
    address internal constant BLOOM_FACTORY = address(0);
    address internal constant EXCHANGE_RATE_REGISTRY = address(0);

    function run() public {
        vm.startBroadcast();

        // // Deploy emergency handler logic
        EmergencyHandler emergencyHandlerImplementation = new EmergencyHandler();

        // Deploy proxy for emergency handler
        TransparentUpgradeableProxy emergencyHandlerProxy = new TransparentUpgradeableProxy(
            address(emergencyHandlerImplementation),
            MULTISIG,
            ""
        );

        IBloomFactory.PoolParams memory poolParams = IBloomFactory.PoolParams(
            address(WHITELIST_BORROW),
            address(LENDER_RETURN_BPS_FEED),
            address(emergencyHandlerProxy),
            60e4,
            10.0e6,
            commitPhaseDuration,
            swapTimeout,
            poolPhaseDuration
        );

        IBloomFactory.SwapFacilityParams memory swapFacilityParams = IBloomFactory.SwapFacilityParams(
            USDCUSD,
            IB01USD,
            address(WHITELIST_SWAP),
            SPREAD,
            MIN_STABLE_VALUE,
            MAX_BILL_VALUE
        );

        pool = IBloomFactory(BLOOM_FACTORY).create(
            "Term Bound Yield 6 month apr-2024-BatchA",
            "TBY-apr24(a)",
            UNDERLYING_TOKEN,
            BILL_TOKEN,
            IRegistry(EXCHANGE_RATE_REGISTRY),
            poolParams,
            swapFacilityParams,
            vm.getNonce(address(BLOOM_FACTORY))
        );
        vm.label(address(pool), "BloomPool");
        console2.log("BloomPool deployed at:", address(pool));

        swap = SwapFacility(pool.SWAP_FACILITY());
        vm.label(address(swap), "SwapFacility");
        console2.log("SwapFacility deployed at:", address(swap));

        vm.stopBroadcast();
    }

    function _deploySwapFacility() internal {
        uint256 deployerNonce = vm.getNonce(msg.sender);

        swap = new SwapFacility(
            UNDERLYING_TOKEN, 
            BILL_TOKEN,
            USDCUSD,
            IB01USD,
            IWhitelist(address(WHITELIST_SWAP)),
            SPREAD,
            LibRLP.computeAddress(msg.sender, deployerNonce + 1),
            MIN_STABLE_VALUE,
            MAX_BILL_VALUE
        );
        vm.label(address(swap), "SwapFacility");
        console2.log("SwapFacility deployed at:", address(swap));
    }
}
