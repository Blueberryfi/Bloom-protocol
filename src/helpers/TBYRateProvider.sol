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

import "../interfaces/IRateProvider.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";

/**
 * @title Bloom TBY Rate Provider
 * @notice Returns value of TBY in terms of USD.
 * Bloom controls the oracle's address and updates exchangeRate
 * every 24 hours at 4pm UTC. This update cadence may change
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
    function getRate() external view override returns (uint256) {
        return registry.getExchangeRate(tby);
    }
}
