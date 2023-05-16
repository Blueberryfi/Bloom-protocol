// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Owned} from "solmate/auth/Owned.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";

/// @author philogy <https://github.com/philogy>
contract MerkleWhitelist is IWhitelist, Owned {
    event NewWhitelistRoot(bytes32 newRoot);

    bytes32 public whitelistMerkleRoot;

    constructor(bytes32 initialRoot, address initialOwner) Owned(initialOwner) {
        emit NewWhitelistRoot(whitelistMerkleRoot = initialRoot);
    }

    /// @notice Change whitelist signer
    function setRoot(bytes32 newRoot) external onlyOwner {
        emit NewWhitelistRoot(whitelistMerkleRoot = newRoot);
    }

    function isWhitelisted(address member, bytes calldata data) external view returns (bool) {
        bytes32[] memory proof = abi.decode(data, (bytes32[]));
        bytes32 leaf = keccak256(abi.encodePacked(member));
        return MerkleProofLib.verify(proof, whitelistMerkleRoot, leaf);
    }
}