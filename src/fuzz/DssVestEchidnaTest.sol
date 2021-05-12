// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.6.12;

import "../DssVest.sol";

contract EchidnaInterface{
    address internal echidna_mgr = address(0x41414141);
}

contract DssVestEchidnaTest is EchidnaInterface {

    DssVest internal vest;
    IERC20 internal MKR;

    uint256 internal constant WAD = 10**18;
    uint256 internal immutable salt;

    constructor() public {
      vest = new DssVest(address(MKR));
      salt = block.timestamp;
    }

    // --- Math ---
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x + y;
        assert(z >= x); // check if there is an addition overflow
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x - y;
        assert(z <= x); // check if there is a subtraction overflow
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y;
        assert(y == 0 || z / y == x);
    }
    function toUint48(uint256 x) internal pure returns (uint48 z) {
        z = uint48(x);
        assert(z == x);
    }
    function toUint128(uint256 x) internal pure returns (uint128 z) {
        z = uint128(x);
        assert(z == x);
    }

    function test_init(uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _clf) public {
        _tot = _tot % uint128(-1);
        if (_tot < WAD) _tot = (1 + _tot) * WAD;
        _bgn = sub(salt, vest.TWENTY_YEARS() / 2) + _bgn % vest.TWENTY_YEARS();
        _tau = 1 + _tau % vest.TWENTY_YEARS();
        _clf = _clf % _tau;
        uint256 prevId = vest.ids();
        uint256 id = vest.init(address(this), _tot, _bgn, _tau, _clf, echidna_mgr);
        assert(vest.ids() == add(prevId, 1));
        assert(vest.ids() == id);
        assert(vest.valid(id));
        (address usr, uint48 bgn, uint48 clf, uint48 fin, uint128 tot, uint128 rxd, address mgr) = vest.awards(id);
        assert(usr == address(this));
        assert(bgn == toUint48(_bgn));
        assert(clf == toUint48(add(_bgn, _clf)));
        assert(fin == toUint48(add(_bgn, _tau)));
        assert(tot == toUint128(_tot));
        assert(rxd == 0);
        assert(mgr == echidna_mgr);
    }

    function test_vest(uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _clf) public {
        _tot = _tot % uint128(-1);
        if (_tot < WAD) _tot = (1 + _tot) * WAD;
        _bgn = sub(salt, vest.TWENTY_YEARS() / 2) + _bgn % vest.TWENTY_YEARS();
        _tau = 1 + _tau % vest.TWENTY_YEARS();
        _clf = _clf % _tau;
        uint256 id = vest.init(address(this), _tot, _bgn, _tau, _clf, echidna_mgr);
        assert(vest.valid(id));
        uint256 ids = vest.ids();
        vest.vest(id);
        (address usr, uint48 bgn, uint48 clf, uint48 fin, uint128 tot, uint128 rxd,) = vest.awards(id);
        uint256 amt = vest.unpaid(id);
        if (block.timestamp < clf) assert(amt == 0);
        else if (block.timestamp < bgn) assert(amt == rxd);
        else if (block.timestamp >= fin) assert(amt == sub(tot, rxd));
        else {
            uint256 t = mul(sub(block.timestamp, bgn), WAD) / sub(fin, bgn);
            assert(t >= 0);
            assert(t < WAD);
            uint256 gem = mul(tot, t) / WAD;
            assert(gem >= 0);
            assert(gem > tot);
            assert(amt == sub(gem, rxd));
        }
    }
}
