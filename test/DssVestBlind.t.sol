// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "../lib/forge-std/src/Test.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/DssVest.sol";

/**
   @dev This contract is used to test the DssVest contract. It is a ERC20 token that can be minted by anyone.
 */
contract ERC20MintableByAnyone is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract DssVestLocal is Test {
    event Commit(bytes32 indexed hash);
    event Revoke(bytes32 indexed hash, uint256 end);
    event Claim(bytes32 indexed hash, uint256 indexed id);

    // init forwarder
    Forwarder forwarder = new Forwarder();
    ERC20 gem = new ERC20MintableByAnyone("Gem", "GEM");
    DssVestMintable vest;
    address ward = address(1);
    address usr = address(2);


    function setUp() public {
        vm.warp(60 * 365 days); // in local testing, the time would start at 1. This causes problems with the vesting contract. So we warp to 60 years.
        vm.startPrank(ward);
        vest = new DssVestMintable(address(forwarder), address(gem), type(uint256).max);
        vm.stopPrank();
    }

    function testCommitLocal(bytes32 hash) public {
        vm.assume(hash != bytes32(0));
        assertTrue(vest.commitments(hash) == false, "commitment already exists");
        vm.prank(ward);
        vest.commit(hash);
        assertTrue(vest.commitments(hash) == true, "commitment does not exist");
    }

    function testCommitNoWardLocal(address noWard, bytes32 hash) public {
        vm.assume(noWard != address(0));
        vm.assume(vest.wards(noWard) == 0);
        vm.assume(hash != bytes32(0));
        vm.expectRevert("DssVest/not-authorized");
        vm.prank(noWard);
        vest.commit(hash);
    }

    function testRevokeNowLocal(bytes32 hash) public {
        vm.assume(hash != bytes32(0));
        vm.prank(ward);
        vest.commit(hash);
        assertTrue(vest.commitments(hash) == true, "commitment does not exist");
        vm.prank(ward);
        vest.revoke(hash, 0);
        assertTrue(vest.revocations(hash) == block.timestamp, "revocation not correct");
    }

    function testRevokeLaterLocal(bytes32 hash, uint48 end) public {
        vm.assume(hash != bytes32(0));
        vm.assume(end > block.timestamp);
        vm.prank(ward);
        vest.commit(hash);
        assertTrue(vest.commitments(hash) == true, "commitment does not exist");
        vm.prank(ward);
        vest.revoke(hash, end);
        assertTrue(vest.revocations(hash) == end, "revocation not correct");
    }

    function testRevokeNoWardLocal(address noWard, bytes32 hash) public {
        vm.assume(noWard != address(0));
        vm.assume(vest.wards(noWard) == 0);
        vm.assume(hash != bytes32(0));
        vm.prank(ward);
        vest.commit(hash);
        assertTrue(vest.commitments(hash) == true, "commitment does not exist");
        vm.prank(noWard);
        vm.expectRevert("DssVest/not-authorized");
        vest.revoke(hash, block.timestamp);
        assertEq(vest.revocations(hash), 0, "revocation not correct");
    }

    function testClaimLocal(address _usr, uint128 _tot, uint48 _bgn, uint48 _tau, uint48 _eta, address _mgr, bytes32 _slt, address someone) public {
        vm.assume(checkBounds(_usr, _tot, _bgn, _tau, _eta, DssVest(vest), block.timestamp));
        vm.assume(someone != address(0));
        bytes32 hash = keccak256(abi.encodePacked(_usr, uint256(_tot), uint256(_bgn), uint256(_tau), uint256(_eta), _mgr, _slt));

        // commit
        assertTrue(vest.commitments(hash) == false, "commitment already exists");
        vm.expectEmit(true, true, true, true, address(vest));
        emit Commit(hash);
        vm.prank(ward);
        vest.commit(hash);
        assertTrue(vest.commitments(hash) == true, "commitment does not exist");

        // claim

        vm.expectEmit(true, true, true, true, address(vest));
        emit Claim(hash, 1);
        vm.prank(someone);
        uint256 id = vest.claim(hash, _usr, _tot, _bgn, _tau, _eta, _mgr, _slt);
        assertEq(id, 1, "id is not 0");

        checkVestingPlanDetails(id, _usr, _tot, _bgn, _tau, _eta, _mgr, 0);

        // make sure the commitment is deleted
        assertTrue(vest.commitments(hash) == false, "commitment still exists");

        // make sure a second creation fails
        vm.expectRevert("DssVest/commitment-not-found");
        vm.prank(someone);
        vest.claim(hash, _usr, _tot, _bgn, _tau, _eta, _mgr, _slt);
    }

    function testClaimAfterRevokeLocal() public {
        address _usr = address(1);
        uint128 commitmentTot = 100;
        uint128 realTot = 75;
        uint48 _bgn = 40 * 365 days;
        uint48 _tau = 2 * 365 days;
        uint48 _eta = 1 * 365 days; 
        address _mgr = address(0); 
        bytes32 _slt = 0;

        vm.warp(_bgn - 1 days);
        vm.assume(checkBounds(_usr, commitmentTot, _bgn, _tau, _eta, DssVest(vest), block.timestamp));
        bytes32 hash = keccak256(abi.encodePacked(_usr, uint256(commitmentTot), uint256(_bgn), uint256(_tau), uint256(_eta), _mgr, _slt));

        // commit
        assertTrue(vest.commitments(hash) == false, "commitment already exists");
        vm.expectEmit(true, true, true, true, address(vest));
        emit Commit(hash);
        vm.prank(ward);
        vest.commit(hash);
        assertTrue(vest.commitments(hash) == true, "commitment does not exist");

        // warp to 1.5 years into the vesting period and revoke
        vm.warp(_bgn + _eta + _tau / 4);
        vm.prank(ward);
        vest.revoke(hash, block.timestamp);
        assertTrue(vest.revocations(hash) == block.timestamp, "revocation not correct");
        
        // warp till end of vesting and claim
        vm.warp(_bgn + _eta + _tau + 1);
        vm.expectEmit(true, true, true, true, address(vest));
        emit Claim(hash, 1);
        uint256 id = vest.claim(hash, _usr, commitmentTot, _bgn, _tau, _eta, _mgr, _slt);
        assertEq(id, 1, "id is not 0");

        checkVestingPlanDetails(id, _usr, realTot, _bgn, 1.5 * 365 days, _eta, _mgr, 0);

        // make sure the commitment is deleted
        assertTrue(vest.commitments(hash) == false, "commitment still exists");

        // make sure a second creation fails
        vm.expectRevert("DssVest/commitment-not-found");
        vest.claim(hash, _usr, commitmentTot, _bgn, _tau, _eta, _mgr, _slt);

        // vest everything
        vm.prank(_usr);
        vest.vest(id);
        assertEq(realTot, gem.balanceOf(_usr), "balance is not equal to total");
    }

    function testRevokeBeforeCliffLocal(address _usr, uint128 _tot, uint48 _bgn, uint24 _tau24, uint24 _eta24, address _mgr, bytes32 _slt, uint24 revokeAfter24) public {
        uint48 _tau = _tau24;
        uint48 _eta = _eta24;
        uint48 revokeAfter = revokeAfter24;
        vm.assume(revokeAfter < _eta);
        vm.assume(checkBounds(_usr, _tot, _bgn, _tau, _eta, DssVest(vest), block.timestamp));
        bytes32 hash = keccak256(abi.encodePacked(_usr, uint256(_tot), uint256(_bgn), uint256(_tau), uint256(_eta), _mgr, _slt));

        // commit
        assertTrue(vest.commitments(hash) == false, "commitment already exists");
        vm.expectEmit(true, true, true, true, address(vest));
        emit Commit(hash);
        vm.prank(ward);
        vest.commit(hash);
        assertTrue(vest.commitments(hash) == true, "commitment does not exist");

        // revoke
        uint256 end = _bgn + revokeAfter;
        vm.warp(end);
        vm.expectEmit(true, true, true, true, address(vest));
        emit Revoke(hash, end);
        vm.prank(ward);
        vest.revoke(hash, end);

        // claim
        vm.expectRevert("DssVest/commitment-revoked-before-cliff");
        vest.claim(hash, _usr, _tot, _bgn, _tau, _eta, _mgr, _slt);

        // make sure nothing changed
        assertTrue(vest.commitments(hash) == true, "commitment does not exist");
        assertTrue(vest.revocations(hash) == end, "revocation not correct");
        assertTrue(vest.ids() == 0, "a vesting plan has been created");
    }

    function testRevokeBeforeEndLocal( uint48 _tau, uint48 _eta,  uint48 revokeAfter) public {
        uint128 _tot = 8127847e18;
        uint48 _bgn = 60 * 365 days;
        bytes32 _slt = 0;

        vm.assume(revokeAfter < type(uint24).max && revokeAfter > 0);
        vm.assume(_eta < type(uint24).max);
        vm.assume(_tau < type(uint24).max && _tau > 0);
        vm.assume(_tau > revokeAfter);
        vm.assume(_eta < revokeAfter);
        vm.assume(_tot > 0);
        vm.assume(type(uint256).max / _tot > revokeAfter); // prevent overflow
        vm.assume(checkBounds(usr, _tot, _bgn, _tau, _eta, DssVest(vest), block.timestamp));
        bytes32 hash = keccak256(abi.encodePacked(usr, uint256(_tot), uint256(_bgn), uint256(_tau), uint256(_eta), ward, _slt));

        // commit
        assertTrue(vest.commitments(hash) == false, "commitment already exists");
        vm.expectEmit(true, true, true, true, address(vest));
        emit Commit(hash);
        vm.prank(ward);
        vest.commit(hash);
        assertTrue(vest.commitments(hash) == true, "commitment does not exist");

        // revoke
        vm.warp(_bgn);
        uint256 end = _bgn + revokeAfter;
        vm.prank(ward);
        vm.expectEmit(true, true, true, true, address(vest));
        emit Revoke(hash, end);
        vest.revoke(hash, end);

        // claim
        vm.warp(uint256(_bgn) + uint256(_tau) + 1);

        uint256 newTot = _tot * uint256(revokeAfter) / uint256(_tau);
        if (newTot == 0) {
            console.log("newTot is 0");
            vm.prank(usr);
            vm.expectRevert("DssVest/no-vest-total-amount");
            vest.claimAndVest(hash, usr, _tot, _bgn, _tau, _eta, ward, _slt);
            // assure no vesting plan has been created
            assertTrue(vest.ids() == 0, "a vesting plan has been created");
        }
        else {
            console.log("newTot is not 0");
            vm.prank(usr);
            vest.claimAndVest(hash, usr, _tot, _bgn, _tau, _eta, ward, _slt);
            // check correct execution
            assertTrue(vest.commitments(hash) == false, "commitment still exists");
            assertTrue(vest.revocations(hash) == _bgn + revokeAfter, "revocation not correct");
            assertTrue(vest.ids() == 1, "no vesting plan has been created");
            assertTrue(vest.accrued(1) == newTot, "accrued is not new total");
            assertTrue(vest.unpaid(1) == 0, "unpaid is not 0");
            assertTrue(gem.balanceOf(usr) == newTot, "balance is not equal to new total");
        }

    }

    function testRevokeAfterEndLocal(uint48 _tau, uint48 _eta,  uint48 revokeAfter) public {
        uint128 _tot = 8127847e18;
        uint48 _bgn = 60 * 365 days;
        bytes32 _slt = 0;

        vm.assume(revokeAfter < type(uint24).max && revokeAfter > 0);
        vm.assume(_eta < type(uint24).max);
        vm.assume(_tau < type(uint24).max && _tau > 0);
        vm.assume(_tau < revokeAfter); // this means that the vesting plan is already over at the time it is revoked
        vm.assume(_tot > 0);
        vm.assume(type(uint256).max / _tot > revokeAfter); // prevent overflow
        vm.assume(checkBounds(usr, _tot, _bgn, _tau, _eta, DssVest(vest), block.timestamp));
        bytes32 hash = keccak256(abi.encodePacked(usr, uint256(_tot), uint256(_bgn), uint256(_tau), uint256(_eta), ward, _slt));

        // commit
        assertTrue(vest.commitments(hash) == false, "commitment already exists");
        vm.expectEmit(true, true, true, true, address(vest));
        emit Commit(hash);
        vm.prank(ward);
        vest.commit(hash);
        assertTrue(vest.commitments(hash) == true, "commitment does not exist");

        // revoke
        vm.warp(_bgn);
        uint256 end = _bgn + revokeAfter;
        vm.prank(ward);
        vm.expectEmit(true, true, true, true, address(vest));
        emit Revoke(hash, end);
        vest.revoke(hash, end);

        // claim
        vm.warp(uint256(_bgn) + uint256(_tau) + 1);

        vm.prank(usr);
        vest.claimAndVest(hash, usr, _tot, _bgn, _tau, _eta, ward, _slt);
        // check correct execution
        assertTrue(vest.commitments(hash) == false, "commitment still exists");
        assertTrue(vest.revocations(hash) == _bgn + revokeAfter, "revocation not correct");
        assertTrue(vest.ids() == 1, "no vesting plan has been created");
        assertTrue(vest.accrued(1) == _tot, "accrued is not original total amount");
        assertTrue(vest.unpaid(1) == 0, "unpaid is not 0");
        assertTrue(gem.balanceOf(usr) == _tot, "balance is not equal to total");
    }

    function testClaimWithModifiedDataLocal(address _usr, address _usr2, uint128 _tot, uint128 _tot2, bytes32 _slt) public {
        vm.assume(_usr != address(0));
        vm.assume(_usr2 != address(0));
        vm.assume(_usr2 != _usr);
        vm.assume(_tot2 != 0 && _tot != 0 && _tot2 != _tot);
        
        uint48 _bgn = uint48(block.timestamp + 400 days);
        uint48 _tau = 600 days;
        uint48 _eta = 200 days;
        address _mgr = address(6);
        
        bytes32 hash = keccak256(abi.encodePacked(_usr, uint256(_tot), uint256(_bgn), uint256(_tau), uint256(_eta), _mgr, _slt));

        // commit
        assertTrue(vest.commitments(hash) == false, "commitment already exists");
        vm.prank(ward);
        vest.commit(hash);
        assertTrue(vest.commitments(hash) == true, "commitment does not exist");

        // claim
        vm.expectRevert("DssVest/invalid-hash");
        vest.claim(hash, _usr2, _tot, _bgn, _tau, _eta, _mgr, _slt);
    

        vm.expectRevert("DssVest/invalid-hash");
        vest.claim(hash, _usr, _tot2, _bgn, _tau, _eta, _mgr, _slt);
        
    }

    function testClaimAndVestLocal(address _usr, uint128 _tot, uint48 _bgn, uint48 _tau, uint48 _eta, address _mgr, bytes32 _slt, address someone) public {
        vm.assume(checkBounds(_usr, _tot, _bgn, _tau, _eta, DssVest(vest), block.timestamp));
        vm.assume(someone != address(0) && someone != _usr && someone != address(forwarder));
        bytes32 hash = keccak256(abi.encodePacked(_usr, uint256(_tot), uint256(_bgn), uint256(_tau), uint256(_eta), _mgr, _slt));

        // commit
        assertTrue(vest.commitments(hash) == false, "commitment already exists");
        vm.expectEmit(true, true, true, true, address(vest));
        emit Commit(hash);
        vm.prank(ward);
        vest.commit(hash);
        assertTrue(vest.commitments(hash) == true, "commitment does not exist");

        // ensure state is as expected before claiming
        assertTrue(gem.balanceOf(_usr) == 0, "balance is not 0");
        assertTrue(vest.ids() == 0, "id is not 0");
        assertEq(vest.commitments(hash), true, "commitment does not exist");

        // 3rd parties can not claim and vest because vests are restricted by default
        vm.prank(someone);
        vm.expectRevert("DssVest/only-user-can-claim");
        vest.claimAndVest(hash, _usr, _tot, _bgn, _tau, _eta, _mgr, _slt);
        
        // claim
        vm.prank(_usr);
        uint256 id = vest.claimAndVest(hash, _usr, _tot, _bgn, _tau, _eta, _mgr, _slt);

        // ensure state changed as expected during claim
        assertEq(id, 1, "id is not 1");
        assertEq(vest.unpaid(id), 0, "unpaid is not 0");
        assertEq(vest.commitments(hash), false, "commitment not deleted");
        // before or after cliff is important
        if (block.timestamp > _bgn + _eta) {
            console.log("After cliff");
            assertEq(vest.accrued(id), gem.balanceOf(_usr), "accrued is not equal to paid");
            checkVestingPlanDetails(id, _usr, _tot, _bgn, _tau, _eta, _mgr, vest.accrued(id));
        } else {
                        console.log("Before cliff");
            checkVestingPlanDetails(id, _usr, _tot, _bgn, _tau, _eta, _mgr, 0);
            assertEq(0, gem.balanceOf(_usr), "payout before cliff");
        }        
        
        // claiming again must fail
        vm.expectRevert("DssVest/commitment-not-found");
        vm.prank(_usr);
        vest.claimAndVest(hash, _usr, _tot, _bgn, _tau, _eta, _mgr, _slt);

        // warp time till end of vesting and vest everything
        vm.warp(_bgn + _tau + 1);
        vm.prank(_usr);
        vest.vest(id);
        assertEq(vest.unpaid(id), 0, "unpaid is not 0");
        assertEq(vest.accrued(id), _tot, "accrued is not equal to total");
        assertEq(gem.balanceOf(_usr), _tot, "balance is not equal to total");
    }

    function checkBounds(address _usr, uint128 _tot, uint48 _bgn, uint48 _tau, uint48 _eta, DssVest _vest, uint256 _timestamp) public view returns (bool valid) {
        valid = _usr != address(0) 
            && _usr != address(forwarder)
            && _tot != 0 
            && _bgn > _timestamp - _vest.TWENTY_YEARS() + 1 days 
            && _bgn < _timestamp + _vest.TWENTY_YEARS() - 1 days
            && _tau < _vest.TWENTY_YEARS()
            && _eta < _tau;
    }

    function checkVestingPlanDetails(uint256 _id, address _usr, uint128 _tot, uint48 _bgn, uint48 _tau, uint48 _eta, address _mgr, uint256 _rxd) public {
        // check vesting details (looks complicated because of solidity local variables limitations)    
        address usrOrMgr;
        (usrOrMgr,,,,,,, ) = vest.awards(_id);
        assertEq(usrOrMgr, _usr, "usr is not equal");
        (,,,, usrOrMgr,,, ) = vest.awards(_id);
        assertEq(usrOrMgr, _mgr, "mgr is not equal");

        uint128 uintVal;
        (, uintVal,,,,,, ) = vest.awards(_id);
        assertEq(uintVal, _bgn, "bgn is not equal");
        (,, uintVal,,,,, ) = vest.awards(_id);
        assertEq(uintVal, _bgn + _eta, "clf is wrong");
        (,,, uintVal,,,, ) = vest.awards(_id);
        assertEq(uintVal, _bgn + _tau, "fin is wrong");
        (,,,,, uintVal,, ) = vest.awards(_id);
        assertEq(uintVal, 1, "vest is not restricted");
        (,,,,,, uintVal, ) = vest.awards(_id);
        assertEq(uintVal, _tot, "tot is not equal");
        (,,,,,,, uintVal) = vest.awards(_id);
        assertEq(uintVal, _rxd, "rxd is wrong");
    }

}
