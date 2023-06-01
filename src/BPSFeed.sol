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
import {IBPSFeed} from "./interfaces/IBPSFeed.sol";

/// @author Blueberry protocol
contract BPSFeed is IBPSFeed, Owned {
    // =================== Storage ===================

    uint256 internal _totalRate;
    uint256 internal _totalDuration;
    uint256 internal _lastRate;
    uint256 internal _lastTimestamp;

    constructor() Owned(msg.sender) {}

    /// @inheritdoc IBPSFeed
    function getWeightedRate() external view returns (uint256) {
        if (_lastTimestamp == 0) return 0;

        uint256 lastRateDuration = block.timestamp - _lastTimestamp;
        uint256 totalRate = _totalRate + _lastRate * lastRateDuration;
        uint256 totalDuration = _totalDuration + lastRateDuration;
        return totalDuration == 0 ? 0 : totalRate / totalDuration;
    }

    /// @inheritdoc IBPSFeed
    function getCurrentRate() external view returns (uint256) {
        return _lastRate;
    }

    /// @inheritdoc IBPSFeed
    function getLastTimestamp() external view returns (uint256) {
        return _lastTimestamp;
    }

    /// @inheritdoc IBPSFeed
    function updateRate(uint256 _rate) external onlyOwner {
        if (_lastTimestamp > 0) {
            uint256 lastRateDuration = block.timestamp - _lastTimestamp;
            _totalRate += _lastRate * lastRateDuration;
            _totalDuration += lastRateDuration;
        }
        _lastRate = _rate;
        _lastTimestamp = block.timestamp;
    }
}
