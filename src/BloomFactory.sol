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

import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {LibRLP} from "solady/utils/LibRLP.sol";

import {BloomPool} from "./BloomPool.sol";
import {SwapFacility} from "./SwapFacility.sol";

import {IBloomFactory} from "./interfaces/IBloomFactory.sol";
import {IWhitelist} from "./interfaces/IWhitelist.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IStUSD} from "./interfaces/IStUSD.sol";

contract BloomFactory is IBloomFactory, Ownable2StepUpgradeable {
    // =================== Storage ===================   
    address private _lastCreatedPool;    
    address private _stUSD;
    mapping(address => bool) private _isPoolFromFactory;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) external initializer {
        __Ownable2Step_init();
        _transferOwnership(owner);
    }

    function getLastCreatedPool() external view override returns (address) {
        return _lastCreatedPool;
    }

    function getStUSD() external view returns (address) {
        return _stUSD;
    }

    function isPoolFromFactory(address pool)
        external
        view
        override
        returns (bool) 
    {
        return _isPoolFromFactory[pool];
    }

    function setStUSD(address stUSD) external onlyOwner {
        _stUSD = stUSD;
        emit NewStUSD(_stUSD);
    }

    function create(
        string memory name,
        string memory symbol,
        address underlyingToken,
        address billToken,
        IRegistry exchangeRateRegistry,
        PoolParams calldata poolParams,
        SwapFacilityParams calldata swapFacilityParams,
        uint256 factoryNonce
    ) external override onlyOwner returns (BloomPool) {
        // Poke StUSD prior to deploying a new BloomPool to ensure that there is no double account
        if (_stUSD != address(0)) {
            IStUSD(_stUSD).poke();
        }

        // Precompute the address of the BloomPool
        address expectedPoolAddress = LibRLP.computeAddress(address(this), factoryNonce + 1);
        
        // Deploys SwapFacility
        SwapFacility swapFacility = new SwapFacility(
            underlyingToken,
            billToken,
            swapFacilityParams.underlyingTokenOracle,
            swapFacilityParams.billyTokenOracle,
            IWhitelist(swapFacilityParams.swapWhitelist),
            swapFacilityParams.spread,
            expectedPoolAddress,
            swapFacilityParams.minStableValue,
            swapFacilityParams.maxBillyValue
        );

        // Deploys BloomPool
        BloomPool bloomPool = new BloomPool(
            underlyingToken,
            billToken,
            IWhitelist(poolParams.borrowerWhiteList),
            address(swapFacility),
            poolParams.lenderReturnBpsFeed,
            poolParams.emergencyHandler,
            poolParams.leverageBps,
            poolParams.minBorrowDeposit,
            poolParams.commitPhaseDuration,
            poolParams.swapTimeout,
            poolParams.poolPhaseDuration,
            name,
            symbol
        );

        // Verify that the deployed BloomPool address matches the expected address
        // If this isn't the case we should revert because the swap facility is associated 
        //     with the wrong address
        if (address(bloomPool) != expectedPoolAddress) {
            revert InvalidPoolAddress();
        }

        // Add the pool to the set of pools & store the last created pool
        _isPoolFromFactory[address(bloomPool)] = true;
        _lastCreatedPool = address(bloomPool);

        // Register the pool in the exchange rate registry & activate the token
        exchangeRateRegistry.registerToken(bloomPool);

        emit NewBloomPoolCreated(address(bloomPool), address(swapFacility));

        return bloomPool;
    }
}