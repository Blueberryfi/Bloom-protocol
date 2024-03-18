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

import {MockERC20} from "../test/mock/MockERC20.sol";

import {ISwapFacility} from "../src/interfaces/ISwapFacility.sol";
import {IWhitelist} from "../src/interfaces/IWhitelist.sol";
import {IRegistry} from "../src/interfaces/IRegistry.sol";


contract Deploy is Test, Script {
    address internal constant DEPLOYER = 0x263c0a1ff85604f0ee3f4160cAa445d0bad28dF7;
    address internal constant MULTISIG = 0x100FE48127438776484fa988598600B174C8b1Bf;
    // address internal constant TREASURY = 0xFdC004B6B92b45B224d37dc45dBA5cA82c1e08f2;
    // Replace with real address if we arent deploying a new factory or registry
    address internal BLOOM_FACTORY_IMPLEMENTATION = address(0);
    address internal BLOOM_FACTORY_PROXY_ADDRESS = address(0);
    address internal EXCHANGE_RATE_REGISTRY = address(0);
    address internal EMERGENCY_HANDLER = address(0);

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
    uint256 internal constant MAX_BILL_VALUE = 112.6e8;
    uint256 internal constant BPS = 1e4;
    uint256 internal constant commitPhaseDuration = 10 days;
    uint256 internal constant poolPhaseDuration = 2 days;
    uint256 internal constant swapTimeout = 1 days;

    // True if we want to deploy a factory. False if we want to use an existing one
    bool internal constant DEPLOY_FACTORY = true;
    bool internal constant DEPLOY_EXCHANGE_RATE_REGISTRY = true;
    bool internal constant DEPLOY_EMERGENCY_HANDLER = true;
    bool internal constant DEPLOY_FACTORY_PROXY = true;
    bool internal constant UPDATE_FACTORY = false;
    
    // Aux
    // BPSFeed internal lenderReturnBpsFeed;
    // MerkleWhitelist internal whitelistBorrow;
    // MerkleWhitelist internal whitelistSwap;

    // Protocol
    BloomPool internal pool;
    SwapFacility internal swap;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address mockUsdc = address(new MockERC20("Bloom Mock USDC", "USDC", 6));
        address mockIb01 = address(new MockERC20("Bloom Mock ib01", "ib01", 18));
        console2.log('Mock USDC: ', mockUsdc);
        console2.log('Mock IB01: ', mockIb01);

        // Deploy protocol
        (BLOOM_FACTORY_PROXY_ADDRESS, BLOOM_FACTORY_IMPLEMENTATION) = _deployBloomFactory("BloomTBYs");

        ExchangeRateRegistry registry = new ExchangeRateRegistry(DEPLOYER, BLOOM_FACTORY_PROXY_ADDRESS);
        console2.log("Registry deployed at: ", address(registry));

        // Deploy emergency handler logic
        address handlerProxy = _deployEmergencyHandler(registry);
        console2.log("EmergencyHandler deployed at: ", handlerProxy);
        IBloomFactory.PoolParams memory poolParams = IBloomFactory.PoolParams(
            address(WHITELIST),
            address(BPSFEED),
            handlerProxy,
            50e4,
            10.0e6,
            commitPhaseDuration,
            swapTimeout,
            poolPhaseDuration
        );

        IBloomFactory.SwapFacilityParams memory swapFacilityParams = IBloomFactory.SwapFacilityParams(
            USDCUSD,
            IB01USD,
            address(WHITELIST),
            SPREAD,
            MIN_STABLE_VALUE,
            MAX_BILL_VALUE
        );

        pool = BloomFactory(BLOOM_FACTORY_PROXY_ADDRESS).create(
            "Test Bloom Pool 1",
            "TBY-1",
            mockUsdc,
            mockIb01,
            registry,
            poolParams,
            swapFacilityParams,
            vm.getNonce(BLOOM_FACTORY_PROXY_ADDRESS)
        );
        console2.log('TBY-1: ', address(pool));
        // swap = SwapFacility(pool.SWAP_FACILITY());
        // vm.label(address(swap), "SwapFacility");
        // console2.log("SwapFacility deployed at:", address(swap));

        //vm.stopBroadcast();
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

    function _deployBloomFactory(bytes32 salt) internal returns (address, address) {
        BloomFactory factoryImplementation = new BloomFactory();
        console2.log("Factory implementation deployed at: ", address(factoryImplementation));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(factoryImplementation),
            address(MULTISIG),
            abi.encodeCall(BloomFactory.initialize, (
                DEPLOYER
            ))
        );
        console2.log("Factory proxy deployed at: ", address(proxy));
        return (address(proxy), address(factoryImplementation));
    }

    // function _deploySwapFacility() internal {
    //     uint256 deployerNonce = vm.getNonce(msg.sender);

    //     swap = new SwapFacility(
    //         UNDERLYING_TOKEN, 
    //         BILL_TOKEN,
    //         USDCUSD,
    //         IB01USD,
    //         IWhitelist(address(WHITELIST_SWAP)),
    //         SPREAD,
    //         LibRLP.computeAddress(msg.sender, deployerNonce + 1),
    //         MIN_STABLE_VALUE,
    //         MAX_BILL_VALUE
    //     );
    //     vm.label(address(swap), "SwapFacility");
    //     console2.log("SwapFacility deployed at:", address(swap));
    // }

    function _deployEmergencyHandler(ExchangeRateRegistry exchangeRateRegistry) internal returns (address) {
        EmergencyHandler handlerImplementation = new EmergencyHandler();
        console2.log("Factory implementation deployed at: ", address(handlerImplementation));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(handlerImplementation),
            address(MULTISIG),
            abi.encodeCall(EmergencyHandler.initialize, (
                exchangeRateRegistry,
                DEPLOYER
            ))
        );
        console2.log("Factory proxy deployed at: ", address(proxy));
        return (address(proxy));
    }

}
