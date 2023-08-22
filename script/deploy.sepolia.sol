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
import {MockERC20} from "../test/mock/MockERC20.sol";

import {ISwapFacility} from "../src/interfaces/ISwapFacility.sol";
import {IWhitelist} from "../src/interfaces/IWhitelist.sol";

contract Deploy is Test, Script {
    address internal constant DEPLOYER = 0x3031303BB07C35d489cd4B7E6cCd6Fb16eA2b3a1;
    address internal constant TREASURY = 0xE4D701c6E3bFbA3e50D1045A3cef4797b6165119;
    address internal constant EMERGENCY_HANDLER = 0x989B1a8EefaC6bF66a159621D49FaF4A939b452D;

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
    uint256 internal constant MIN_STABLE_VALUE = 0.999999e8;
    uint256 internal constant MAX_BILL_VALUE = 107.6e8;
    uint256 internal constant BPS = 1e4;
    uint256 internal constant commitPhaseDuration = 10 days;
    uint256 internal constant poolPhaseDuration = 2 days;
    uint256 internal constant preHoldSwapTimeout = 1 days;

    // Aux
    BPSFeed internal lenderReturnBpsFeed;
    //MerkleWhitelist internal whitelistBorrow;
    //MerkleWhitelist internal whitelistSwap;

    // Protocol
    BloomPool internal pool;
    SwapFacility internal swap;

    function run() public {
        vm.startBroadcast();

        // Deploy aux items
        //_deployBillyToken();
        // _deployMerkleWhitelistBorrow();
        // _deployMerkleWhitelistSwap();
        //_deployBPSFeed();

        // Deploy protocol
        _deploySwapFacility();
        _deployBloomPool();

        vm.stopBroadcast();
    }

    // function _deployBillyToken() internal {
    //     UNDERLYING_TOKEN = new MockERC20(6);
    //     vm.label(address(UNDERLYING_TOKEN), "UnderlyingToken");
    //     BILL_TOKEN = new MockERC20(18);
    //     vm.label(address(BILL_TOKEN), "BillyToken");
    // }

    //function _deployMerkleWhitelistBorrow() internal {
    //    whitelistBorrow = new MerkleWhitelist(
    //        INITIALROOTBORROW,
    //        INITIALOWNER
    //    );
    //    vm.label(address(whitelistBorrow), "MerkleWhitelistBorrow");
    //    console2.log("MerkleWhitelist deployed at:", address(whitelistBorrow));
    //}

    //function _deployMerkleWhitelistSwap() internal {
    //    whitelistSwap = new MerkleWhitelist(
    //        INITIALROOTSWAP,
    //        INITIALOWNER
    //    );
    //    vm.label(address(whitelistSwap), "MerkleWhitelistSwap");
    //    console2.log("MerkleWhitelist deployed at:", address(whitelistSwap));
    //}

    //     function _deployBPSFeed() internal {
    //     lenderReturnBpsFeed = new BPSFeed();
    //     vm.label(address(lenderReturnBpsFeed), "BPSFeed");
    //     console2.log("BPSFeed deployed at:", address(lenderReturnBpsFeed));
    // }

    function _deploySwapFacility() internal {
        uint256 deployerNonce = vm.getNonce(msg.sender);

        swap = new SwapFacility(
            UNDERLYING_TOKEN,        // address(UNDERLYING_TOKEN), 
            BILL_TOKEN,        // address(BILL_TOKEN),
            USDCUSD,
            IB01USD,
            IWhitelist(address(WHITELIST)),         
            //IWhitelist(address(whitelistSwap)),
            SPREAD,
            LibRLP.computeAddress(msg.sender, deployerNonce +1),
            MIN_STABLE_VALUE,
            MAX_BILL_VALUE
        );
        vm.label(address(swap), "SwapFacility");
        console2.log("SwapFacility deployed at:", address(swap));
    }

    function _deployBloomPool() internal {
        pool = new BloomPool(
            UNDERLYING_TOKEN,    // address(UNDERLYING_TOKEN),
            BILL_TOKEN,          // address(BILL_TOKEN),
            IWhitelist(address(WHITELIST)),           // 
            //IWhitelist(address(whitelistBorrow)),
            address(swap),
            TREASURY,
            BPSFEED,             // address(lenderReturnBpsFeed),
            EMERGENCY_HANDLER,
            50e4,
            1.0e6,
            commitPhaseDuration,
            preHoldSwapTimeout,
            poolPhaseDuration,
            300,
            3000,
            "Term Bound Yield 6 month 2023-2-4",
            "TBY-Feb4"
        );
        console2.log("BloomPool deployed at:", address(pool));
    }
}
