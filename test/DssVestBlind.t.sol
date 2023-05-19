// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "../lib/forge-std/src/Test.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/DssVest.sol";

contract DssVestLocal is Test {
    // init forwarder
    Forwarder forwarder = new Forwarder();
    ERC20 gem = new ERC20("Gem", "GEM");
    DssVestMintable vest;
    address ward = address(1);


    function setUp() public {
        vm.warp(60 * 365 days); // in local testing, the time would start at 1. This causes problems with the vesting contract. So we warp to 60 years.
        vm.startPrank(ward);
        vest = new DssVestMintable(address(forwarder), address(gem));
        vest.file("cap", type(uint256).max);
        vm.stopPrank();
    }

    function testCommitlocal(bytes32 hash) public {
        vm.assume(hash != bytes32(0));
        assertTrue(vest.commitments(hash) == false, "commitment already exists");
        vm.prank(ward);
        vest.commit(hash);
        assertTrue(vest.commitments(hash) == true, "commitment does not exist");
    }

    function testCommitNoWardlocal(address noWard, bytes32 hash) public {
        vm.assume(noWard != address(0));
        vm.assume(vest.wards(noWard) == 0);
        vm.assume(hash != bytes32(0));
        vm.expectRevert("DssVest/not-authorized");
        vm.prank(noWard);
        vest.commit(hash);
    }

    function testCreateFromCommitmentlocal(address _usr, uint128 _tot, uint48 _bgn, uint48 _tau, uint48 _eta, address _mgr, bytes32 _slt, address someone) public {
        vm.assume(checkBounds(_usr, _tot, _bgn, _tau, _eta, DssVest(vest), block.timestamp));
        vm.assume(someone != address(0));
        bytes32 hash = keccak256(abi.encodePacked(_usr, uint256(_tot), uint256(_bgn), uint256(_tau), uint256(_eta), _mgr, _slt));

        // commit
        assertTrue(vest.commitments(hash) == false, "commitment already exists");
        vm.prank(ward);
        vest.commit(hash);
        assertTrue(vest.commitments(hash) == true, "commitment does not exist");

        // createFromCommitment
        vm.prank(someone);
        uint256 id = vest.createFromCommitment(hash, _usr, _tot, _bgn, _tau, _eta, _mgr, _slt);
        assertEq(id, 1, "id is not 0");

        // check vesting details (looks complicated because of solidity local variables limitations)
        address usrOrMgr;
        (usrOrMgr,,,,,,, ) = vest.awards(id);
        assertEq(usrOrMgr, _usr, "usr is not equal");
        (,,,, usrOrMgr,,, ) = vest.awards(id);
        assertEq(usrOrMgr, _mgr, "mgr is not equal");

        uint128 uintVal;
        (, uintVal,,,,,, ) = vest.awards(id);
        assertEq(uintVal, _bgn, "bgn is not equal");
        (,, uintVal,,,,, ) = vest.awards(id);
        assertEq(uintVal, _bgn + _eta, "clf is wrong");
        (,,, uintVal,,,, ) = vest.awards(id);
        assertEq(uintVal, _bgn + _tau, "fin is wrong");
        (,,,,, uintVal,, ) = vest.awards(id);
        assertEq(uintVal, 1, "vest is not restricted");
        (,,,,,, uintVal, ) = vest.awards(id);
        assertEq(uintVal, _tot, "tot is not equal");
        (,,,,,,, uintVal) = vest.awards(id);
        assertEq(uintVal, 0, "rxd is not 0");

        // make sure the commitment is deleted
        assertTrue(vest.commitments(hash) == false, "commitment still exists");

        // make sure a second creation fails
        vm.expectRevert("DssVest/commitment-not-found");
        vm.prank(someone);
        vest.createFromCommitment(hash, _usr, _tot, _bgn, _tau, _eta, _mgr, _slt);
    }

    function checkBounds(address _usr, uint128 _tot, uint48 _bgn, uint48 _tau, uint48 _eta, DssVest _vest, uint256 _timestamp) public view returns (bool) {
        bool valid = true;
        valid = valid && (_usr != address(0));
        valid = valid && (_tot != 0);
        valid = valid && (_bgn > _timestamp - _vest.TWENTY_YEARS() + 1 days && _bgn < _timestamp + _vest.TWENTY_YEARS() - 1 days);
        valid = valid && (_tau < _vest.TWENTY_YEARS());
        valid = valid && (_eta < _tau);

        return valid;
    }

}
