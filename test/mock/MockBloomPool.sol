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

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ISwapFacility} from "src/interfaces/ISwapFacility.sol";
import {MockERC20} from "./MockERC20.sol";

error InvalidState(MockBloomPool.State current);
error NotEmergencyHandler();

contract MockBloomPool is MockERC20 {
    using SafeTransferLib for address;

    address public immutable underlyingToken;
    address public immutable billToken;
    address public emergencyHandler;

    uint256 public COMMIT_PHASE_END;
    
    mapping(uint256 => AssetCommitment) commitments;

    State public state;

    ISwapFacility public immutable swap;
    
    enum State {
        Normal,
        EmergencyExit
    }

    struct AssetCommitment {
        address owner;
        uint128 committedAmount;
        uint128 cumulativeAmountEnd;
    }

    modifier onlyState(State expectedState) {
        if (state != expectedState) revert InvalidState(state);
        _;
    }

    modifier onlyEmergencyHandler() {
        if (msg.sender != emergencyHandler) revert NotEmergencyHandler();
        _;
    }

    constructor(address _underlyingToken, address _billToken, address _swap) 
        MockERC20(MockERC20(_underlyingToken).decimals())
    {
        underlyingToken = _underlyingToken;
        billToken = _billToken;
        swap = ISwapFacility(_swap);
        state = State.Normal;
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

    function executeEmergencyBurn(
        address account,
        uint256 amount
    ) external onlyState(State.EmergencyExit) onlyEmergencyHandler {
        _burn(account, amount);
    }

    function getBorrowCommitment(uint256 id) external view returns (AssetCommitment memory) {
        return commitments[id];
    }

    function setState(State newState) external {
        state = newState;
    }

    function setEmergencyHandler(address newHandler) external {
        emergencyHandler = newHandler;
    }

    function setBorrowerCommitment(uint256 id, AssetCommitment memory commitment) external {
        commitments[id] = commitment;
    }

    function setCommitPhaseEnd(uint256 newCommitPhaseEnd) external {
        COMMIT_PHASE_END = newCommitPhaseEnd;
    }
}
