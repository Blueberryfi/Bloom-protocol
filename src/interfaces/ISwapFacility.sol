// SPDX-License-Identifier: BUSL-1.1
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.19;

import {IWhitelist} from "../interfaces/IWhitelist.sol";

/// @author Blueberry protocol
interface ISwapFacility {
    // =================== Functions ===================

    /// @notice Get Underlying token
    function underlyingToken() external view returns (address);

    /// @notice Get Billy token
    function billyToken() external view returns (address);

    /// @notice Get Price oracle for underlying token
    function underlyingTokenOracle() external view returns (address);

    /// @notice Get Price oracle for billy token
    function billyTokenOracle() external view returns (address);

    /// @notice Get Whitelist contract
    function whitelist() external view returns (IWhitelist);

    /// @notice Get Spread price
    function spread() external view returns (uint256);

    /// @notice Get Pool address
    function pool() external view returns (address);

    /// @notice Set Pool Address
    function setPool(address _pool) external;

    /// @notice Set Spread Price
    function setSpread(uint256 _spread) external;

    /// @notice swap tokens Underlying <-> Billy
    function swap(address inToken, address outToken, uint256 inAmount, bytes32[] calldata proof) external;
}
