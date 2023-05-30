// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/
pragma solidity 0.8.19;

import {BillyPoolInitParams} from "./IBillyPool.sol";

/// @author philogy <https://github.com/philogy>
interface IBillyFactory {
    error ZeroAddress();

    event PoolCreated(address indexed pool);

    function createWithDefaults(
        address billToken,
        uint256 commitPhaseDuration,
        uint256 poolPhaseDuration,
        uint256 lenderRateBps,
        uint256 lenderReturnFee,
        uint256 borrowerReturnFee,
        string memory name,
        string memory symbol
    ) external returns (address pool);

    function rawCreate(BillyPoolInitParams memory poolParams) external returns (address pool);
}