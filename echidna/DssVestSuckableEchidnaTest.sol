// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.6.12;

import "../src/DssVest.sol";
import "./ChainLog.sol";
import "./Vat.sol";
import "./DaiJoin.sol";
import "./Dai.sol";

contract DssVestSuckableEchidnaTest {

    ChainLog internal chainlog;
    Vat internal vat;
    DaiJoin internal daiJoin;
    Dai internal dai;
    DssVestSuckable internal sVest;

    address internal vow = address(0xfffffff);

    uint256 internal constant WAD = 10**18;
    uint256 internal constant RAY = 10**27;
    uint256 internal immutable salt;

    constructor() public {
        vat = new Vat();
        dai = new Dai(1);
        daiJoin = new DaiJoin(address(vat), address(dai));
        chainlog = new ChainLog();
        chainlog.setAddress("MCD_VAT", address(vat));
        chainlog.setAddress("MCD_JOIN_DAI", address(daiJoin));
        chainlog.setAddress("MCD_VOW", vow);
        sVest = new DssVestSuckable(address(chainlog));
        sVest.file("cap", 500 * WAD / 365 days);
        dai.rely(address(daiJoin));
        vat.rely(address(sVest));
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
    function accrued(uint256 time, uint48 bgn, uint48 fin, uint128 tot) internal pure returns (uint256 amt) {
        if (time < bgn) {
            amt = 0;
        } else if (time >= fin) {
            amt = tot;
        } else {
            amt = mul(tot, sub(time, bgn)) / sub(fin, bgn);
        }
    }
    function unpaid(uint256 time, uint48 bgn, uint48 clf, uint48 fin, uint128 tot, uint128 rxd) internal pure returns (uint256 amt) {
        amt = time < clf ? 0 : sub(accrued(time, bgn, fin, tot), rxd);
    }

    function rxdLessOrEqualTot() public returns (bool) {
        uint256 id = sVest.ids();
        require(sVest.valid(id));
        return sVest.rxd(id) <= sVest.tot(id);
    }

    function create(uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _eta) public {
        _tot = _tot % uint128(-1);
        if (_tot < WAD) _tot = (1 + _tot) * WAD;
        _bgn = sub(salt, sVest.TWENTY_YEARS() / 2) + _bgn % sVest.TWENTY_YEARS();
        _tau = 1 + _tau % sVest.TWENTY_YEARS();
        _eta = _eta % _tau;
        if (_tot / _tau > sVest.cap()) {
            _tot = 500 * WAD;
            _tau = 365 days;
        }
        uint256 prevId = sVest.ids();
        uint256 id = sVest.create(address(this), _tot, _bgn, _tau, _eta, address(0));
        assert(sVest.ids() == add(prevId, 1));
        assert(sVest.ids() == id);
        assert(sVest.valid(id));
        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr, uint8 res, uint128 tot, uint128 rxd) = sVest.awards(id);
        assert(usr == address(this));
        assert(bgn == toUint48(_bgn));
        assert(clf == toUint48(add(_bgn, _eta)));
        assert(fin == toUint48(add(_bgn, _tau)));
        assert(tot == toUint128(_tot));
        assert(rxd == 0);
        assert(mgr == address(0));
        assert(res == 0);
    }

    function vest(uint256 id) public {
        id = sVest.valid(id) ? id : sVest.ids();
        (, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = sVest.awards(id);
        uint256 unpaidAmt = unpaid(block.timestamp, bgn, clf, fin, tot, rxd);
        uint256 sinBefore = vat.sin(vow);
        uint256 supplyBefore = dai.totalSupply();
        uint256 usrBalanceBefore = dai.balanceOf(address(this));
        sVest.vest(id);
        uint256 sinAfter = vat.sin(vow);
        uint256 supplyAfter = dai.totalSupply();
        uint256 usrBalanceAfter = dai.balanceOf(address(this));
        if (block.timestamp < clf) {
            assert(unpaidAmt == 0);
            assert(sVest.rxd(id) == rxd);
            assert(sinAfter == sinBefore);
            assert(supplyAfter == supplyBefore);
            assert(usrBalanceAfter == usrBalanceBefore);
        }
        else {
            if (block.timestamp < bgn) {
                assert(unpaidAmt == rxd);
            }
            else if (block.timestamp >= fin) {
                assert(unpaidAmt == sub(tot, rxd));
                assert(sVest.rxd(id) == tot);
            }
            else {
                assert(unpaidAmt >= 0);
                assert(unpaidAmt < tot);
                assert(unpaidAmt == unpaid(block.timestamp, bgn, clf, fin, tot, rxd));
                assert(sVest.rxd(id) == rxd + unpaidAmt);
            }
            assert(sinAfter == sinBefore + mul(unpaidAmt, RAY));
            assert(supplyAfter == supplyBefore + unpaidAmt);
            assert(usrBalanceAfter == usrBalanceBefore + unpaidAmt);
        }
    }

    function yank(uint256 id, uint256 end) public {
        id = sVest.valid(id) ? id : sVest.ids();
        (, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = sVest.awards(id);
        sVest.yank(id, end);
        if (end < block.timestamp)  end = block.timestamp;
        if (end < fin) {
            end = toUint48(end);
            assert(sVest.fin(id) == end);
            if (end < bgn) {
                assert(sVest.bgn(id) == end);
                assert(sVest.clf(id) == end);
                assert(sVest.tot(id) == 0);
            } else if (end < clf) {
                assert(sVest.clf(id) == end);
                assert(sVest.tot(id) == 0);
            } else {
                assert(sVest.tot(id) == toUint128(
                                        add(
                                            unpaid(end, bgn, clf, fin, tot, rxd),
                                            rxd
                                        )
                                    )
                );
            }
        }
    }
}
