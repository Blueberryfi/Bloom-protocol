// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/IRateProvider.sol";
import {ExchangeRateUtil} from "./ExchangeRateUtil.sol";

/**
 * @title Bloom TBY interface to return exchangeRate
 */
interface ITBY {
    /**
     * @notice get exchange rate
     * @return Returns the current exchange rate scaled by by 10**18
     */
    function exchangeRate() external view returns (uint256);
}

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
     * @return address of TBY
     */
    function getTBYAddress() public view returns (address) {
        return address(TBY);
    }

    /**
     * @return value of TBY in terms of USD scaled by 10**18
     */
    function getRate() public view override returns (uint256) {
        return TBY.exchangeRate();
    }

    /**
     * @return value of TBY in terms of USD scaled by 10**18
     */
    function getExchangeRate() public view override returns (uint256) {
        return ExchangeRateUtil.safeGetExchangeRate(address(TBY));
    }
}
