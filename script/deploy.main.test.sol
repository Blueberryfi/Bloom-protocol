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
import {Script, console2} from "forge-std/Script.sol";
import {LibRLP} from "solady/utils/LibRLP.sol";
import {TransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

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
    // Replace with real address if we arent deploying a new factory or registry
    address internal constant BLOOM_FACTORY_ADDRESS = address(0);
    address internal constant EXCHANGE_RATE_REGISTRY = address(0);
    address internal constant EMERGENCY_HANDLER = address(0);

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
    uint256 internal constant commitPhaseDuration = 3 days;
    uint256 internal constant poolPhaseDuration = 180 days;
    uint256 internal constant swapTimeout = 7 days;

    // True if we want to deploy a factory. False if we want to use an existing one
    bool internal constant DEPLOY_FACTORY = true;
    bool internal constant DEPLOY_EXCHANGE_RATE_REGISTRY = true;
    bool internal constant DEPLOY_EMERGENCY_HANDLER = true;
    // Aux
    // BPSFeed internal lenderReturnBpsFeed;
    // MerkleWhitelist internal whitelistBorrow;
    // MerkleWhitelist internal whitelistSwap;

    // Protocol
    BloomPool internal pool;
    SwapFacility internal swap;

    function run() public {
        vm.startBroadcast();

        // Deploy aux items
        // _deployMerkleWhitelistBorrow();
        // _deployMerkleWhitelistSwap();
        // _deployBPSFeed();

        // Deploy protocol
        BloomFactory factory = _deployBloomFactoryWithCreate2("BlueberryBloom");

        ExchangeRateRegistry exchangeRateRegistry = _deployExchangeRateRegistry(address(factory));

        // Deploy emergency handler logic
        EmergencyHandler emergencyHandlerImplementation = _deployEmergencyHandler(exchangeRateRegistry);

        // Deploy proxy for emergency handler
        TransparentUpgradeableProxy emergencyHandlerProxy = new TransparentUpgradeableProxy(
            address(emergencyHandlerImplementation),
            MULTISIG,
            ""
        );

        IBloomFactory.PoolParams memory poolParams = IBloomFactory.PoolParams(
            TREASURY,
            address(WHITELIST_BORROW),
            address(LENDER_RETURN_BPS_FEED),
            address(emergencyHandlerProxy),
            60e4,
            10.0e6,
            commitPhaseDuration,
            swapTimeout,
            poolPhaseDuration,
            0, // 0%
            0 // 0%
        );

        IBloomFactory.SwapFacilityParams memory swapFacilityParams = IBloomFactory.SwapFacilityParams(
            USDCUSD,
            IB01USD,
            address(WHITELIST_SWAP),
            SPREAD,
            MIN_STABLE_VALUE,
            MAX_BILL_VALUE
        );

        pool = factory.create(
            "Term Bound Yield 6 month feb-2024-Batch2",
            "TBY-feb-2024-Batch2",
            UNDERLYING_TOKEN,
            BILL_TOKEN,
            exchangeRateRegistry,
            poolParams,
            swapFacilityParams,
            vm.getNonce(address(factory))
        );
        vm.label(address(pool), "BloomPool");
        console2.log("BloomPool deployed at:", address(pool));

        swap = SwapFacility(pool.SWAP_FACILITY());
        vm.label(address(swap), "SwapFacility");
        console2.log("SwapFacility deployed at:", address(swap));

        vm.stopBroadcast();
    }

    /* 
    function _deployMerkleWhitelistBorrow() internal {
        whitelistBorrow = new MerkleWhitelist(
            INITIALROOTBORROW,
            INITIALOWNER
        );
        vm.label(address(whitelistBorrow), "MerkleWhitelist");
        console2.log("MerkleWhitelist deployed at:", address(whitelistBorrow));
    }

    function _deployMerkleWhitelistSwap() internal {
        whitelistSwap = new MerkleWhitelist(
        INITIALROOTSWAP,
        INITIALOWNER
    );
        vm.label(address(whitelistSwap), "MerkleWhitelist");
        console2.log("MerkleWhitelist deployed at:", address(whitelistSwap));
    }

    function _deployBPSFeed() internal {
        lenderReturnBpsFeed = new BPSFeed();
        vm.label(address(lenderReturnBpsFeed), "BPSFeed");
        console2.log("BPSFeed deployed at:", address(lenderReturnBpsFeed));
    }
    */

    function _deployBloomFactoryWithCreate2(bytes32 salt) internal returns (BloomFactory) {
        if (!DEPLOY_FACTORY) {
            console2.log("Factory previously deployed at: ", BLOOM_FACTORY_ADDRESS);
            return BloomFactory(BLOOM_FACTORY_ADDRESS);
        } else {
            address factoryAddr = address(new BloomFactory{salt: salt}(DEPLOYER));
            vm.label(factoryAddr, "BloomFactory");
            console2.log("BloomFactory deployed at:", factoryAddr);
            return BloomFactory(factoryAddr);
        }
    }

    function _deployExchangeRateRegistry(address bloomFactory) internal returns (ExchangeRateRegistry) {
        if (DEPLOY_EXCHANGE_RATE_REGISTRY) {
            address factoryAddress = DEPLOY_FACTORY ? address(bloomFactory) : BLOOM_FACTORY_ADDRESS;

            ExchangeRateRegistry registry = new ExchangeRateRegistry(MULTISIG, factoryAddress);
            vm.label(address(registry), "ExchangeRateRegistry");
            console2.log("ExchangeRateRegistry deployed at: ", address(registry));
            return registry;
        } else {
            console2.log("Registry previously deployed at: ", EXCHANGE_RATE_REGISTRY);
            return ExchangeRateRegistry(EXCHANGE_RATE_REGISTRY);
        }
    }

    function _deployEmergencyHandler(ExchangeRateRegistry exchangeRateRegistry) internal returns (EmergencyHandler) {
        if (DEPLOY_EMERGENCY_HANDLER) {
            EmergencyHandler emergencyHandler = new EmergencyHandler(exchangeRateRegistry);
            vm.label(address(emergencyHandler), "EmergencyHandler");
            console2.log("EmergencyHandler deployed at: ", address(emergencyHandler));
            return emergencyHandler;
        } else {
            console2.log("EmergencyHandler previously deployed at: ", EMERGENCY_HANDLER);
            return EmergencyHandler(EMERGENCY_HANDLER);
        }
    }

}
