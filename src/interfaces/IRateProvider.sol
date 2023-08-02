// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

// TODO: pull this from the monorepo
interface IRateProvider {
    function getRate() external view returns (uint256);

    function getExchangeRate() external view returns (uint256);
}
