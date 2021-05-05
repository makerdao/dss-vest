// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.6.12;

import "../DssVest.sol";

contract DssVestEchidnaTest {

    DssVest internal vest;
    IMKR internal MKR;

    constructor() public {
      vest = new DssVest(address(MKR));
    }

    // --- Math ---

    uint256 internal constant WAD = 10**18;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function test_init_ids(uint256 _amt, uint256 _bgn, uint256 _tau, uint256 _clf, uint256 _pmt, address _mgr) public {
        _amt = 1 * WAD + _amt % uint128(-1);
        _bgn = block.timestamp + _bgn % vest.MAX_VEST_PERIOD();
        _tau = 1 + _tau % vest.MAX_VEST_PERIOD();
        _clf = 0 + _clf % _tau;
        _pmt = 1 * WAD + _pmt % _amt;
        uint256 prevId = vest.ids();
        uint256 id = vest.init(address(this), _amt, _bgn, _tau, _clf, _pmt, _mgr);
        assert(vest.ids() == add(prevId, id));
        assert(vest.valid(id));
    }

    function test_init_params(uint256 _amt, uint256 _bgn, uint256 _tau, uint256 _clf, uint256 _pmt, address _mgr) public {
        _amt = 1 * WAD + _amt % uint128(-1);
        _bgn = block.timestamp + _bgn % vest.MAX_VEST_PERIOD();
        _tau = 1 + _tau % vest.MAX_VEST_PERIOD();
        _clf = 0 + _clf % _tau;
        _pmt = 1 * WAD + _pmt % _amt;
        uint256 id = vest.init(address(this), _amt, _bgn, _tau, _clf, _pmt, _mgr);
        (address usr, uint48 bgn, uint48 clf, uint48 fin, uint128 amt, uint128 rxd, address mgr) = vest.awards(id);
        if (sub(_amt, _pmt) != 0) {
            assert(usr == (address(this)));
            assert(bgn == uint48(_bgn));
            assert(clf == add(_bgn, _clf));
            assert(fin == add(_bgn, _tau));
            assert(amt == sub(_amt, _pmt));
            assert(rxd == uint128(0));
            assert(mgr == _mgr);
        }
    }

    function test_vest(uint256 _amt, uint256 _bgn, uint256 _tau, uint256 _clf, uint256 _pmt, address _mgr, uint256 _tick) public {
        _amt = 1 * WAD + _amt % uint128(-1);
        _bgn = block.timestamp + _bgn % vest.MAX_VEST_PERIOD();
        _tau = 1 + _tau % vest.MAX_VEST_PERIOD();
        _clf = 0 + _clf % _tau;
        _pmt = 1 * WAD + _pmt % _amt;
        _tick = block.timestamp + _tick % uint128(-1);
        uint256 id = vest.init(address(this), _amt, _bgn, _tau, _clf, _pmt, _mgr);
        assert(vest.valid(id));
        uint256 ids = vest.ids();
        vest.vest(id);
        (address usr, uint48 bgn, uint48 clf, uint48 fin, uint128 amt, uint128 rxd, address mgr) = vest.awards(id);
        if (_tick < fin) {
          assert (vest.ids() == sub(ids, 1));
        } else if (_tick >= clf) {
          uint256 t = (_tick - bgn) * WAD / (fin - bgn);
          assert(t >= 0);
          assert(t < WAD);
          uint256 mkr = (amt * t) / WAD;
          assert(mkr >= 0);
          assert(mkr < amt);
          assert(rxd == uint128(mkr));
        }
    }
}
