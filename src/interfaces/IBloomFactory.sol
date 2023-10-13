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

import {BloomPool} from "../BloomPool.sol";

import {IWhitelist} from "./IWhitelist.sol";

interface IBloomFactory {
    error InvalidPoolAddress();

    struct GeneralParams {
        address underlyingToken;
        address billToken;
        IWhitelist whitelist;
    }

    struct PoolParams {
        address treasury;
        address borrowerWhiteList;
        address lenderReturnBpsFeed;
        address emergencyHandler;
        uint256 leverageBps;
        uint256 minBorrowDeposit;
        uint256 commitPhaseDuration;
        uint256 preHoldSwapTimeout;
        uint256 poolPhaseDuration;
        uint256 lenderReturnFee;
        uint256 borrowerReturnFee;
    }

    struct SwapFacilityParams {
        address underlyingTokenOracle;
        address billyTokenOracle;
        address swapWhitelist;
        uint256 spread;
        address pool;
        uint256 minStableValue;
        uint256 maxBillyValue;
    }

    event NewBloomPoolCreated(address indexed pool, address swapFacility);

    /**
     * @notice Returns the last created pool that was created from the factory
     */
    function getLastCreatedPool() external view returns (address);

    /**
     * @notice Returns all pools that were created from the factory
     * @return Array of pool addresses
     */
    function getAllPoolsFromFactory() external view returns (address[] memory);

    /**
     * @notice Returns true if the pool was created from the factory
     * @param pool Address of a BloomPool
     * @return True if the pool was created from the factory
     */
    function isPoolFromFactory(address pool) external view returns (bool);

    /**
     * @notice Create and initializes a new BloomPool and SwapFacility
     * @param name Name of the pool
     * @param symbol Symbol of the pool
     * @param generalParams Parameters that are used for both the pool and the swap facility
     * @param poolParams Parameters that are used for the pool
     * @param swapFacilityParams Parameters that are used for the swap facility
     * @return Address of the new pool
     */
    function create(
        string memory name,
        string memory symbol,
        GeneralParams calldata generalParams,
        PoolParams calldata poolParams,
        SwapFacilityParams calldata swapFacilityParams,
        uint256 deployerNonce
    ) external returns (BloomPool);

}