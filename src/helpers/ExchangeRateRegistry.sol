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

import "./RateLimit.sol";
import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title ExchangeRateRegistry
 * @notice Manage tokens and exchange rates
 * @dev This contract stores:
    * 1. Address of all TBYs
    * 2. Exchange rate of each TBY
    * 3. If TBY is active or not
 */
contract ExchangeRateRegistry is RateLimit {
    using EnumerableSet for EnumerableSet.AddressSet;

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
     * @dev Group of active tokens
     */
    EnumerableSet.AddressSet internal _activeTokens;

    /**
     * @dev Group of inactive tokens
     */
    EnumerableSet.AddressSet internal _inactiveTokens;

    /**
     * @dev Indicates that the contract has been _initialized
     */
    bool internal _initialized;

    /**
     * @notice The maximum change value of the exchange rate
     */
    uint256 public maxChange;

    /**
     * @notice Emitted when token is registered
     * @param token The token address to register
     * @param createdAt Timestamp of the token creation
     */
    event TokenRegistered(address token, uint256 createdAt);

    /**
     * @notice Emitted when token is activated
     * @param token The token address
     */
    event TokenActivated(address token);

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
    function initialize(
        address newOwner,
        uint256 newMaxChange
    ) external onlyOwner {
        require(
            !_initialized,
            "ExchangeRateRegistry: contract is already initialized"
        );
        require(
            newOwner != address(0),
            "ExchangeRateRegistry: owner is the zero address"
        );
        require(
            newMaxChange != 0,
            "ExchangeRateRegistry: maxChange is the zero"
        );
        transferOwnership(newOwner);
        maxChange = newMaxChange;
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
        require(
            !info.registered,
            "ExchangeRateRegistry: token already registered"
        );

        info.registered = true;
        info.active = true;
        info.createdAt = createdAt;
        info.exchangeRate = 1e18; // starting exchange rate

        _activeTokens.add(token);

        emit TokenRegistered(token, createdAt);
    }

    /**
     * @notice Activate the token
     * @param token The token address to activate
     */
    function activateToken(address token) external onlyOwner {
        TokenInfo storage info = tokenInfos[token];
        require(info.registered, "ExchangeRateRegistry: token not registered");
        require(!info.active, "ExchangeRateRegistry: token is active");

        info.active = true;

        _activeTokens.add(token);
        _inactiveTokens.remove(token);

        emit TokenActivated(token);
    }

    /**
     * @notice Inactivate the token
     * @param token The token address to inactivate
     */
    function inactivateToken(address token) external onlyOwner {
        TokenInfo storage info = tokenInfos[token];
        require(info.active, "ExchangeRateRegistry: token is inactive");

        info.active = false;

        _activeTokens.remove(token);
        _inactiveTokens.add(token);

        emit TokenInactivated(token);
    }

    /**
     * @notice Return list of active tokens
     */
    function getActiveTokens() public view returns (address[] memory) {
        return _activeTokens.values();
    }

    /**
     * @notice Return list of inactive tokens
     */
    function getInactiveTokens() public view returns (address[] memory) {
        return _inactiveTokens.values();
    }

    /**
     * @notice Update exchange rate for token
     * @param token The token address to update exchange rate for
     * @param addition The addition value to the exchange rate
     * @param subtraction The subtraction value to the exchange rate
     */
    function updateExchangeRate(
        address token,
        uint256 addition,
        uint256 subtraction
    ) external onlyCallers {
        TokenInfo storage info = tokenInfos[token];
        require(info.active, "ExchangeRateRegistry: token is inactive");

        require(addition + subtraction > 0, "ExchangeRateRegistry: both zero");
        require(
            addition == 0 || subtraction == 0,
            "ExchangeRateRegistry: both non-zero"
        );

        uint256 exchangeRateChange;
        if (addition > 0) {
            exchangeRateChange = addition;
            info.exchangeRate += addition;
        } else {
            exchangeRateChange = subtraction;
            info.exchangeRate -= subtraction;
        }

        require(
            exchangeRateChange < maxChange,
            "ExchangeRateRegistry: exchange rate change exceeds limit"
        );

        require(
            exchangeRateChange <= allowances[msg.sender],
            "ExchangeRateRegistry: exchange rate update exceeds allowance"
        );

        allowances[msg.sender] = allowances[msg.sender] - exchangeRateChange;

        emit ExchangeRateUpdated(msg.sender, token, addition, subtraction);
    }

    /**
     * @notice Update exchange rate for all active tokens
     * @param addition The addition value to the exchange rate
     * @param subtraction The subtraction value to the exchange rate
     */
    function updateExchangeRateForAll(
        uint256 addition,
        uint256 subtraction
    ) external onlyCallers {
        address[] memory tokens = getActiveTokens();
        uint256 tokensLength = tokens.length;

        require(addition + subtraction > 0, "ExchangeRateRegistry: both zero");
        require(
            addition == 0 || subtraction == 0,
            "ExchangeRateRegistry: both non-zero"
        );

        uint256 exchangeRateChange;
        if (addition > 0) {
            exchangeRateChange = addition;
        } else {
            exchangeRateChange = subtraction;
        }

        require(
            exchangeRateChange < maxChange,
            "ExchangeRateRegistry: exchange rate change exceeds limit"
        );

        uint256 totalChange = exchangeRateChange;
        require(
            totalChange <= allowances[msg.sender],
            "ExchangeRateRegistry: exchange rate update exceeds allowance"
        );

        allowances[msg.sender] = allowances[msg.sender] - totalChange;

        for (uint256 i; i != tokensLength; ++i) {
            address token = tokens[i];
            TokenInfo storage info = tokenInfos[token];
            if (addition > 0) {
                info.exchangeRate += addition;
            } else {
                info.exchangeRate -= subtraction;
            }

            emit ExchangeRateUpdated(msg.sender, token, addition, subtraction);
        }
    }

    /**
     * @notice Returns the current exchange rate of the given token
     * @param token The token address
     * @return The current exchange rate of the given token
     */
    function getExchangeRate(address token) external view returns (uint256) {
        TokenInfo storage info = tokenInfos[token];
        require(info.registered, "ExchangeRateRegistry: token not registered");

        return info.exchangeRate;
    }
}
