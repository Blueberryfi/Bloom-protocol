// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IWhitelist} from "src/interfaces/IWhitelist.sol";

/// @author philogy <https://github.com/philogy>
contract MockWhitelist is IWhitelist {
    mapping(address => bool) public includes;

    function add(address member) external {
        includes[member] = true;
    }

    function remove(address member) external {
        includes[member] = false;
    }

    function isWhitelisted(address member, bytes calldata) external view returns (bool) {
        return includes[member];
    }
}