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

import {Script, console2} from "forge-std/Script.sol";
import {ExchangeRateRegistry} from "src/helpers/ExchangeRateRegistry.sol";
import {TBYRateProviderFactory} from "src/helpers/TBYRateProviderFactory.sol";
import {MerkleWhitelist} from "../src/MerkleWhitelist.sol";
import {BPSFeed} from "../src/BPSFeed.sol";
import {BloomPool} from "../src/BloomPool.sol";
import {SwapFacility} from "../src/SwapFacility.sol";
import {ExchangeRateRegistry} from "../src/helpers/ExchangeRateRegistry.sol";
import {TBYRateProviderFactory} from "../src/helpers/TBYRateProviderFactory.sol";
import {BloomFactory, IBloomFactory} from "../src/BloomFactory.sol";
import {EmergencyHandler} from "../src/EmergencyHandler.sol";

import {MockERC20} from "../test/mock/MockERC20.sol";

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title DeployCore
 * @notice Deploys the core contracts for the Bloom Protocol that are required for the rest of the system to function.
 */
contract DeployCore is Script {
    address internal deployer;
    bytes32 internal constant INITIAL_ROOT = 0x00;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        deployer = vm.addr(deployerPrivateKey);
        
        MockERC20 mockUsdc = new MockERC20("Bloom-USDC", "bUSDC", 6);
        MockERC20 mockIb01 = new MockERC20("Bloom-Ib01", "bIb01", 18);
        console2.log('Mock USDC deployed at: ', address(mockUsdc));
        console2.log('Mock Ib01 deployed at: ', address(mockIb01));

        (address bloomPoolFactory, ) = _deployBloomFactory();
        console2.log("BloomFactory deployed at: ", bloomPoolFactory);
        BPSFeed bpsFeed = new BPSFeed();
        console2.log("BPSFeed deployed at: ", address(bpsFeed));
        ExchangeRateRegistry exchangeRateRegistry = new ExchangeRateRegistry(deployer, bloomPoolFactory);
        console2.log("ExchangeRateRegistry deployed at: ", address(exchangeRateRegistry));

        // Deploy merkle whitelist
        MerkleWhitelist whitelistBorrow = new MerkleWhitelist(
            INITIAL_ROOT,
            deployer
        );  
        console2.log("MerkleWhitelist for Borrows deployed at: ", address(whitelistBorrow));
        MerkleWhitelist whitelistSwap = new MerkleWhitelist(
            INITIAL_ROOT,
            deployer
        );
        console2.log("MerkleWhitelist for Swaps deployed at: ", address(whitelistSwap));
    }

    function _deployBloomFactory() internal returns (address, address) {
        BloomFactory factoryImplementation = new BloomFactory();

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(factoryImplementation),
            deployer,
            abi.encodeWithSignature("initialize(address)", deployer)
        );

        return (address(proxy), address(factoryImplementation));
    }
}