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

import {MerkleWhitelist} from "../src/MerkleWhitelist.sol";
import {BPSFeed} from "../src/BPSFeed.sol";
import {BloomPool} from "../src/BloomPool.sol";
import {SwapFacility} from "../src/SwapFacility.sol";

import {ISwapFacility} from "../src/interfaces/ISwapFacility.sol";
import {IWhitelist} from "../src/interfaces/IWhitelist.sol";

contract Deploy is Test, Script {
    address internal constant TREASURY = 0xE4D701c6E3bFbA3e50D1045A3cef4797b6165119;
    address internal constant EMERGENCY_HANDLER = 0x989B1a8EefaC6bF66a159621D49FaF4A939b452D;

    address internal constant UNDERLYING_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address internal constant BILL_TOKEN = 0xCA30c93B02514f86d5C86a6e375E3A330B435Fb5; //bIB01
    

    // chainlink feeds
    address internal constant USDCUSD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal constant IB01USD = 0x32d1463EB53b73C095625719Afa544D5426354cB;
    
    bytes32 internal constant INITIALROOT = 0xb179801aa7ae4f1e71e664f691b85625d68c7f104c5c64b08010f15a93668c7f;
    address internal constant INITIALOWNER = 0x72d19f7c71a2bD5E61871B1D3dF7a45ae5Ec9582;

    uint256 internal constant SPREAD = 0.004e4; // 0.04%
    uint256 internal constant MIN_STABLE_VALUE = 0.999999e8;
    uint256 internal constant MAX_BILL_VALUE = 107.60e8;
    uint256 internal constant BPS = 1e4;
    uint256 internal constant commitPhaseDuration = 3 days;
    uint256 internal constant poolPhaseDuration = 180 days;
    uint256 internal constant preHoldSwapTimeout = 7 days;
    
    // Aux
    BPSFeed internal lenderReturnBpsFeed;
    MerkleWhitelist internal whitelist;

    // Protocol
    BloomPool internal pool;
    SwapFacility internal swap;
    

    function run() public {
        vm.startBroadcast();

        // Deploy aux items
        _deployMerkleWhitelist();
        _deployBPSFeed();

        // Deploy protocol
        _deploySwapFacility();
        _deployBloomPool();

        vm.stopBroadcast();
    }

    function _deployMerkleWhitelist() internal {
        whitelist = new MerkleWhitelist(
            INITIALROOT,
            INITIALOWNER
        );
        vm.label(address(whitelist), "MerkleWhitelist");
        console2.log("MerkleWhitelist deployed at:", address(whitelist));
        }
    
        function _deployBPSFeed() internal {
        lenderReturnBpsFeed = new BPSFeed();
        vm.label(address(lenderReturnBpsFeed), "BPSFeed");
        console2.log("BPSFeed deployed at:", address(lenderReturnBpsFeed));
    }
    

    function _deploySwapFacility() internal {

        uint256 deployerNonce = vm.getNonce(address(this));

        swap = new SwapFacility(
            UNDERLYING_TOKEN, 
            BILL_TOKEN,
            USDCUSD,
            IB01USD,
            IWhitelist(address(whitelist)),
            SPREAD,
            LibRLP.computeAddress(address(this), deployerNonce +1),
            MIN_STABLE_VALUE,
            MAX_BILL_VALUE
        );
        vm.label(address(swap), "SwapFacility");
        console2.log("SwapFacility deployed at:", address(swap));
    }

    function _deployBloomPool() internal {

        pool = new BloomPool(
            UNDERLYING_TOKEN,
            BILL_TOKEN,
            IWhitelist(address(whitelist)),
            address(swap),
            TREASURY,
            address(lenderReturnBpsFeed),
            EMERGENCY_HANDLER,
            50e4,
            100.0e18,
            commitPhaseDuration,
            preHoldSwapTimeout,
            poolPhaseDuration,
            300,
            3000,
            "Term Bound Token 6 month 2023-12-31",
            "TBT-Dec31"
        );
        console2.log("BloomPool deployed at:", address(pool));
    }
}