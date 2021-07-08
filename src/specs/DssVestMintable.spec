// DssVestMintable.spec

// Verify that wards behaves correctly on rely
rule rely(address usr) {
    env e;

    uint256 ward = wards(e, e.msg.sender);

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

    uint256 ward = wards(e, e.msg.sender);

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

    uint256 clf = _bgn + _clf;
    uint256 fin = _bgn + _tau;

    bool revert1  = ward != 1;
    bool revert2  = _usr == 0;
    bool revert3  = _tot == max_uint128;
    bool revert4  = _tot == 0;
    bool revert5  = _bgn >= e.block.timestamp + twenty_years;
    bool revert6  = _bgn <= e.block.timestamp - twenty_years;
    bool revert7  = _tau == 0;
    bool revert8  = _tot / _tau > _cap;
    bool revert9  = _tau > twenty_years;
    bool revert10 = _clf > _tau;
    bool revert11 = _ids == max_uint;
    bool revert12 = _bgn > max_uint96 / 2;
    bool revert13 = clf > max_uint96 / 2;
    bool revert14 = fin > max_uint96 / 2;
    bool revert15 = _tot > max_uint128;
    bool revert16 = e.msg.value > 0;
    bool revert17 = e.block.timestamp + twenty_years < e.block.timestamp;
    bool revert18 = e.block.timestamp - twenty_years > e.block.timestamp;
    bool revert19 = clf < _bgn;
    bool revert20 = fin < _bgn;

    assert(revert1  => lastReverted, "Lack of auth did not revert");
    assert(revert2  => lastReverted, "Invalid user did not revert");
    assert(revert3  => lastReverted, "Amount error did not revert");
    assert(revert4  => lastReverted, "No vest total ammount did not revert");
    assert(revert5  => lastReverted, "Starting timestamp too far did not revert");
    assert(revert6  => lastReverted, "Starting timestamp too long ago did not revert");
    assert(revert7  => lastReverted, "Tau zero did not revert");
    assert(revert8  => lastReverted, "Rate too high did not revert");
    assert(revert9  => lastReverted, "Tau too long did not revert");
    assert(revert10 => lastReverted, "Cliff too long did not revert");
    assert(revert11 => lastReverted, "Ids overflow did not revert");
    assert(revert12 => lastReverted, "Starting timestamp toUint48 cast did not revert");
    assert(revert13 => lastReverted, "Cliff toUint48 cast overflow did not revert");
    assert(revert14 => lastReverted, "Fin toUint48 cast overflow did not revert");
    assert(revert15 => lastReverted, "Tot toUint128 cast overflow did not revert");
    assert(revert16 => lastReverted, "Sending ETH did not revert");
    assert(revert17 => lastReverted, "Addition overflow did not revert");
    assert(revert18 => lastReverted, "Subtraction underflow did not revert");
    assert(revert19 => lastReverted, "Addition overflow did not revert");
    assert(revert20 => lastReverted, "Addition overflow did not revert");

    assert(lastReverted =>
            revert1  || revert2  || revert3  ||
            revert4  || revert5  || revert6  ||
            revert7  || revert8  || revert9  ||
            revert10 || revert11 || revert12 ||
            revert13 || revert14 || revert15 ||
            revert16 || revert17 || revert18 ||
            revert19 || revert20, "Revert rules are not covering all the cases");
}
