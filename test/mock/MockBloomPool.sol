// SPDX-License-Identifier: BUSL-1.1
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.19;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ISwapFacility} from "src/interfaces/ISwapFacility.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockBloomPool {
    using SafeTransferLib for address;

    address public immutable underlyingToken;
    address public immutable billToken;

    ISwapFacility public immutable swap;

    constructor(address _underlyingToken, address _billToken, address _swap) {
        underlyingToken = _underlyingToken;
        billToken = _billToken;
        swap = ISwapFacility(_swap);
    }

    function initiatePreHoldSwap() external {
        uint256 amountToSwap = underlyingToken.balanceOf(address(this));
        underlyingToken.safeApprove(address(swap), amountToSwap);
        swap.swap(underlyingToken, billToken, amountToSwap, new bytes32[](0));
    }

    function initiatePostHoldSwap() external {
        uint256 amountToSwap = billToken.balanceOf(address(this));
        billToken.safeApprove(address(swap), amountToSwap);
        swap.swap(billToken, underlyingToken, amountToSwap, new bytes32[](0));
    }

    function completeSwap(address outToken, uint256 outAmount) external {}
}
