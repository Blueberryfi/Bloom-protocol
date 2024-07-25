// SPDX-License-Identifier: BUSL-1.1
/*
██████╗░██╗░░░░░░█████╗░░█████╗░███╗░░░███╗
██╔══██╗██║░░░░░██╔══██╗██╔══██╗████╗░████║
██████╦╝██║░░░░░██║░░██║██║░░██║██╔████╔██║
██╔══██╗██║░░░░░██║░░██║██║░░██║██║╚██╔╝██║
██████╦╝███████╗╚█████╔╝╚█████╔╝██║░╚═╝░██║
╚═════╝░╚══════╝░╚════╝░░╚════╝░╚═╝░░░░░╚═╝
*/

pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";

import {BloomPool, State, AssetCommitment} from "src/BloomPool.sol";
import {ExchangeRateRegistry} from "src/helpers/ExchangeRateRegistry.sol";

import {MockERC20} from "./mock/MockERC20.sol";
import {MockWhitelist} from "./mock/MockWhitelist.sol";
import {MockSwapFacility} from "./mock/MockSwapFacility.sol";
import {MockBPSFeed} from "./mock/MockBPSFeed.sol";
import {MockOracle} from "./mock/MockOracle.sol";

import {IBloomPool} from "src/interfaces/IBloomPool.sol";
import {IWhitelist} from "src/interfaces/IWhitelist.sol";
import {IBPSFeed} from "src/interfaces/IBPSFeed.sol";

contract ExchangeRateRegistryTest is Test {
    BloomPool internal pool;
    MockERC20 internal stableToken;
    MockERC20 internal billyToken;
    MockWhitelist internal whitelist;
    MockSwapFacility internal swap;
    MockOracle internal oracle1;
    MockOracle internal oracle2;

    address internal registryOwner = makeAddr("owner");
    address internal factory = makeAddr("factory");

    MockBPSFeed internal feed;
    ExchangeRateRegistry internal registry;

    uint256 internal constant ORACLE_RATE = 1.5e4;
    uint256 internal constant BPS = 1e4;
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
        stableToken = new MockERC20("USDC", "USDC", 6);
        billyToken = new MockERC20("ib01", "ib01", 18);
        whitelist = new MockWhitelist();
        swap = new MockSwapFacility(stableToken, billyToken, oracle1, oracle2);
        feed = new MockBPSFeed();

        feed.setRate(ORACLE_RATE);

        registry = new ExchangeRateRegistry(registryOwner, factory);

        pool = new BloomPool({
            underlyingToken: address(stableToken),
            billToken: address(billyToken),
            whitelist: IWhitelist(address(whitelist)),
            exchangeRateRegistry: registry,
            swapFacility: address(swap),
            leverageBps: 4 * BPS,
            emergencyHandler: address(0),
            minBorrowDeposit: 100e18,
            commitPhaseDuration: COMMIT_PHASE,
            swapTimeout: 7 days,
            poolPhaseDuration: POOL_DURATION,
            lenderReturnBpsFeed: address(feed),
            name: "Term Bound Token 6 month 2023-06-1",
            symbol: "TBT-1"
        });
    }

    function test_RegistryOwner() public {
        assertEq(registry.owner(), registryOwner);
    }

    function test_GetExchangeRate() public {
        vm.prank(registryOwner);
        skip(COMMIT_PHASE);
        
        registry.registerToken(pool);
        assertEq(registry.getExchangeRate(address(pool)), STARTING_EXCHANGE_RATE);

        uint256 testingIntervals = 5;

        for (uint256 i=1; i <= testingIntervals; i++) {
            uint256 timePerInterval = POOL_DURATION / testingIntervals;
            skip(timePerInterval);
            
            uint256 valueAccrued = (((ORACLE_RATE - 1e4) * SCALER) / testingIntervals) * i;
            uint256 lenderShare = valueAccrued / 1e18;
            uint256 expectedRate = STARTING_EXCHANGE_RATE + valueAccrued - lenderShare;

            assertEq(registry.getExchangeRate(address(pool)), expectedRate);
        }

        // Expect revert if token is not registered
        vm.expectRevert(ExchangeRateRegistry.TokenNotRegistered.selector);
        registry.getExchangeRate(address(stableToken));
    }

    function test_BloomFactoryQueries() public {
        assertEq(registry.getBloomFactory(), factory);

        // New factory address
        address newFactory = makeAddr("factory");

        // Fail when not called by owner
        vm.expectRevert("Ownable: caller is not the owner");
        registry.updateBloomFactory(newFactory);
        
        vm.prank(registryOwner);
        registry.updateBloomFactory(newFactory);
    }

    function test_NonePoolEmergency() public {
        vm.expectRevert(ExchangeRateRegistry.InvalidUser.selector);
        registry.setEmergencyRate(1.1e18);
    }
}