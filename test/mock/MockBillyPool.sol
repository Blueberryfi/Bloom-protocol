// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ISwapFacility} from "src/interfaces/ISwapFacility.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockBillyPool {
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
        swap.swap(underlyingToken, billToken, amountToSwap, "");
    }

    function initiatePostHoldSwap() external {
        uint256 amountToSwap = billToken.balanceOf(address(this));
        billToken.safeApprove(address(swap), amountToSwap);
        swap.swap(billToken, underlyingToken, amountToSwap, "");
    }

    function completeSwap(address outToken, uint256 outAmount) external {}
}
