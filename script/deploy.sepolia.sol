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
    address internal constant DEPLOYER = 0x91797a79fEA044D165B00D236488A0f2D22157BC;
    address internal constant MULTISIG = address(0);
    address internal constant TREASURY = 0xE4D701c6E3bFbA3e50D1045A3cef4797b6165119;
    // Replace with real address if we arent deploying a new factory or registry
    address internal constant BLOOM_FACTORY_ADDRESS = address(0);
    address internal constant EXCHANGE_RATE_REGISTRY = address(0);
    address internal constant EMERGENCY_HANDLER = address(0);

    address internal constant UNDERLYING_TOKEN = 0xa1c511b3C5Be3C94089203845D6247D1696D7Fb9; //
    address internal constant BILL_TOKEN = 0x106c5522A76818cEdf06E885E8a8A63eb6Cf2a4b;
    //bIB01
    // MockERC20 internal UNDERLYING_TOKEN;
    // MockERC20 internal BILL_TOKEN;

    IWhitelist internal constant WHITELIST = IWhitelist(0x461796731316D6987F77f50c249bF3c272668F13);
    address internal constant BPSFEED = 0x4C46dfc9e4cCe661d6E24FE49C43adb004423541;

    // chainlink feeds
    address internal constant USDCUSD = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address internal constant IB01USD = 0xB677bfBc9B09a3469695f40477d05bc9BcB15F50;

    bytes32 internal constant INITIALROOTBORROW = 0xabc6a38afc2e6c26bad45002703dd3bae47e41d24d13e71f8e61687633acc2ea;
    bytes32 internal constant INITIALROOTSWAP = 0xabc6a38afc2e6c26bad45002703dd3bae47e41d24d13e71f8e61687633acc2ea;
    address internal constant INITIALOWNER = 0x3031303BB07C35d489cd4B7E6cCd6Fb16eA2b3a1;

    uint256 internal constant SPREAD = 0.0125e4; // 0.125%
    uint256 internal constant MIN_STABLE_VALUE = 0.995e8;
    uint256 internal constant MAX_BILL_VALUE = 107.6e8;
    uint256 internal constant BPS = 1e4;
    uint256 internal constant commitPhaseDuration = 10 days;
    uint256 internal constant poolPhaseDuration = 2 days;
    uint256 internal constant swapTimeout = 1 days;
    // True if we want to deploy a factory. False if we want to use an existing one
    bool internal constant DEPLOY_FACTORY = true;
    bool internal constant DEPLOY_EXCHANGE_RATE_REGISTRY = true;
    bool internal constant DEPLOY_EMERGENCY_HANDLER = true;
    // Aux
    // BPSFeed internal lenderReturnBpsFeed;
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
            DEPLOYER,
            ""
        );

        IBloomFactory.PoolParams memory poolParams = IBloomFactory.PoolParams(
            TREASURY,
            address(WHITELIST),
            address(BPSFEED),
            address(emergencyHandlerProxy),
            50e4,
            10.0e6,
            commitPhaseDuration,
            swapTimeout,
            poolPhaseDuration,
            300, // 3%
            0 // 0%
        );

        IBloomFactory.SwapFacilityParams memory swapFacilityParams = IBloomFactory.SwapFacilityParams(
            USDCUSD,
            IB01USD,
            address(WHITELIST),
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

        factory.transferOwnership(MULTISIG);
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

    // function _deploySwapFacility() internal {
    //     uint256 deployerNonce = vm.getNonce(msg.sender);

    //     swap = new SwapFacility(
    //         UNDERLYING_TOKEN, 
    //         BILL_TOKEN,
    //         USDCUSD,
    //         IB01USD,
    //         IWhitelist(address(WHITELIST)),
    //         SPREAD,
    //         LibRLP.computeAddress(msg.sender, deployerNonce + 1),
    //         MIN_STABLE_VALUE,
    //         MAX_BILL_VALUE
    //     );
    //     vm.label(address(swap), "SwapFacility");
    //     console2.log("SwapFacility deployed at:", address(swap));
    // }

    // function _deployBloomPool() internal {
    //     pool = new BloomPool(
    //         UNDERLYING_TOKEN,
    //         BILL_TOKEN,
    //         IWhitelist(address(WHITELIST)),
    //         address(swap),
    //         TREASURY,
    //         address(BPSFEED),
    //         EMERGENCY_HANDLER,
    //         50e4,
    //         10.0e6,
    //         commitPhaseDuration,
    //         swapTimeout,
    //         poolPhaseDuration,
    //         300, // 3%
    //         0, // 0%
    //         "Term Bound Yield 6 month feb-2024-Batch2",
    //         "TBY-feb-2024-Batch2"
    //     );
    //     console2.log("BloomPool deployed at:", address(pool));
    // }

    function _deployExchangeRateRegistry(address bloomFactory) internal returns (ExchangeRateRegistry) {
        if (DEPLOY_EXCHANGE_RATE_REGISTRY) {
            address factoryAddress = DEPLOY_FACTORY ? address(bloomFactory) : BLOOM_FACTORY_ADDRESS;

            ExchangeRateRegistry registry = new ExchangeRateRegistry(DEPLOYER, factoryAddress);
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
