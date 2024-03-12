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

import {TBYRateProvider} from "./TBYRateProvider.sol";

import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

import {IBaseRateProviderFactory} from "../interfaces/IBaseRateProviderFactory.sol";
import {IRegistry} from "../interfaces/IRegistry.sol";

contract TBYRateProviderFactory is IBaseRateProviderFactory, Ownable2Step {
    // Mapping of rate providers created by this factory.
    mapping(address => bool) private _isRateProviderFromFactory;

    event RateProviderCreated(address indexed rateProvider);

    /**
     * @inheritdoc IBaseRateProviderFactory
     */
    function isRateProviderFromFactory(address rateProvider) external view override returns (bool) {
        return _isRateProviderFromFactory[rateProvider];
    }

    /**
     * @notice Creates a new TBYRateProvider contract using the registry.
     * @param registry The address of the registry contract.
     * @param tby The address of the TBY contract.
     * @return TBYRateProvider - The new TBYRateProvider contract.
     */
    function create(IRegistry registry, address tby) external onlyOwner returns (TBYRateProvider) {
        TBYRateProvider rateProvider = new TBYRateProvider(registry, tby);
        _isRateProviderFromFactory[address(rateProvider)] = true;
        emit RateProviderCreated(address(rateProvider));
        return rateProvider;
    }
}