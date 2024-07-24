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

import {IBloomPool} from "./IBloomPool.sol";

/**
 * @title Bloom Registry interface to return exchangeRate
 */
interface IRegistry {
    /**
     * @notice Returns the current exchange rate of the given token
     * @param token The token address
     * @return The current exchange rate of the given token
     */
    function getExchangeRate(address token) external view returns (uint256);

    /**
     * @notice Register new token to the registry
     * @dev This is a permissioned function. Only the BloomFactory or the registry owner can call this function
     * @param token The TBY token that will be registered (aka the BloomPool)
     */
    function registerToken(IBloomPool token) external;

    /**
     * @notice Set the exchange rate for a token that is in emergency mode
     * @dev Bool pool's stop accruing interest in the event that the pool goes into emergency exit mode
     * @dev This is a permissioned function. Only the BloomPool itself can call.
     * @param rate The exchange rate at the time of emergency exit mode.
     */
    function setEmergencyRate(uint256 rate) external;
}
