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

import {IRateProvider} from "./interfaces/IRateProvider.sol";
import {BPSFeed} from "./BPSFeed.sol";

contract TBYRateProvider is IRateProvider {
    // IB01/USD Oracle returns an 8-decimal fixed point number
    uint256 internal constant TBY_SCALING_FACTOR = 1e10;
    BPSFeed public priceFeed;

    constructor(BPSFeed _priceFeed) {
        priceFeed = _priceFeed;
    } 

    /// @inheritdoc IRateProvider
    function getRate() external view returns (uint256) {
        return priceFeed.getWeightedRate() * TBY_SCALING_FACTOR;
    }

}