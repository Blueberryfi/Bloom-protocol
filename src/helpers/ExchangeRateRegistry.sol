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

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/IBPSFeed.sol";
import "../interfaces/IBloomPool.sol";

/**
 * @title ExchangeRateRegistry
 * @notice Manage tokens and exchange rates
 * @dev This contract stores:
 * 1. Address of all TBYs
 * 2. Exchange rate of each TBY
 * 3. If TBY is active or not
 */
contract ExchangeRateRegistry is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant BASE_RATE = 1e18;
    uint256 public constant SCALER = 1e14;

    struct TokenInfo {
        bool registered;
        bool active;
        address pool;
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
     * @notice Emitted when token is registered
     * @param token The token address to register
     * @param pool The pool associated with the token
     * @param createdAt Timestamp of the token creation
     */
    event TokenRegistered(
        address indexed token,
        address pool,
        uint256 createdAt
    );

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
     * @param exchangeRate The new exchange rate
     */
    event ExchangeRateUpdated(
        address indexed caller,
        address token,
        uint256 exchangeRate
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
            "ExchangeRateRegistry: contract is already initialized"
        );
        require(
            newOwner != address(0),
            "ExchangeRateRegistry: owner is the zero address"
        );
        transferOwnership(newOwner);
        _initialized = true;
    }

    /**
     * @notice Register new token to the registry
     * @param token The token address to register
     * @param pool The pool associated with the token
     */
    function registerToken(
        address token,
        address pool
    ) external onlyOwner {
        IBloomPool poolContract = IBloomPool(pool);
        uint256 createdAt = poolContract.COMMIT_PHASE_END();

        TokenInfo storage info = tokenInfos[token];
        require(
            !info.registered,
            "ExchangeRateRegistry: token already registered"
        );

        info.registered = true;
        info.active = true;
        info.pool = pool;
        info.createdAt = createdAt;

        _activeTokens.add(token);

        emit TokenRegistered(token, pool, createdAt);
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
    function getActiveTokens() external view returns (address[] memory) {
        return _activeTokens.values();
    }

    /**
     * @notice Return list of inactive tokens
     */
    function getInactiveTokens() external view returns (address[] memory) {
        return _inactiveTokens.values();
    }

    /**
     * @notice Return true if the registry has been initialized
     */
    function isRegistryInitialized() external view returns (bool) {
        return _initialized;
    }

    /**
     * @notice Update the exchange rate for the given token
     * @param token The token address
     */
    function updateExchangeRate(address token) external onlyOwner {
        _updateExchangeRate(token);
    }

    /**
     * @notice Update the exchange rate for all active tokens
     */
    function updateExchangeRateForAll() external onlyOwner {
        address[] memory activeTokens = _activeTokens.values();

        uint256 length = activeTokens.length;
        for (uint256 i; i != length; ++i) {
            _updateExchangeRate(activeTokens[i]);
        }
    }

    function _updateExchangeRate(address token) internal {
        TokenInfo storage info = tokenInfos[token];

        uint256 exchangeRate = _getExchangeRate(token);

        info.exchangeRate = exchangeRate;

        emit ExchangeRateUpdated(msg.sender, token, exchangeRate);
    }

    /**
     * @notice Returns the most recent updated exchange rate of the given token
     * @param token The token address
     * @return The most recent updated exchange rate of the given token
     */
    function getRecentRate(address token) external view returns (uint256) {
        TokenInfo storage info = tokenInfos[token];
        require(info.registered, "ExchangeRateRegistry: token not registered");

        return info.exchangeRate;
    }

    /**
     * @notice Returns the current exchange rate of the given token
     * @param token The token address
     * @return The current exchange rate of the given token
     */
    function getExchangeRate(address token) external view returns (uint256) {
        return _getExchangeRate(token);
    }

    function _getExchangeRate(address token) internal view returns (uint256) {
        TokenInfo storage info = tokenInfos[token];
        require(info.registered, "ExchangeRateRegistry: token not registered");

        IBloomPool pool = IBloomPool(info.pool);
        uint256 lenderFee = pool.LENDER_RETURN_FEE();
        uint256 duration = pool.POOL_PHASE_DURATION();
        IBPSFeed bpsFeed = IBPSFeed(pool.LENDER_RETURN_BPS_FEED());

        uint256 rate = (bpsFeed.getWeightedRate() * SCALER);
        uint256 timeElapsed = block.timestamp - info.createdAt;
        if (timeElapsed > duration) {
            timeElapsed = duration;
        }
        uint256 adjustedLenderFee = (lenderFee * SCALER);
        
        uint256 delta = ((rate * (BASE_RATE - adjustedLenderFee) / 1e18) * timeElapsed) / 
            duration;

        return BASE_RATE + ((delta * BASE_RATE) / 1e18);
    }
}
