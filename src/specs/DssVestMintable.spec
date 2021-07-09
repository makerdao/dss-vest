// DssVestMintable.spec

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

    assert(wards(e, usr) == 1, "Rely did not set the wards as expected");
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    uint256 ward = wards(e, e.msg.sender);

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

    assert(wards(e, usr) == 0, "Deny did not set the wards as expected");
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    uint256 ward = wards(e, e.msg.sender);

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

    assert(cap(e) == data, "File did not set cap as expected");
}

// Verify revert rules on file
rule file_revert(bytes32 what, uint256 data) {
    env e;

    uint256 ward = wards(e, e.msg.sender);

    file@withrevert(e, what, data);

    bool revert1 = ward != 1;
    bool revert2 = what != 0x6361700000000000000000000000000000000000000000000000000000000000; // what != "cap"
    bool revert3 = e.msg.value > 0;

    assert(revert1 => lastReverted, "Lack of auth did not revert");
    assert(revert2 => lastReverted, "File unrecognized param did not revert");
    assert(revert3 => lastReverted, "Sending ETH did not revert");
    assert(lastReverted => revert1 || revert2 || revert3, "Revert rules are not covering all the cases");
}

// Verify that awards behaves correctly on init
rule init(address _usr, uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _clf, address _mgr) {
    env e;

    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    uint256 prevId = ids(e);

    uint256 id = init(e, _usr, _tot, _bgn, _tau, _clf, _mgr);

    usr, bgn, clf, fin, tot, rxd, mgr = awards(e, id);

    assert(ids(e) == prevId + 1, "Init did not increase the Ids as expected");
    assert(ids(e) == id, "Init did not return the Id as expected");
    assert(valid(e, id), "Init did not return a valid Id");
    assert(usr == _usr, "Init did not set usr as expected");
    assert(bgn == _bgn, "Init did not set bgn as expected");
    assert(clf == _bgn + _clf, "Init did not set clf as expected");
    assert(fin == _bgn + _tau, "Init did not set fin as expected");
    assert(tot == _tot, "Init did not set tot as expected");
    assert(rxd == 0, "Init did not set rxd as expected");
    assert(mgr == _mgr, "Init did not set mgr as expected");
}

// Verify revert rules on init
rule init_revert(address _usr, uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _clf, address _mgr) {
    env e;

    uint256 ward = wards(e, e.msg.sender);
    uint256 twenty_years = TWENTY_YEARS(e);
    uint256 _cap = cap(e);
    uint256 _ids = ids(e);

    init@withrevert(e, _usr, _tot, _bgn, _tau, _clf, _mgr);
    uint256 locked = lockedGhost();

    uint256 clf = _bgn + _clf;
    uint256 fin = _bgn + _tau;

    uint256 max_uint48 = 2^48 - 1;

    bool revert1  = ward != 1;
    bool revert2  = locked != 0;
    bool revert3  = _usr == 0;
    bool revert4  = _tot == 0;
    bool revert5  = e.block.timestamp + twenty_years > max_uint;
    bool revert6  = _bgn >= e.block.timestamp + twenty_years;
    bool revert7  = e.block.timestamp < twenty_years;
    bool revert8  = _bgn <= e.block.timestamp - twenty_years;
    bool revert9  = _tau == 0;
    bool revert10 = _tot / _tau > _cap;
    bool revert11 = _tau > twenty_years;
    bool revert12 = _clf > _tau;
    bool revert13 = _ids >= max_uint;
    bool revert14 = _bgn > max_uint48;
    bool revert15 = clf > max_uint48;
    bool revert16 = fin > max_uint48;
    // Remove the - 1 from the next rule when the require(_tot < uint128(-1)) is removed from the code
    // toUint128(tot) already protects from overflow
    bool revert17 = _tot > max_uint128 - 1;
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

    uint256 WAD = 10^18;

    address _usrB; uint48 _bgnB; uint48 _clfB; uint48 _finB; uint128 _totB; uint128 _rxdB; address _mgrB;
    _usrB, _bgnB, _clfB, _finB, _totB, _rxdB, _mgrB  = awards(e, _id);

    require(_finB > 0);

    uint256 amt = unpaid(e, _id);
    // uint256 t = (e.block.timestamp - _bgn) * WAD / _fin;

    bool timeLeClif = e.block.timestamp < _clfB;
    bool timeLeBgn = e.block.timestamp < _bgnB;
    bool timeHioEqFin = e.block.timestamp >= _finB;

    vest(e, _id);

    // address _usrA; uint48 _bgnA; uint48 _clfA; uint48 _finA; uint128 _totA; uint128 _rxdA; address _mgrA;
    // usrA, bgnA, clfA, finA, totA, rxdA, mgrA  = awards(e, _id);
    // uint256 gem = _totA * t / WAD;

    assert(timeLeClif => amt == 0, "Vest did not set amt as expected");
    // assert(!timeLeClif && timeLeBgn => amt == _rxd, "Vest did not set amt as expected");
    assert(!timeLeClif && !timeLeBgn && timeHioEqFin => amt == _totB - _rxdB, "Vest did not set amt as expected");
    // assert(!timeLeClif && !timeLeBgn && !timeHioEqFin => t >= 0 && t < WAD, "T exceed expected range");
    // assert(!timeLeClif && !timeLeBgn && !timeHioEqFin => gem >= 0 && gem < tot, "Gem exceed expected range");
    // assert(!timeLeClif && !timeLeBgn && !timeHioEqFin => amt == gem - _rxd, "Vest did not set amt as expected");
    // assert(amt < max_uint => rxd == amt + _rxd, "Vest did not set rxd as expected");
}

// Verify revert rules on vest
rule vest_revert(uint256 _id) {
    env e;

    uint256 rstd = restricted(e, _id);
    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr  = awards(e, _id);
    uint256 amt = unpaid(e, _id);

    vest@withrevert(e, _id);
    uint256 locked = lockedGhost();

    bool revert1 = locked != 0;
    bool revert2 = rstd != 0 && e.msg.sender != usr;
    bool revert3 = rxd + amt < rxd;
    bool revert4 = rxd + amt > max_uint128;
    bool revert5 = e.msg.value > 0;

    assert(revert1 => lastReverted, "Locked did not revert");
    assert(revert2 => lastReverted, "Only user can claim did not revert");
    assert(revert3 => lastReverted, "Addition overflow did not revert");
    assert(revert4 => lastReverted, "Rxd toUint128 cast overflow did not revert");
    assert(revert5 => lastReverted, "Sending ETH did not revert");
    assert(lastReverted => revert1 || revert2 || revert3 || revert4 || revert5, "Revert rules are not covering all the cases");
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

    uint256 ward = wards(e, e.msg.sender);
    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr  = awards(e, _id);

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

    uint256 ward = wards(e, e.msg.sender);
    address usr; uint48 bgn; uint48 clf; uint48 fin; uint128 tot; uint128 rxd; address mgr;
    usr, bgn, clf, fin, tot, rxd, mgr  = awards(e, _id);

    unrestrict@withrevert(e, _id);

    bool revert1 = ward != 1 && usr != e.msg.sender;
    bool revert2 = e.msg.value > 0;

    assert(revert1 => lastReverted, "Only governance or owner can unrestrict did not revert");
    assert(revert2 => lastReverted, "Sending ETH did not revert");
    assert(lastReverted => revert1 || revert2, "Revert rules are not covering all the cases");
}
