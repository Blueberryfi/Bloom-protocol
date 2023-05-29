// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.19;

import {Owned} from "solmate/auth/Owned.sol";
import {QuickTypeLib} from "../lib/QuickTypeLib.sol";

/// @author philogy <https://github.com/philogy>
contract OwnedValueStore is Owned {
    using QuickTypeLib for *;

    mapping(bytes32 => uint256) private mainStore;

    event ValueSet(bytes32 indexed key, uint256 rawValue);

    constructor(address initialOwner) Owned(initialOwner) {}

    function storeAddr(bytes32 key, address value) external {
        storeUint(key, value.toUint());
    }

    function storeUint(bytes32 key, uint256 value) public onlyOwner {
        mainStore[key] = value;
        emit ValueSet(key, value);
    }

    function getUint(bytes32 key) public view returns (uint256) {
        return mainStore[key];
    }

    function getAddr(bytes32 key) public view returns (address) {
        return mainStore[key].toAddr();
    }
}