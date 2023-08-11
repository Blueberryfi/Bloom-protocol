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
import "../interfaces/IBaseRateProviderFactory.sol";
import "./TBYRateProvider.sol";
import "./ExchangeRateRegistry.sol";

contract TBYRateProviderFactory is IBaseRateProviderFactory {
    // Mapping of rate providers created by this factory.
    mapping(address => bool) private _isRateProviderFromFactory;

    event RateProviderCreated(address indexed rateProvider);

    function isRateProviderFromFactory(address rateProvider) external view returns (bool) {
        return _isRateProviderFromFactory[rateProvider];
    }

    function _onCreate(address rateProvider) internal {
        _isRateProviderFromFactory[rateProvider] = true;
        emit RateProviderCreated(rateProvider);
    }

    /// @notice Creates a new TBYRateProvider contract using the registry.
    /// @param registry The address of the registry contract.
    /// @param tby The address of the TBY contract.
    function create(IRegistry registry, address tby) external returns (TBYRateProvider) {
        TBYRateProvider rateProvider = new TBYRateProvider(registry, tby);
        _onCreate(address(rateProvider));
        return rateProvider;
    }

}