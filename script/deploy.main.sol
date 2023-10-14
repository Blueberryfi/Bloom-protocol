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
    address internal constant TREASURY = 0xFdC004B6B92b45B224d37dc45dBA5cA82c1e08f2;
    address internal constant EMERGENCY_HANDLER = 0x91797a79fEA044D165B00D236488A0f2D22157BC;

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
    uint256 internal constant MAX_BILL_VALUE = 109.6e8;
    uint256 internal constant BPS = 1e4;
    uint256 internal constant commitPhaseDuration = 3 days;
    uint256 internal constant poolPhaseDuration = 180 days;
    uint256 internal constant preHoldSwapTimeout = 7 days;

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
        _deploySwapFacility();
        _deployBloomPool();

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

    function _deployBloomPool() internal {
        pool = new BloomPool(
            UNDERLYING_TOKEN,
            BILL_TOKEN,
            IWhitelist(address(WHITELIST_BORROW)),
            address(swap),
            TREASURY,
            address(LENDER_RETURN_BPS_FEED),
            EMERGENCY_HANDLER,
            50e4,
            10.0e6,
            commitPhaseDuration,
            preHoldSwapTimeout,
            poolPhaseDuration,
            300, // 3%
            0, // 0%
            "Term Bound Yield 6 month feb-2024-Batch2",
            "TBY-feb-2024-Batch2"
        );
        console2.log("BloomPool deployed at:", address(pool));
    }
}
