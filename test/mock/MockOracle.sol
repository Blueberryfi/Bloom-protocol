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

import {IOracle} from "src/interfaces/IOracle.sol";

contract MockOracle is IOracle {
    int256 public latestAnswer;
    uint8 public decimals;

    constructor(uint8 _decimals) {
       decimals = _decimals;
    }

    function setAnswer(int256 _answer) external {
        latestAnswer = _answer;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, latestAnswer, 0, block.timestamp, 0);
    }
}
