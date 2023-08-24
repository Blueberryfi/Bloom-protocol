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

import "../interfaces/IRateProvider.sol";
import "./ExchangeRateRegistry.sol";

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
}

/**
 * @title Bloom TBY Rate Provider
 * @notice Returns value of TBY in terms of USD.
 * Bloom controls the oracle's address and updates exchangeRate
 * every 24 hours at 4pm UTC. This update cadende may change
 * in the future.
 */
contract TBYRateProvider is IRateProvider {
    IRegistry public immutable registry;

    address public immutable tby;

    constructor(IRegistry _registry, address _tby) {
        registry = _registry;
        tby = _tby;
    }

    /**
     * @return value of TBY in terms of USD returns an 18 decimal number
     */
    function getRate() public view override returns (uint256) {
        return registry.getExchangeRate(tby);
    }

}
