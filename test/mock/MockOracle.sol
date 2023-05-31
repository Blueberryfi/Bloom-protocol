pragma solidity 0.8.19;

contract MockOracle {
    int256 public latestAnswer;

    function setAnswer(int256 _answer) external {
        latestAnswer = _answer;
    }
}
