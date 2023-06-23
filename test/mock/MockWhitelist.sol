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

import {IMockWhitelist} from "./interfaces/IMockWhitelist.sol";


contract MockWhitelist is IMockWhitelist {
    mapping(address => bool) public includes;

    function add(address member) external {
        includes[member] = true;
    }

    function remove(address member) external {
        includes[member] = false;
    }

    function isWhitelisted(address member, bytes32[] calldata) external view returns (bool) {
        return includes[member];
    }
}
