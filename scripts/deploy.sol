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
import {Script} from "forge-std/Script.sol";
import {LibRLP} from "solady/utils/LibRLP.sol";

import {MerkleWhitelist} from "../src/MerkleWhitelist.sol";
import {BPSFeed} from "../src/BPSFeed.sol";
import {BloomPool} from "../src/BloomPool.sol";
import {SwapFacility} from "../src/SwapFacility.sol";

contract Deploy is Test, Script {
    address constant treasury = 0xE4D701c6E3bFbA3e50D1045A3cef4797b6165119;
    address constant emergencyHandler = 0x989B1a8EefaC6bF66a159621D49FaF4A939b452D;

    address constant underlyingToken = 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48; // USDC
    address constant billToken = 0xCA30c93B02514f86d5C86a6e375E3A330B435Fb5; //bIB01
    

    // chainlink feeds
    address constant USDCUSD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant IB01USD = 0x32d1463EB53b73C095625719Afa544D5426354cB;
    
    
    // Aux
    MerkleWhitelist whitelist;
    BPSFeed lenderReturnBpsFeed;

    // Protocol
    BloomPool bloomPool;
    SwapFacility swapFacility;
    

    function run() public {
        vm.startBroadcast();

        // Deploy aux items
        deployMerkleWhitelist();
        deployBPSFeed();
        printAux();

        // Deploy protocol
        deployBloomPool();
        deploySwapFacility();
        printProtocol();

        vm.stopBroadcast();
    }

    function deployMerkleWhitelist() internal {

    }

    function printAux() internal view {
        console.log("MerkleWhitelist", address(merkleWhitelist));
        console.log("BPSFeed", address(BPSFeed));
    }

    function printProtocol() internal view {
        console.log("BloomPool", address(BloomPool));
        console.log("SwapFacility", address(SwapFacility));
    }
}