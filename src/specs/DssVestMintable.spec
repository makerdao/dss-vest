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

    uint256 prevId = ids(e);

    uint256 id = init(e, _usr, _tot, _bgn, _tau, _clf, _mgr);

    //(address usr, uint48 bgn, uint48 clf, uint48 fin, uint128 tot, uint128 rxd, address mgr) = awards(e, id);

    assert(ids(e) == prevId + 1, "Init did not increase the Ids as expected");
    assert(ids(e) == id, "Init did not return the Id as expected");
    assert(valid(e, id), "Init did not return a valid Id");
    //assert(usr == _usr, "Init did not set usr as expected");

}

// Verify revert rules on init
rule init_revert(address _usr, uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _clf, address _mgr) {
    env e;

    uint256 ward = wards(e, e.msg.sender);


    init@withrevert(e, _usr, _tot, _bgn, _tau, _clf, _mgr);

    bool revert1  = ward != 1;
    bool revert2  = _usr == 0;
    bool revert3  = _tot == max_uint128;
    bool revert4  = _tot == 0;
    bool revert5  = _bgn >= e.block.timestamp + TWENTY_YEARS(e);
    bool revert6  = _bgn <= e.block.timestamp - TWENTY_YEARS(e);
    bool revert7  = _tau == 0;
    bool revert8  = _tot / _tau > cap(e);
    bool revert9  = _tau > TWENTY_YEARS(e);
    bool revert10 = _clf > _tau;
    bool revert11 = ids(e) == max_uint;

    assert(revert1  => lastReverted, "Lack of auth did not revert");
    assert(revert2  => lastReverted, "Amount error did not revert");
    assert(revert3  => lastReverted, "No vest total ammount did not revert");
    assert(revert4  => lastReverted, "Starting timestamp too far did not revert");
    assert(revert5  => lastReverted, "Starting timestamp too long ago did not revert");
    assert(revert6  => lastReverted, "a");
    assert(revert7  => lastReverted, "b");
    assert(revert6  => lastReverted, "c");
    assert(revert7  => lastReverted, "d");
    assert(revert8  => lastReverted, "e");
    assert(revert9  => lastReverted, "f");
    assert(revert10 => lastReverted, "g");
    assert(revert11 => lastReverted, "h");
    //assert(revert12 => lastReverted, "i");
    assert(lastReverted => revert1  ||
                           revert2  ||
                           revert3  ||
                           revert4  ||
                           revert5  ||
                           revert6  ||
                           revert7  ||
                           revert8  ||
                           revert9  ||
                           revert10 ||
                           revert11, "Revert rules are not covering all the cases");
}
