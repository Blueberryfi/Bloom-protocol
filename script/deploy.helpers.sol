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
import {ExchangeRateRegistry} from "../src/helpers/ExchangeRateRegistry.sol";
import {TBYRateProviderFactory} from "../src/helpers/TBYRateProviderFactory.sol";

contract Deploy is Test, Script {
    address internal constant DEPLOYER = 0x91797a79fEA044D165B00D236488A0f2D22157BC;


    function run() public {
        vm.startBroadcast();

        _deployExchangeRateRegistry();
        _deployTBYRateProviderFactory();

        vm.stopBroadcast();
    }

    function _deployExchangeRateRegistry() internal {
        ExchangeRateRegistry registry = new ExchangeRateRegistry();
        registry.initialize(DEPLOYER);
        vm.label(address(registry), "ExchangeRateRegistry");
        console2.log("ExchangeRateRegistry deployed at: ", address(registry));
    }

    function _deployTBYRateProviderFactory() internal {
        TBYRateProviderFactory factory = new TBYRateProviderFactory();
        vm.label(address(factory), "TBYRateProviderFactory");
        console2.log("TBYRateProviderFactory deployed at: ", address(factory));
    }
}
