// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Address } from "oz/utils/Address.sol";

/**
 * @title ExchangeRateUtil
 * @dev Used for safe exchange rate updating
 */
library ExchangeRateUtil {
    using Address for address;

    bytes4 private constant _EXCHANGE_RATE_GETTER_SELECTOR = bytes4(
        keccak256("exchangeRate()")
    );
    bytes4 private constant _EXCHANGE_RATE_UPDATER_SELECTOR = bytes4(
        keccak256("updateExchangeRate(uint256)")
    );

    /**
     * @dev Updates the given token contract's exchange rate
     * @param newExchangeRate New exchange rate
     * @param tokenContract Token contract address
     */
    function safeUpdateExchangeRate(
        uint256 newExchangeRate,
        address tokenContract
    ) internal {
        bytes memory data = abi.encodeWithSelector(
            _EXCHANGE_RATE_UPDATER_SELECTOR,
            newExchangeRate
        );
        tokenContract.functionCall(
            data,
            "ExchangeRateUtil: update exchange rate failed"
        );
    }

    /**
     * @dev Gets the given token contract's exchange rate
     * @param tokenContract Token contract address
     * @return The exchange rate read from the given token contract
     */
    function safeGetExchangeRate(address tokenContract)
        internal
        view
        returns (uint256)
    {
        bytes memory data = abi.encodePacked(_EXCHANGE_RATE_GETTER_SELECTOR);
        bytes memory returnData = tokenContract.functionStaticCall(
            data,
            "ExchangeRateUtil: get exchange rate failed"
        );
        return abi.decode(returnData, (uint256));
    }
}