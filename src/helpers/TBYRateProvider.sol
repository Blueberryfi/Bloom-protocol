// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/ITBY.sol";
import "../interfaces/IRateProvider.sol";

/**
 * @title Bloom TBY Rate Provider
 * @notice Returns value of TBY in terms of USD.
 * Bloom controls the oracle's address and updates exchangeRate
 * every 24 hours at 4pm UTC. This update cadende may change
 * in the future.
 */
contract TBYRateProvider is IRateProvider {
    ITBY public immutable TBY;

    constructor(ITBY _TBY) {
        TBY = _TBY;
    }


    /**
     * @return value of TBY in terms of USD scaled by 10**18
     */
    function getRate() public view override returns (uint256) {
        return TBY.exchangeRate();
    }
}