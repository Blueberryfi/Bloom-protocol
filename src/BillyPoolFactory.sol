// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.19;

import {IBillyFactory} from "./interfaces/IBillyFactory.sol";
import {OwnedValueStore} from "./base/OwnedValueStore.sol";

import {BillyPool, BillyPoolInitParams} from "./BillyPool.sol";

/// @author Blueberry protocol (philogy <https://github.com/philogy>)
contract BillyPoolFactory is IBillyFactory, OwnedValueStore {
    mapping(address => bool) public createdPool;

    error NonPositiveRate();

    bytes32 internal constant DEFAULT_UNDERLYING_KEY = "store.defaultUnderyling";
    bytes32 internal constant DEFAULT_WHITELIST_KEY = "store.defaultWhitelist";
    bytes32 internal constant DEFAULT_SWAP_FACILITY_KEY = "store.defaultSwapFacility";
    bytes32 internal constant DEFAULT_TREASURY_KEY = "store.defaultTreasury";
    bytes32 internal constant DEFAULT_LEVERAGE_KEY = "store.defaultLeverage";
    bytes32 internal constant DEFAULT_MIN_BORROW_KEY = "store.defaultMinimumBorrow";
    uint256 internal constant BPS = 1e4;

    constructor(address initialOwner) OwnedValueStore(initialOwner) {}

    function createWithDefaults(
        address billToken,
        uint256 commitPhaseDuration,
        uint256 poolPhaseDuration,
        uint256 lenderReturnBps,
        uint256 lenderReturnFee,
        uint256 borrowerReturnFee,
        string memory name,
        string memory symbol
    ) external returns (address) {
        // Ensure that interest >0%. Use `rawCreate` if negative rate required.
        if (lenderReturnBps <= BPS) revert NonPositiveRate();

        return rawCreate(
            BillyPoolInitParams({
                underlyingToken: getAddr(DEFAULT_UNDERLYING_KEY),
                billToken: billToken,
                whitelist: getAddr(DEFAULT_WHITELIST_KEY),
                swapFacility: getAddr(DEFAULT_SWAP_FACILITY_KEY),
                treasury: getAddr(DEFAULT_TREASURY_KEY),
                leverageBps: getUint(DEFAULT_LEVERAGE_KEY),
                minBorrowDeposit: getUint(DEFAULT_MIN_BORROW_KEY),
                commitPhaseDuration: commitPhaseDuration,
                poolPhaseDuration: poolPhaseDuration,
                lenderReturnBps: lenderReturnBps,
                lenderReturnFee: lenderReturnFee,
                borrowerReturnFee: borrowerReturnFee,
                name: name,
                symbol: symbol
            })
        );
    }

    function rawCreate(BillyPoolInitParams memory poolParams) public onlyOwner returns (address pool) {
        pool = address(new BillyPool(poolParams));
        createdPool[pool] = true;
        emit PoolCreated(pool);
    }
}