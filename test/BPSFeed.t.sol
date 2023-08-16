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

import {Test} from "forge-std/Test.sol";

import {BPSFeed} from "src/BPSFeed.sol";
import {IBPSFeed} from "src/interfaces/IBPSFeed.sol";

contract BPSFeedTest is Test {
    BPSFeed internal feed;

    address internal owner = makeAddr("owner");
    address internal nonOwner = makeAddr("nonOwner");

    uint256 internal rate1 = 10020;
    uint256 internal duration1 = 10 days;
    uint256 internal rate2 = 10025;
    uint256 internal duration2 = 6 days;
    uint256 internal rate3 = 9030;
    uint256 internal rate4 = 11111;

    function setUp() public {
        vm.prank(owner);
        feed = new BPSFeed();

        assertEq(feed.owner(), owner);
    }

    function testUpdateRate_fail_as_nonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        feed.updateRate(rate1);
    }

    function testUpdateRate_success() public {
        vm.prank(owner);
        feed.updateRate(rate1);
    }

    function testUpdateRate_InvalidRateLow() public {
        startHoax(owner);
        vm.expectRevert(IBPSFeed.InvalidRate.selector);
        feed.updateRate(rate3);
    }

    function testUpdateRate_InvalidRateHigh() public {
        startHoax(owner);
        vm.expectRevert(IBPSFeed.InvalidRate.selector);
        feed.updateRate(rate4);
    }

    function testGetWeightedRate() public {
        assertEq(feed.getWeightedRate(), 0);

        vm.startPrank(owner);

        feed.updateRate(rate1);
        assertEq(feed.getWeightedRate(), 0);

        skip(duration1);
        assertEq(feed.getWeightedRate(), rate1);

        feed.updateRate(rate2);
        assertEq(feed.getWeightedRate(), rate1);

        skip(duration2);
        assertEq(feed.getWeightedRate(), (rate1 * duration1 + rate2 * duration2) / (duration1 + duration2));

        vm.stopPrank();
    }

    function testGetCurrentRate() public {
        assertEq(feed.currentRate(), 1e4);

        vm.startPrank(owner);

        feed.updateRate(rate1);
        assertEq(feed.currentRate(), rate1);

        skip(duration1);
        assertEq(feed.currentRate(), rate1);

        feed.updateRate(rate2);
        assertEq(feed.currentRate(), rate2);

        skip(duration2);
        assertEq(feed.currentRate(), rate2);

        vm.stopPrank();
    }

    function testGetLastTimestamp() public {
        assertEq(feed.lastTimestamp(), 0);

        vm.startPrank(owner);

        feed.updateRate(rate1);
        uint256 lastTimestamp = block.timestamp;
        assertEq(feed.lastTimestamp(), lastTimestamp);
        lastTimestamp = feed.lastTimestamp();

        skip(duration1);
        assertEq(feed.lastTimestamp(), lastTimestamp);

        feed.updateRate(rate2);
        lastTimestamp = block.timestamp;
        assertEq(feed.lastTimestamp(), lastTimestamp);
        lastTimestamp = feed.lastTimestamp();

        skip(duration2);
        assertEq(feed.lastTimestamp(), lastTimestamp);

        vm.stopPrank();
    }
}
