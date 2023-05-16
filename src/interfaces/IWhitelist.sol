// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @author philogy <https://github.com/philogy>
interface IWhitelist {
    function isWhitelisted(address member, bytes calldata proof) external returns (bool);
}