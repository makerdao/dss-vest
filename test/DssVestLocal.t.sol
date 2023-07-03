// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "../lib/forge-std/src/Test.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol";
import "@tokenize.it/contracts/contracts/Token.sol";
import "@tokenize.it/contracts/contracts/AllowList.sol";
import "@tokenize.it/contracts/contracts/FeeSettings.sol";
import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import {DssVestMintable} from "../src/DssVest.sol";
import "../src/DssVestMintableNaiveFactory.sol";

contract DssVestLocal is Test {
    // init forwarder
    Forwarder forwarder = new Forwarder();

    function setUp() public {
        vm.warp(60 * 365 days); // in local testing, the time would start at 1. This causes problems with the vesting contract. So we warp to 60 years.
    }

    function testFileWrongKeyLocal(address gem, uint256 value, string memory key) public {
        vm.assume(keccak256(abi.encodePacked(key)) != keccak256(abi.encodePacked("cap")));
        vm.assume(gem != address(0));
        DssVestMintable vest = new DssVestMintable(address(forwarder), gem, 0);
        vm.expectRevert("DssVest/file-unrecognized-param");
        vest.file("wrongKey", value);
    }

    function testRelyDenyLocal(address gem, address ward) public {
        vm.assume(gem != address(0));
        vm.assume(ward != address(0));
        vm.assume(ward != address(this));
        DssVestMintable vest = new DssVestMintable(address(forwarder), gem, 0);
        assertEq(vest.wards(ward), 0, "address is already a ward");
        vest.rely(ward);
        assertEq(vest.wards(ward), 1, "rely failed");
        vest.deny(ward);
        assertEq(vest.wards(ward), 0, "deny failed");
    }
}
