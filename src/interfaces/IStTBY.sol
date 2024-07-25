// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IStTBY {
    /**
     * @notice Invokes the auto stake feature or adjusts the remaining balance
     * if the most recent deposit did not get fully staked
     * @dev autoMint feature is invoked if the last created pool is in
     * the commit state
     * @dev remainingBalance adjustment is invoked if the last created pool is
     * in any other state than commit and deposits dont get fully staked
     * @dev anyone can call this function for now
     */
    function poke() external;
}
