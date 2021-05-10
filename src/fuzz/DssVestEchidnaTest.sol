// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.6.12;

import "../DssVest.sol";

contract EchidnaInterface{
    address internal echidna_mgr = address(0x41414141);
}

contract DssVestEchidnaTest is EchidnaInterface {

    DssVest internal vest;
    IMKR internal MKR;

    uint256 internal constant WAD = 10**18;
    uint256 internal immutable salt;

    constructor() public {
      vest = new DssVest(address(MKR));
      salt = block.timestamp;
    }

    // --- Math ---
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x + y;
        assert (z >= x); // check if there is an addition overflow
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x - y;
        assert (z <= x); // check if there is a subtraction overflow
    }

    function test_init(uint256 _amt, uint256 _bgn, uint256 _tau, uint256 _clf) public {
        _amt = _amt % uint128(-1);
        if (_amt < WAD) _amt = (1 + _amt) * WAD;
        _bgn = salt + _bgn % vest.MAX_VEST_PERIOD();
        _tau = 1 + _tau % vest.MAX_VEST_PERIOD();
        _clf = _clf % _tau;
        uint256 prevId = vest.ids();
        uint256 id = vest.init(address(this), _amt, _bgn, _tau, _clf, echidna_mgr);
        assert(vest.ids() == add(prevId, 1));
        assert(vest.ids() == id);
        assert(vest.valid(id));
        (address usr, uint48 bgn, uint48 clf, uint48 fin, uint128 amt, uint128 rxd, address mgr) = vest.awards(id);
        assert(usr == address(this));
        assert(bgn == uint48(_bgn));
        assert(clf == uint48(_bgn + _clf));
        assert(fin == uint48(_bgn + _tau));
        assert(amt == uint128(_amt));
        assert(rxd == 0);
        assert(mgr == echidna_mgr);
    }

    function test_vest(uint256 _amt, uint256 _bgn, uint256 _tau, uint256 _clf) public {
        _amt = _amt % uint128(-1);
        if (_amt < WAD) _amt = (1 + _amt) * WAD;
        _bgn = salt + _bgn % vest.MAX_VEST_PERIOD();
        _tau = 1 + _tau % vest.MAX_VEST_PERIOD();
        _clf = _clf % _tau;
        uint256 id = vest.init(address(this), _amt, _bgn, _tau, _clf, echidna_mgr);
        assert(vest.valid(id));
        uint256 ids = vest.ids();
        vest.vest(id);
        (address usr, uint48 bgn, uint48 clf, uint48 fin, uint128 amt, uint128 rxd,) = vest.awards(id);
        if (block.timestamp >= fin) {
          assert (vest.ids() == sub(ids, 1));
        } else if (block.timestamp >= clf) {
          uint256 t = (block.timestamp - bgn) * WAD / (fin - bgn);
          assert(t >= 0);
          assert(t < WAD);
          uint256 mkr = (amt * t) / WAD;
          assert(mkr >= 0);
          assert(mkr < amt);
          assert(rxd == uint128(mkr));
        }
    }
}
