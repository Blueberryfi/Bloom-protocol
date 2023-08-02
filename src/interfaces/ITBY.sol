// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/**
 * @title Bloom TBY interface to return exchangeRate
 */
interface TBY {
    /**
     * @notice get exchange rate
     * @return Returns the current exchange rate scaled by by 10**18
     */
    function exchangeRate() external view returns (uint256);
}