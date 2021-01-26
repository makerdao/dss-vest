pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./DssVest.sol";

contract DssVestTest is DSTest {
    DssVest vest;

    function setUp() public {
        vest = new DssVest();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
