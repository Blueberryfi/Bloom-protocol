// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {RateLimit} from "./RateLimit.sol";
import {ExchangeRateUtil} from "./ExchangeRateUtil.sol";

/**
 * @title ExchangeRateUpdater
 * @notice Updating contract for ERC20 tokens with an exchange rate
 */
contract ExchangeRateUpdater is RateLimit {
    /**
     * @dev Returns the address of the token contract
     * @return The address of the token contract with an exchange rate
     */
    address public tokenContract;

    /**
     * @dev Indicates that the contract has been _initialized
     */
    bool internal _initialized;

    /**
     * @notice Emitted when exchange rate is updated
     * @param caller The address initiating the exchange rate update
     * @param amount The new exchange rate
     */
    event ExchangeRateUpdated(address indexed caller, uint256 amount);

    /**
     * @dev Function to initialize the contract
     * @dev Can an only be called once by the deployer of the contract
     * @dev The caller is responsible for ensuring that both the new owner and the token contract are configured correctly
     * @param newOwner The address of the new owner of the exchange rate updater contract, can either be an EOA or a contract
     * @param newTokenContract The address of the token contract whose exchange rate is updated
     */
    function initialize(
        address newOwner,
        address newTokenContract
    ) external onlyOwner {
        require(
            !_initialized,
            "ExchangeRateUpdater: contract is already initialized"
        );
        require(
            newOwner != address(0),
            "ExchangeRateUpdater: owner is the zero address"
        );
        require(
            newTokenContract != address(0),
            "ExchangeRateUpdater: tokenContract is the zero address"
        );
        transferOwnership(newOwner);
        tokenContract = newTokenContract;
        _initialized = true;
    }

    /**
     * @dev Rate limited function to update token's exchange rate
     * @param _newExchangeRate The new exchange rate. Must be less than or equal
     * to the allowance of the caller.
     */
    function updateExchangeRate(
        uint256 _newExchangeRate
    ) public virtual onlyCallers {
        require(
            _newExchangeRate > 0,
            "ExchangeRateUpdater: new exchange rate must be greater than 0"
        );

        _replenishAllowance(msg.sender);

        uint256 currentExchangeRate = ExchangeRateUtil.safeGetExchangeRate(
            tokenContract
        );

        require(
            _newExchangeRate != currentExchangeRate,
            "ExchangeRateUpdater: exchange rate isn't new"
        );

        uint256 exchangeRateChange;
        if (_newExchangeRate > currentExchangeRate) {
            exchangeRateChange = _newExchangeRate - currentExchangeRate;
        } else {
            exchangeRateChange = currentExchangeRate - _newExchangeRate;
        }

        require(
            exchangeRateChange <= allowances[msg.sender],
            "ExchangeRateUpdater: exchange rate update exceeds allowance"
        );

        allowances[msg.sender] = allowances[msg.sender] - exchangeRateChange;

        ExchangeRateUtil.safeUpdateExchangeRate(
            _newExchangeRate,
            tokenContract
        );
        emit ExchangeRateUpdated(msg.sender, _newExchangeRate);
    }
}
