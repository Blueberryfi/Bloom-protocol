// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {RateLimit} from "./RateLimit.sol";

/**
 * @title ExchangeRateRegistry
 * @notice Manage tokens and exchange rates
 */
contract ExchangeRateRegistry is RateLimit {
    struct TokenInfo {
        bool registered;
        bool active;
        uint256 createdAt;
        uint256 exchangeRate;
    }

    /**
     * @notice Mapping of token to TokenInfo
     */
    mapping(address => TokenInfo) public tokenInfos;

    /**
     * @dev Indicates that the contract has been _initialized
     */
    bool internal _initialized;

    /**
     * @notice Emitted when token is registered
     * @param token The token address to register
     * @param createdAt Timestamp of the token creation
     */
    event TokenRegistered(address token, uint256 createdAt);

    /**
     * @notice Emitted when token is inactivated
     * @param token The token address
     */
    event TokenInactivated(address token);

    /**
     * @notice Emitted when exchange rate is updated
     * @param caller The address initiating the exchange rate update
     * @param token The token address
     * @param addition The addition to exchange rate
     * @param subtraction The subtraction from exchange rate
     */
    event ExchangeRateUpdated(
        address indexed caller,
        address token,
        uint256 addition,
        uint256 subtraction
    );

    /**
     * @dev Function to initialize the contract
     * @dev Can an only be called once by the deployer of the contract
     * @dev The caller is responsible for ensuring that both the new owner and the token contract are configured correctly
     * @param newOwner The address of the new owner of the exchange rate updater contract, can either be an EOA or a contract
     */
    function initialize(address newOwner) external onlyOwner {
        require(
            !_initialized,
            "ExchangeRateUpdater: contract is already initialized"
        );
        require(
            newOwner != address(0),
            "ExchangeRateUpdater: owner is the zero address"
        );
        transferOwnership(newOwner);
        _initialized = true;
    }

    /**
     * @notice Register new token to the registry
     * @param token The token address to register
     * @param createdAt Timestamp of the token creation
     */
    function registerToken(
        address token,
        uint256 createdAt
    ) external onlyOwner {
        TokenInfo storage info = tokenInfos[token];
        require(!info.registered, "token already registered");

        info.registered = true;
        info.active = true;
        info.createdAt = createdAt;
        info.exchangeRate = 1e18; // starting exchange rate

        emit TokenRegistered(token, createdAt);
    }

    /**
     * @notice Inactivate the token
     * @param token The token address to inactivate
     */
    function inactivateToken(address token) external onlyOwner {
        TokenInfo storage info = tokenInfos[token];
        require(info.active, "token is inactive");

        info.active = false;

        emit TokenInactivated(token);
    }

    function updateExchangeRate(
        address token,
        uint256 addition,
        uint256 subtraction
    ) external onlyCallers {
        TokenInfo storage info = tokenInfos[token];
        require(info.active, "token is inactive");

        require(addition + subtraction > 0, "both zero");
        require(addition == 0 || subtraction == 0, "both non-zero");

        uint256 exchangeRateChange;
        if (addition > 0) {
            exchangeRateChange = addition;
            info.exchangeRate += addition;
        } else {
            exchangeRateChange = subtraction;
            info.exchangeRate -= subtraction;
        }

        require(
            exchangeRateChange <= allowances[msg.sender],
            "ExchangeRateUpdater: exchange rate update exceeds allowance"
        );

        allowances[msg.sender] = allowances[msg.sender] - exchangeRateChange;

        emit ExchangeRateUpdated(msg.sender, token, addition, subtraction);
    }

    /**
     * @notice Returns the current exchange rate of the given token
     * @param token The token address
     * @return The current exchange rate of the given token
     */
    function getExchangeRate(address token) external view returns (uint256) {
        TokenInfo storage info = tokenInfos[token];
        require(info.registered, "token not registered");

        return info.exchangeRate;
    }
}
