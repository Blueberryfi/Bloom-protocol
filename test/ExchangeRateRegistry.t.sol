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

import {BloomPool, State, AssetCommitment} from "src/BloomPool.sol";
import {ExchangeRateRegistry} from "src/helpers/ExchangeRateRegistry.sol";
import {IBloomPool} from "src/interfaces/IBloomPool.sol";
import {IWhitelist} from "src/interfaces/IWhitelist.sol";
import {IBPSFeed} from "src/interfaces/IBPSFeed.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {MockWhitelist} from "./mock/MockWhitelist.sol";
import {MockSwapFacility} from "./mock/MockSwapFacility.sol";
import {MockBPSFeed} from "./mock/MockBPSFeed.sol";

contract ExchangeRateRegistryTest is Test {
    BloomPool internal pool;
    MockERC20 internal stableToken;
    MockERC20 internal billyToken;
    MockWhitelist internal whitelist;
    MockSwapFacility internal swap;

    address internal treasury = makeAddr("treasury");
    address internal registryOwner = makeAddr("owner");

    MockBPSFeed internal feed;
    ExchangeRateRegistry internal registry;

    uint256 internal constant ORACLE_RATE = 10200;
    uint256 internal constant BPS = 1e4;
    uint256 internal constant LENDER_RETURN_FEE = 1000;
    uint256 internal constant SCALER = 1e14;
    uint256 internal constant COMMIT_PHASE = 3 days;
    uint256 internal constant POOL_DURATION = 360 days;

    uint256 internal constant STARTING_EXCHANGE_RATE = 1e18;

    struct TokenInfo {
        bool registered;
        bool active;
        address pool;
        uint256 createdAt;
        uint256 exchangeRate;
    }

    function setUp() public {
        stableToken = new MockERC20(6);
        billyToken = new MockERC20(18);
        whitelist = new MockWhitelist();
        swap = new MockSwapFacility(stableToken, billyToken);
        feed = new MockBPSFeed();

        feed.setRate(ORACLE_RATE);

        pool = new BloomPool({
            underlyingToken: address(stableToken),
            billToken: address(billyToken),
            whitelist: IWhitelist(address(whitelist)),
            swapFacility: address(swap),
            treasury: treasury,
            leverageBps: 4 * BPS,
            emergencyHandler: address(0),
            minBorrowDeposit: 100e18,
            commitPhaseDuration: COMMIT_PHASE,
            preHoldSwapTimeout: 7 days,
            poolPhaseDuration: POOL_DURATION,
            lenderReturnBpsFeed: address(feed),
            lenderReturnFee: LENDER_RETURN_FEE,
            borrowerReturnFee: 3000,
            name: "Term Bound Token 6 month 2023-06-1",
            symbol: "TBT-1"
        });

        registry = new ExchangeRateRegistry();
    }

    function test_InitializeRegistry() public {
        assertEq(registry.isRegistryInitialized(), false);
        registry.initialize(registryOwner);
        assertEq(registry.isRegistryInitialized(), true);
    }

    function test_ExpectRevertWhenDoubleInitializing() public {
        registry.initialize(registryOwner);
        assertEq(registry.isRegistryInitialized(), true);
        vm.prank(registryOwner);
        vm.expectRevert("ExchangeRateRegistry: contract is already initialized");
        registry.initialize(registryOwner);
    }

    function test_ExpectRevertWhenRandoInitializes() public {
        registry.initialize(registryOwner);
        assertEq(registry.isRegistryInitialized(), true);
        
        address rando = makeAddr("rando");        
        
        vm.expectRevert("Ownable: caller is not the owner");
        registry.initialize(registryOwner);
    }

    function test_ExpectRevertWhenOwnerIsZero() public {
        assertEq(registry.isRegistryInitialized(), false);

        vm.expectRevert("ExchangeRateRegistry: owner is the zero address");
        registry.initialize(address(0));
    }

    function test_GetExchangeRate() public {
        registry.initialize(registryOwner);

        vm.prank(registryOwner);
        skip(COMMIT_PHASE);
        
        registry.registerToken(address(billyToken), address(pool));
        assertEq(registry.getExchangeRate(address(billyToken)), STARTING_EXCHANGE_RATE);

        uint256 testingIntervals = 5;

        for (uint256 i=1; i <= testingIntervals; i++) {
            uint256 timePerInterval = POOL_DURATION / testingIntervals;
            skip(timePerInterval);
            
            uint256 valueAccrued = (((ORACLE_RATE - 1e4) * SCALER) / testingIntervals) * i;
            uint256 lenderShare = valueAccrued * (LENDER_RETURN_FEE * SCALER) / 1e18;
            uint256 expectedRate = STARTING_EXCHANGE_RATE + valueAccrued - lenderShare;

            assertEq(registry.getExchangeRate(address(billyToken)), expectedRate);
        }
    }
}