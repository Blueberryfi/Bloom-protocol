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

import {Test} from "forge-std/Test.sol";

import {BPSFeed} from "src/BPSFeed.sol";

contract BPSFeedTest is Test {
    BPSFeed internal feed;

    address internal owner = makeAddr("owner");
    address internal nonOwner = makeAddr("nonOwner");

    uint256 internal rate1 = 200;
    uint256 internal duration1 = 10 days;
    uint256 internal rate2 = 250;
    uint256 internal duration2 = 6 days;

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
        assertEq(
            feed.getWeightedRate(),
            (rate1 * duration1 + rate2 * duration2) / (duration1 + duration2)
        );

        vm.stopPrank();
    }

    function testGetCurrentRate() public {
        assertEq(feed.getCurrentRate(), 0);

        vm.startPrank(owner);

        feed.updateRate(rate1);
        assertEq(feed.getCurrentRate(), rate1);

        skip(duration1);
        assertEq(feed.getCurrentRate(), rate1);

        feed.updateRate(rate2);
        assertEq(feed.getCurrentRate(), rate2);

        skip(duration2);
        assertEq(feed.getCurrentRate(), rate2);

        vm.stopPrank();
    }

    function testGetLastTimestamp() public {
        assertEq(feed.getLastTimestamp(), 0);

        vm.startPrank(owner);

        feed.updateRate(rate1);
        uint256 lastTimestamp = block.timestamp;
        assertEq(feed.getLastTimestamp(), lastTimestamp);

        skip(duration1);
        assertEq(feed.getLastTimestamp(), lastTimestamp);

        feed.updateRate(rate2);
        lastTimestamp = block.timestamp;
        assertEq(feed.getLastTimestamp(), lastTimestamp);

        skip(duration2);
        assertEq(feed.getLastTimestamp(), lastTimestamp);

        vm.stopPrank();
    }
}
