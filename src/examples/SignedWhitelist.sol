// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Owned} from "solmate/auth/Owned.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {IWhitelist} from "../interfaces/IWhitelist.sol";

import {ECDSA} from "solady/utils/ECDSA.sol";

/// @author philogy <https://github.com/philogy>
contract SignedWhitelist is IWhitelist, Owned, EIP712 {
    event SignerSet(address indexed newSigner);

    error CannotReinstateSigner();
    error ZeroAddress();

    /// @dev No nonce required, invalidation done by changing signer.
    bytes32 internal constant WHITELIST_TYPE_HASH = keccak256("Whitelist(address member)");

    mapping(address => bool) public signerAlreadyInstated;
    address public signer;

    constructor(address initialSigner, address initialOwner) Owned(initialOwner) {
        _setSigner(initialSigner);
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    function name() public pure returns (string memory) {
        return "Signed Whitelist";
    }

    function version() public pure returns (string memory) {
        return "1";
    }

    /// @notice Change whitelist signer
    function setSigner(address newSigner) external onlyOwner {
        _setSigner(newSigner);
    }

    function isWhitelisted(address member, bytes calldata sig) external view returns (bool) {
        return signer == ECDSA.recoverCalldata(_hashTypedData(keccak256(abi.encode(WHITELIST_TYPE_HASH, member))), sig);
    }

    function _setSigner(address newSigner) internal {
        if (newSigner == address(0)) revert ZeroAddress();
        // Necessary to avoid accidentally re-validating a old whitelist.
        if (signerAlreadyInstated[newSigner]) revert CannotReinstateSigner();
        signerAlreadyInstated[newSigner] = true;
        emit SignerSet(signer = newSigner);
    }

    function _domainNameAndVersion() internal pure override returns (string memory, string memory) {
        return (name(), version());
    }
}