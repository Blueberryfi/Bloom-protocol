// SPDX-License-Identifier: BUSL-1.1
/*
██████╗░██╗░░░░░░█████╗░░█████╗░███╗░░░███╗
██╔══██╗██║░░░░░██╔══██╗██╔══██╗████╗░████║
██████╦╝██║░░░░░██║░░██║██║░░██║██╔████╔██║
██╔══██╗██║░░░░░██║░░██║██║░░██║██║╚██╔╝██║
██████╦╝███████╗╚█████╔╝╚█████╔╝██║░╚═╝░██║
╚═════╝░╚══════╝░╚════╝░░╚════╝░╚═╝░░░░░╚═╝
*/

pragma solidity ^0.8.0;

import {IBloomPool} from "./IBloomPool.sol";
import {IOracle} from "./IOracle.sol";

interface IEmergencyHandler {

    error BorrowerAlreadyClaimed();
    error CallerNotBloomPool();
    error NoTokensToRedeem();
    error OracleAnswerNegative();
    error PoolNotRegistered();
    error InvalidOwner();

    struct RedemptionInfo {
        address token;
        uint256 rate;
        uint256 rateDecimals;
    }

    /**
     * @notice Redeem underlying assets from a Bloom Pool that are in emergency mode
     * @param _pool BloomPool that the funds in the emergency handler contract orginated from
     * @return amount of underlying assets redeemed
     */
    function redeem(IBloomPool _pool) external returns (uint256);

    /**
     * @notice Redeem Bill Tokens 
     * @param _pool BloomPool that the funds in the emergency handler contract orginated from
     * @param _id Id of the borrowers commit in the corresponding BloomPool
     * @return amount of Bill Tokens redeemed
     */
    function redeem(IBloomPool _pool, uint256 _id) external returns (uint256);
    
    /**
     * @notice Registers a Bloom Pool in the Emergency Handler
     * @param _asset Address of the asset being set to the EmergencyHandler
     */
    function registerPool(IOracle _tokenOracle, address _asset) external;
}