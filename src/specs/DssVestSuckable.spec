// DssVestSuckable.spec

// certoraRun src/DssVest.sol:DssVestSuckable src/specs/Vat.sol src/specs/DaiJoin.sol --link DssVestSuckable:vat=Vat DssVestSuckable:daiJoin=DaiJoin --verify DssVestSuckable:src/specs/DssVestSuckable.spec --optimistic_loop --rule_sanity

methods {
    wards(address) returns (uint256) envfree
    awards(uint256) returns (address, uint48, uint48, uint48, uint128, uint128, address) envfree
    ids() returns (uint256) envfree
    cap() returns (uint256) envfree
    gem() returns (address) envfree
    valid(uint256) returns (bool) envfree
    TWENTY_YEARS() returns (uint256) envfree
    token.balanceOf(address) returns (uint256) envfree
    token.totalSupply() returns (uint256) envfree
    token.authority() returns (address) envfree
}

definition WAD() returns uint256 = 10^18;
definition max_uint48() returns uint256 = 2^48 - 1;

ghost lockedGhost() returns uint256;

hook Sstore locked uint256 n_locked STORAGE {
    havoc lockedGhost assuming lockedGhost@new() == n_locked;
}

hook Sload uint256 value locked STORAGE {
    require lockedGhost() == value;
}

// Verify that wards behaves correctly on rely
rule rely(address usr) {
    env e;

    rely(e, usr);

    assert(wards(usr) == 1, "Rely did not set the wards as expected");
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    uint256 ward = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = ward != 1;
    bool revert2 = e.msg.value > 0;

    assert(revert1 => lastReverted, "Lack of auth did not revert");
    assert(revert2 => lastReverted, "Sending ETH did not revert");
    assert(lastReverted => revert1 || revert2, "Revert rules are not covering all the cases");
}

// Verify that wards behaves correctly on deny
rule deny(address usr) {
    env e;

    deny(e, usr);

    assert(wards(usr) == 0, "Deny did not set the wards as expected");
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    uint256 ward = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = ward != 1;
    bool revert2 = e.msg.value > 0;

    assert(revert1 => lastReverted, "Lack of auth did not revert");
    assert(revert2 => lastReverted, "Sending ETH did not revert");
    assert(lastReverted => revert1 || revert2, "Revert rules are not covering all the cases");
}

// Verify that cap behave correctly on file
rule file(bytes32 what, uint256 data) {
    env e;

    file(e, what, data);

    assert(cap() == data, "File did not set cap as expected");
}

// Verify revert rules on file
rule file_revert(bytes32 what, uint256 data) {
    env e;

    uint256 ward = wards(e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = ward != 1;
    bool revert2 = what != 0x6361700000000000000000000000000000000000000000000000000000000000; // what != "cap"
    bool revert3 = e.msg.value > 0;

    assert(revert1 => lastReverted, "Lack of auth did not revert");
    assert(revert2 => lastReverted, "File unrecognized param did not revert");
    assert(revert3 => lastReverted, "Sending ETH did not revert");
    assert(lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases");
}
