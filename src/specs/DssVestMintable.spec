// DssVestMintable.spec

// certoraRun src/DssVest.sol:DssVestMintable src/specs/DSToken.sol src/specs/MockAuthority.sol --link DssVestMintable:gem=DSToken DSToken:authority=MockAuthority --verify DssVestMintable:src/specs/DssVestMintable.spec --optimistic_loop --rule_sanity

using DSToken as token
using MockAuthority as authority

methods {
    wards(address) returns (uint256) envfree
    awards(uint256) returns (address, uint48, uint48, uint48, address, uint8, uint128, uint128) envfree
    usr(uint256) returns (address) envfree
    rxd(uint256) returns (uint256) envfree
    res(uint256) returns (uint256) envfree
    ids() returns (uint256) envfree
    cap() returns (uint256) envfree
    gem() returns (address) envfree
    valid(uint256) returns (bool) envfree
    TWENTY_YEARS() returns (uint256) envfree
    token.balanceOf(address) returns (uint256) envfree
    token.totalSupply() returns (uint256) envfree
    token.authority() returns (address) envfree
}

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

// Verify that awards behaves correctly on create
rule create(address _usr, uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _eta, address _mgr) {
    env e;

    address usr; uint48 bgn; uint48 clf; uint48 fin; address mgr; uint8 res; uint128 tot; uint128 rxd;
    uint256 prevId = ids();

    uint256 id = create(e, _usr, _tot, _bgn, _tau, _eta, _mgr);

    usr, bgn, clf, fin, mgr, res, tot, rxd = awards(id);

    assert(ids() == prevId + 1, "Init did not increase the Ids as expected");
    assert(ids() == id, "Init did not return the Id as expected");
    assert(valid(id), "Init did not return a valid Id");
    assert(usr == _usr, "Init did not set usr as expected");
    assert(bgn == _bgn, "Init did not set bgn as expected");
    assert(clf == _bgn + _eta, "Init did not set clf as expected");
    assert(fin == _bgn + _tau, "Init did not set fin as expected");
    assert(tot == _tot, "Init did not set tot as expected");
    assert(rxd == 0, "Init did not set rxd as expected");
    assert(mgr == _mgr, "Init did not set mgr as expected");
    assert(res == 0, "Init did not set res as expected");
}

// Verify revert rules on create
rule create_revert(address _usr, uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _eta, address _mgr) {
    env e;

    uint256 ward = wards(e.msg.sender);
    uint256 twenty_years = TWENTY_YEARS();
    uint256 _cap = cap();
    uint256 _ids = ids();
    uint256 locked = lockedGhost();

    create@withrevert(e, _usr, _tot, _bgn, _tau, _eta, _mgr);

    uint256 clf = _bgn + _eta;
    uint256 fin = _bgn + _tau;

    bool revert1  = ward != 1;
    bool revert2  = locked != 0;
    bool revert3  = _usr == 0;
    bool revert4  = _tot == 0;
    bool revert5  = e.block.timestamp + twenty_years > max_uint256;
    bool revert6  = _bgn >= e.block.timestamp + twenty_years;
    bool revert7  = e.block.timestamp < twenty_years;
    bool revert8  = _bgn <= e.block.timestamp - twenty_years;
    bool revert9  = _tau == 0;
    bool revert10 = _tot / _tau > _cap;
    bool revert11 = _tau > twenty_years;
    bool revert12 = _eta > _tau;
    bool revert13 = _ids >= max_uint256;
    bool revert14 = _bgn > max_uint48();
    bool revert15 = clf > max_uint48();
    bool revert16 = fin > max_uint48();
    bool revert17 = _tot > max_uint128;
    bool revert18 = e.msg.value > 0;

    assert(revert1  => lastReverted, "Lack of auth did not revert");
    assert(revert2  => lastReverted, "Locked did not revert");
    assert(revert3  => lastReverted, "Invalid user did not revert");
    assert(revert4  => lastReverted, "No vest total ammount did not revert");
    assert(revert5  => lastReverted, "Addition overflow did not revert 17");
    assert(revert6  => lastReverted, "Starting timestamp too far did not revert");
    assert(revert7  => lastReverted, "Subtraction underflow did not revert");
    assert(revert8  => lastReverted, "Starting timestamp too long ago did not revert");
    assert(revert9  => lastReverted, "Tau zero did not revert");
    assert(revert10 => lastReverted, "Rate too high did not revert");
    assert(revert11 => lastReverted, "Tau too long did not revert");
    assert(revert12 => lastReverted, "Cliff too long did not revert");
    assert(revert13 => lastReverted, "Ids overflow did not revert");
    assert(revert14 => lastReverted, "Starting timestamp toUint48 cast did not revert");
    assert(revert15 => lastReverted, "Cliff toUint48 cast overflow did not revert");
    assert(revert16 => lastReverted, "Fin toUint48 cast overflow did not revert");
    assert(revert17 => lastReverted, "Tot toUint128 cast overflow did not revert");
    assert(revert18 => lastReverted, "Sending ETH did not revert");

    assert(lastReverted =>
            revert1  || revert2  || revert3  ||
            revert4  || revert5  || revert6  ||
            revert7  || revert8  || revert9  ||
            revert10 || revert11 || revert12 ||
            revert13 || revert14 || revert15 ||
            revert16 || revert17 || revert18, "Revert rules are not covering all the cases");
}

// Verify that awards behaves correctly on vest
rule vest(uint256 _id) {
    env e;

    address usr; uint48 bgn; uint48 clf; uint48 fin; address mgr; uint8 res; uint128 tot; uint128 rxd;
    usr, bgn, clf, fin, mgr, res, tot, rxd = awards(_id);

    require(usr != 0);
    require(tot > 0);
    require(fin > bgn);
    require(fin >= clf);
    require(clf >= bgn);
    require(rxd <= tot);

    uint256 amt = (
        e.block.timestamp >= fin
            ? tot
            : (tot * (e.block.timestamp - bgn)) / (fin - bgn)
    ) - rxd;

    uint256 balanceBefore = token.balanceOf(usr);
    uint256 supplyBefore = token.totalSupply();

    vest(e, _id);

    address usr2; uint48 bgn2; uint48 clf2; uint48 fin2; address mgr2; uint8 res2; uint128 tot2; uint128 rxd2;
    usr2, bgn2, clf2, fin2, mgr2, res2, tot2, rxd2 = awards(_id);

    uint256 balanceAfter = token.balanceOf(usr);
    uint256 supplyAfter = token.totalSupply();

    assert(usr2 == usr, "usr changed");
    assert(bgn2 == bgn, "bgn changed");
    assert(clf2 == clf, "clf changed");
    assert(fin2 == fin, "fin changed");
    assert(tot2 == tot, "tot changed");
    assert(mgr2 == mgr, "mgr changed");
    // assert(rxd2 <= tot, "rxd got higher than total");
    assert(e.block.timestamp < clf => rxd2 == rxd, "rxd did not remain as expected");
    assert(e.block.timestamp < clf => balanceAfter == balanceBefore, "balance did not remain as expected");
    assert(e.block.timestamp < clf => supplyAfter == supplyBefore, "supply did not remain as expected");
    assert(e.block.timestamp >= fin => rxd2 == tot, "Vest did not take the whole amount as expected");
    assert(e.block.timestamp >= clf => rxd2 == rxd + amt, "Vest did not take the proportional amount as expected");
    // assert(e.block.timestamp >= clf && e.block.timestamp < fin => rxd2 < tot, "rxd should not complete tot before time");
    assert(e.block.timestamp >= clf => balanceAfter == balanceBefore + amt, "balance did not increase as expected");
    assert(e.block.timestamp >= clf => supplyAfter == supplyBefore + amt, "supply did not increase as expected");
}

// Verify revert rules on vest
rule vest_revert(uint256 _id) {
    env e;

    require(token == gem());
    require(authority == token.authority());

    address tokenOwner = token.owner(e);
    bool canCall = authority.canCall(e, currentContract, token, 0x40c10f1900000000000000000000000000000000000000000000000000000000);
    bool stop = token.stopped(e);
    address _usr = usr(_id);
    uint256 _rxd = rxd(_id);
    uint256 _res = res(_id);
    uint256 usrBalance = token.balanceOf(_usr);
    uint256 supply = token.totalSupply();
    uint256 amt = unpaid(e, _id);
    uint256 locked = lockedGhost();

    vest@withrevert(e, _id);

    bool revert1 = locked != 0;
    bool revert2 = _res != 0 && _usr != e.msg.sender;
    bool revert3 = _rxd + amt < _rxd;
    bool revert4 = _rxd + amt > max_uint128;
    bool revert5 = e.msg.value > 0;
    bool revert6 = currentContract != token && currentContract != tokenOwner && (authority == 0 || !canCall);
    bool revert7 = stop == true;
    bool revert8 = usrBalance + amt > max_uint256;
    bool revert9 = supply + amt > max_uint256;

    assert(revert1 => lastReverted, "Locked did not revert");
    assert(revert2 => lastReverted, "Only user can claim did not revert");
    assert(revert3 => lastReverted, "Addition overflow did not revert");
    assert(revert4 => lastReverted, "Rxd toUint128 cast overflow did not revert");
    assert(revert5 => lastReverted, "Sending ETH did not revert");
    assert(revert6 => lastReverted, "Lack of auth did not revert");
    assert(revert7 => lastReverted, "Stopped did not revert");
    assert(revert8 => lastReverted, "Usr balance overflow did not revert");
    assert(revert9 => lastReverted, "Total supply overflow did not revert");
    assert(lastReverted =>
            revert1 || revert2 || revert3 ||
            revert4 || revert5 || revert6 ||
            revert7 || revert8 || revert9, "Revert rules are not covering all the cases");
}

// Verify that amt behaves correctly on accrued
rule accrued(uint256 _id) {
    env e;

    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr  = awards(_id);

    require(fin > bgn);

    uint256 gem = tot * ((e.block.timestamp - bgn) * WAD() / (fin - bgn)) / WAD();

    uint256 amt = accrued(e, _id);

    assert(e.block.timestamp < bgn => amt == 0, "Accrued did not return amt equal to zero as expected");
    assert(e.block.timestamp >= bgn && e.block.timestamp >= fin => amt == tot, "Accrued did not return amt equal to tot as expected");
    assert(e.block.timestamp >= bgn && e.block.timestamp < fin => amt == gem, "Accrued did not return amt equal to gem as expected");
}

// Verify revert rules on accrued
rule accrued_revert(uint256 _id) {
    env e;

    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr  = awards(_id);
    uint256 timeDelta = e.block.timestamp - bgn;

    accrued@withrevert(e, _id);

    bool revert1 = usr == 0;
    bool revert2 = e.block.timestamp >= bgn && e.block.timestamp < fin && timeDelta > e.block.timestamp;
    bool revert3 = e.block.timestamp >= bgn && e.block.timestamp < fin && (timeDelta * WAD()) / WAD() != timeDelta;
    bool revert4 = e.block.timestamp >= bgn && e.block.timestamp < fin && fin - bgn > fin;
    bool revert5 = e.msg.value > 0;

    assert(revert1 => lastReverted, "Invalid award did not revert");
    assert(revert2 => lastReverted, "Subtraction underflow timeDelta did not revert");
    assert(revert3 => lastReverted, "Multiplication overflow did not revert");
    assert(revert4 => lastReverted, "Subtraction underflow fin did not revert");
    assert(revert5 => lastReverted, "Sending ETH did not revert");
    assert(lastReverted =>
            revert1 || revert2 || revert3 ||
            revert4 || revert5, "Revert rules are not covering all the cases");
}

// Verify that amt behaves correctly on unpaid
rule unpaid(uint256 _id) {
    env e;

    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr  = awards(_id);
    uint amtAccrued = accrued(e, _id);

    uint256 amt = unpaid(e, _id);

    assert(e.block.timestamp < clf => amt == 0, "Unpaid did not return amt equal to zero as expected");
    assert(e.block.timestamp >= clf => amt == amtAccrued - rxd, "Unpaid did not return amt as expected");
}

// Verify revert rules on unpaid
rule unpaid_revert(uint256 _id) {
    env e;

    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr  = awards(_id);
    uint256 timeDelta = e.block.timestamp - bgn;
    uint amtAccrued = accrued(e, _id);

    require(fin > bgn);

    uint256 t = (e.block.timestamp - bgn) * WAD() / (fin - bgn);

    unpaid@withrevert(e, _id);

    bool revert1 = usr == 0;
    bool revert2 = e.block.timestamp >= clf && e.block.timestamp >= bgn && e.block.timestamp < fin && timeDelta > e.block.timestamp;
    bool revert3 = e.block.timestamp >= clf && e.block.timestamp >= bgn && e.block.timestamp < fin && (timeDelta * WAD()) / WAD() != timeDelta;
    bool revert4 = e.block.timestamp >= clf && e.block.timestamp >= bgn && e.block.timestamp < fin && fin - bgn > fin;
    bool revert5 = e.block.timestamp >= clf && e.block.timestamp >= bgn && e.block.timestamp < fin && tot * t / t != tot;
    bool revert6 = e.block.timestamp >= clf && amtAccrued - rxd > amtAccrued;
    bool revert7 = e.msg.value > 0;

    assert(revert1 => lastReverted, "Invalid award did not revert");
    assert(revert2 => lastReverted, "Subtraction underflow timeDelta did not revert");
    assert(revert3 => lastReverted, "Multiplication overflow did not revert");
    assert(revert4 => lastReverted, "Subtraction underflow fin did not revert");
    assert(revert5 => lastReverted, "Multiplication overflow tot did not revert");
    assert(revert6 => lastReverted, "Substraction underflow amtAccrued did not revert");
    assert(revert7 => lastReverted, "Sending ETH did not revert");
    assert(lastReverted =>
            revert1 || revert2 || revert3 ||
            revert4 || revert5 || revert6 ||
            revert7, "Revert rules are not covering all the cases");
}

// Verify that restricted behaves correctly on restrict
rule restrict(uint256 _id) {
    env e;

    restrict(e, _id);

    assert(restricted(e, _id) == 1, "Restrict did not set restricted as expected");
}

// Verify revert rules on restrict
rule restrict_revert(uint256 _id) {
    env e;

    uint256 ward = wards(e.msg.sender);
    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr  = awards(_id);

    restrict@withrevert(e, _id);

    bool revert1 = ward != 1 && usr != e.msg.sender;
    bool revert2 = e.msg.value > 0;

    assert(revert1 => lastReverted, "Only governance or owner can restrict did not revert");
    assert(revert2 => lastReverted, "Sending ETH did not revert");
    assert(lastReverted => revert1 || revert2, "Revert rules are not covering all the cases");
}

// Verify that restricted behaves correctly on unrestrict
rule unrestrict(uint256 _id) {
    env e;

    unrestrict(e, _id);

    assert(restricted(e, _id) == 0, "Restrict did not set restricted as expected");
}

// Verify revert rules on unrestrict
rule unrestrict_revert(uint256 _id) {
    env e;

    uint256 ward = wards(e.msg.sender);
    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr  = awards(_id);

    unrestrict@withrevert(e, _id);

    bool revert1 = ward != 1 && usr != e.msg.sender;
    bool revert2 = e.msg.value > 0;

    assert(revert1 => lastReverted, "Only governance or owner can unrestrict did not revert");
    assert(revert2 => lastReverted, "Sending ETH did not revert");
    assert(lastReverted => revert1 || revert2, "Revert rules are not covering all the cases");
}

// Verify that awards behaves correctly on yank
rule yank(uint256 _id) {
    env e;

    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr = awards(_id);

    require(fin > bgn);
    require(fin >= clf);
    require(clf >= bgn);
    require(rxd <= tot);

    uint256 amt = (
        e.block.timestamp >= fin
            ? tot
            : tot * ((e.block.timestamp - bgn) * WAD() / (fin - bgn)) / WAD()
    );

    yank(e, _id);

    address usr2; uint48 bgn2; uint48 clf2; uint48 fin2; uint128 tot2; uint128 rxd2; address mgr2;
    usr2, bgn2, clf2, fin2, tot2, rxd2, mgr2 = awards(_id);

    assert(e.block.timestamp > fin => fin2 == fin, "Yank did not set fin as expected");
    assert(e.block.timestamp < clf => tot2 == rxd, "Yank did not set tot as expected");
    assert(e.block.timestamp >= clf => tot2 == amt, "Yank did not set tot as expected");
}

// Verify revert rules on yank
rule yank_revert(uint256 _id) {
    env e;

    uint256 ward = wards(e.msg.sender);
    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr  = awards(_id);
    uint256 timeDelta = e.block.timestamp - bgn;
    uint256 amt = unpaid(e, _id);

    require(fin > bgn);

    yank@withrevert(e, _id);

    bool revert1  = ward != 1 && mgr != e.msg.sender;
    bool revert2  = usr == 0;
    bool revert3  = fin > max_uint48();
    bool revert4  = e.block.timestamp < clf && rxd < 0;
    bool revert5  = e.block.timestamp >= clf && amt + rxd > max_uint128;
    bool revert6  = e.block.timestamp >= clf && amt + rxd < amt;
    bool revert7  = e.block.timestamp >= clf && e.block.timestamp >= bgn && e.block.timestamp < fin && timeDelta > e.block.timestamp;
    bool revert8  = e.block.timestamp >= clf && e.block.timestamp >= bgn && e.block.timestamp < fin && (timeDelta * WAD()) / WAD() != timeDelta;
    bool revert9  = e.block.timestamp >= clf && e.block.timestamp >= bgn && e.block.timestamp < fin && fin - bgn > fin;
    bool revert10 = e.msg.value > 0;

    assert(revert1  => lastReverted, "Not authorized did not revert");
    assert(revert2  => lastReverted, "Invalid award did not revert");
    assert(revert3  => lastReverted, "Fin toUint48 cast did not revert");
    assert(revert4  => lastReverted, "Addition overflow rxd did not revert");
    assert(revert5  => lastReverted, "Amt toUint128 cast did not revert");
    assert(revert6  => lastReverted, "Addition overflow amt did not revert");
    assert(revert7  => lastReverted, "Subtraction underflow timeDelta did not revert");
    assert(revert8  => lastReverted, "Multiplication overflow did not revert");
    assert(revert9  => lastReverted, "Subtraction underflow fin did not revert");
    assert(revert10 => lastReverted, "Sending ETH did not revert");
    assert(lastReverted =>
            revert1  || revert2 || revert3 ||
            revert4  || revert5 || revert6 ||
            revert7  || revert8 || revert9 ||
            revert10, "Revert rules are not covering all the cases");
}

// Verify that awards behaves correctly on yank with arbitrary end
rule yank_end(uint256 _id, uint256 _end) {
    env e;

    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr = awards(_id);

    require(fin > bgn);
    require(fin >= clf);
    require(clf >= bgn);
    require(rxd <= tot);

    uint256 amt = (
        e.block.timestamp >= fin
            ? tot
            : tot * ((e.block.timestamp - bgn) * WAD() / (fin - bgn)) / WAD()
    );

    yank(e, _id, _end);

    address usr2; uint48 bgn2; uint48 clf2; uint48 fin2; uint128 tot2; uint128 rxd2; address mgr2;
    usr2, bgn2, clf2, fin2, tot2, rxd2, mgr2 = awards(_id);

    assert(_end < e.block.timestamp => fin2 == e.block.timestamp, "Yank did not set fin equal block timestamp as expected");
    assert(_end >= e.block.timestamp && _end > fin => fin2 == fin, "Yank did not set fin as expected");
    assert(_end < e.block.timestamp && e.block.timestamp < clf => tot2 == rxd, "Yank did not set tot equal rxd as expected");
    assert(_end < e.block.timestamp && e.block.timestamp >= clf => tot2 == amt, "Yank did not set tot equal amt as expected");
    assert(_end > fin && fin >= clf => tot2 == tot, "Yank did not set tot as expected");
}

// Verify revert rules on yank_end
rule yank_end_revert(uint256 _id, uint256 _end) {
    env e;

    uint256 ward = wards(e.msg.sender);
    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr  = awards(_id);
    uint256 timeDelta = e.block.timestamp - bgn;
    uint256 amt = unpaid(e, _id);

    require(fin > bgn);

    yank@withrevert(e, _id, _end);

    bool revert1  = ward != 1 && mgr != e.msg.sender;
    bool revert2  = usr == 0;
    bool revert3  = _end < fin && fin > max_uint48();
    bool revert4  = _end < e.block.timestamp && e.block.timestamp > max_uint48();
    bool revert5  = e.block.timestamp < clf && rxd < 0;
    bool revert6  = fin < clf && rxd < 0;
    bool revert7  = e.block.timestamp < clf && rxd > max_uint128;
    bool revert8  = fin < clf && rxd > max_uint128;
    bool revert9  = e.block.timestamp >= clf && amt + rxd > max_uint128;
    bool revert10 = fin >= clf && tot > max_uint128;
    bool revert11 = e.block.timestamp >= clf && amt + rxd < amt;
    bool revert12 = e.block.timestamp >= clf && e.block.timestamp < bgn && rxd > 0;
    bool revert13 = fin >= clf && tot + rxd < tot;
    bool revert14 = e.block.timestamp >= clf && e.block.timestamp >= bgn && e.block.timestamp < fin && timeDelta > e.block.timestamp;
    bool revert15 = fin >= clf && tot - rxd > tot;
    bool revert16 = e.block.timestamp >= clf && e.block.timestamp >= bgn && e.block.timestamp < fin && (timeDelta * WAD()) / WAD() != timeDelta;
    bool revert17 = e.block.timestamp >= clf && e.block.timestamp >= bgn && e.block.timestamp < fin && fin - bgn > fin;
    bool revert18 = _end >= clf && _end >= bgn && _end < fin && _end - bgn > _end;
    bool revert19 = _end >= clf && _end >= bgn && _end < fin && fin - bgn > fin;
    bool revert20 = e.msg.value > 0;

    assert(revert1  => lastReverted, "Not authorized did not revert");
    assert(revert2  => lastReverted, "Invalid award did not revert");
    assert(revert3  => lastReverted, "Fin toUint48 cast did not revert");
    assert(revert4  => lastReverted, "Block timestamp toUint48 cast did not revert");
    assert(revert5  => lastReverted, "Addition overflow rxd did not revert with end set as block timestamp");
    assert(revert6  => lastReverted, "Addition overflow rxd did not revert with end set as fin");
    assert(revert7  => lastReverted, "Rxd toUint128 cast did not revert with end set as block timestamp");
    assert(revert8  => lastReverted, "Rxd toUint128 cast did not revert with end set as fin");
    assert(revert9  => lastReverted, "Amt toUint128 cast did not revert with end set as block timestamp");
    assert(revert10 => lastReverted, "Tot toUint128 cast did not revert with end set as fin");
    assert(revert11 => lastReverted, "Addition overflow amt did not revert with end set as block timestamp");
    assert(revert12 => lastReverted, "Substraction underflow rxd did not revert");
    assert(revert13 => lastReverted, "Addition overflow amt did not revert with end set as fin");
    assert(revert14 => lastReverted, "Subtraction underflow timeDelta did not revert");
    assert(revert15 => lastReverted, "Substraciton underflow tot minus rxd did not revert");
    assert(revert16 => lastReverted, "Multiplication overflow did not revert");
    assert(revert17 => lastReverted, "Subtraction underflow fin did not revert");
    assert(revert18 => lastReverted, "Subtraction underflow end did not revert");
    assert(revert19 => lastReverted, "Substraction underlow fin minus bgn did not revert");
    assert(revert20 => lastReverted, "Sending ETH did not revert");
    assert(lastReverted =>
            revert1  || revert2  || revert3  ||
            revert4  || revert5  || revert6  ||
            revert7  || revert8  || revert9  ||
            revert10 || revert11 || revert12 ||
            revert13 || revert14 || revert15 ||
            revert16 || revert17 || revert18 ||
            revert19 || revert20, "Revert rules are not covering all the cases");

}

// Verify that dst behaves correctly on move
rule move(uint256 _id, address _dst) {
    env e;

    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;

    move(e, _id, _dst);

    usr, bgn, clf, fin, tot, rxd, mgr  = awards(_id);

    assert(usr == _dst, "Move did not set usr as expected");
}

// Verify revert rules on move
rule move_revert(uint256 _id, address _dst) {
    env e;

    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr  = awards(_id);

    move@withrevert(e, _id, _dst);

    bool revert1 = usr != e.msg.sender;
    bool revert2 = _dst == 0;
    bool revert3 = e.msg.value > 0;

    assert(revert1 => lastReverted, "Only user can move did not revert");
    assert(revert2 => lastReverted, "Zero address invalid did not revert");
    assert(revert3 => lastReverted, "Sending ETH did not revert");
    assert(lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases");
}

// Verify that id behaves correctly on valid
rule valid(uint256 _id) {
    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr  = awards(_id);

    bool validContract = rxd < tot;

    bool isValid = valid(_id);

    assert(validContract => isValid, "Valid did not set isValid as expected when contract is valid");
    assert(!validContract => !isValid, "Valid did not set isValid as expected when contract is not valid");
}
