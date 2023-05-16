// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @author philogy <https://github.com/philogy>
contract MockERC20 is ERC20("Mock Token", "MCK", 18) {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}