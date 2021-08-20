// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.6.12;

import "../src/DssVest.sol";
import "./DSToken.sol";

contract DssVestMintableEchidnaTest {

    DssVestMintable internal mVest;
    DSToken internal gem;

    uint256 internal constant WAD = 10**18;
    uint256 internal immutable salt;

    constructor() public {
        gem = new DSToken("MKR");
        mVest = new DssVestMintable(address(gem));
        mVest.file("cap", 500 * WAD / 365 days);
        gem.setOwner(address(mVest));
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
        uint256 id = mVest.ids();
        require(mVest.valid(id));
        return mVest.rxd(id) <= mVest.tot(id);
    }

    function create(uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _eta) public {
        _tot = _tot % uint128(-1);
        if (_tot < WAD) _tot = (1 + _tot) * WAD;
        _bgn = sub(salt, mVest.TWENTY_YEARS() / 2) + _bgn % mVest.TWENTY_YEARS();
        _tau = 1 + _tau % mVest.TWENTY_YEARS();
        _eta = _eta % _tau;
        if (_tot / _tau > mVest.cap()) {
            _tot = 500 * WAD;
            _tau = 365 days;
        }
        uint256 prevId = mVest.ids();
        uint256 id = mVest.create(address(this), _tot, _bgn, _tau, _eta, address(0));
        assert(mVest.ids() == add(prevId, 1));
        assert(mVest.ids() == id);
        assert(mVest.valid(id));
        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr, uint8 res, uint128 tot, uint128 rxd) = mVest.awards(id);
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
        id = mVest.valid(id) ? id : mVest.ids();
        (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = mVest.awards(id);
        uint256 unpaidAmt = unpaid(block.timestamp, bgn, clf, fin, tot, rxd);
        uint256 supplyBefore = gem.totalSupply();
        uint256 usrBalanceBefore = gem.balanceOf(usr);
        mVest.vest(id);
        if (block.timestamp < clf) {
            assert(unpaidAmt == 0);
            assert(mVest.rxd(id) == rxd);
            assert(gem.totalSupply() == supplyBefore);
            assert(gem.balanceOf(usr) == usrBalanceBefore);
        }
        else {
            if (block.timestamp < bgn) {
                assert(unpaidAmt == rxd);
            }
            else if (block.timestamp >= fin) {
                assert(unpaidAmt == sub(tot, rxd));
                assert(mVest.rxd(id) == tot);
            }
            else {
                assert(unpaidAmt >= 0);
                assert(unpaidAmt < tot);
                assert(unpaidAmt == unpaid(block.timestamp, bgn, clf, fin, tot, rxd));
                assert(mVest.rxd(id) == toUint128(add(rxd, unpaidAmt)));
            }
            assert(gem.totalSupply() == add(supplyBefore, unpaidAmt));
            assert(gem.balanceOf(usr) == add(usrBalanceBefore, unpaidAmt));
        }
    }

    function vest_amt(uint256 id, uint256 maxAmt) public {
        id = mVest.valid(id) ? id : mVest.ids();
        (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = mVest.awards(id);
        uint256 unpaidAmt = unpaid(block.timestamp, bgn, clf, fin, tot, rxd);
        uint256 amt = maxAmt > unpaidAmt ? unpaidAmt : maxAmt;
        uint256 supplyBefore = gem.totalSupply();
        uint256 usrBalanceBefore = gem.balanceOf(usr);
        mVest.vest(id, maxAmt);
        if (block.timestamp < clf) {
            assert(mVest.rxd(id) == rxd);
            assert(gem.totalSupply() == supplyBefore);
            assert(gem.balanceOf(usr) == usrBalanceBefore);
        }
        else {
            assert(mVest.rxd(id) == toUint128(add(rxd, amt)));
            assert(gem.totalSupply() == add(supplyBefore, amt));
            assert(gem.balanceOf(usr) == add(usrBalanceBefore, amt));
        }
    }

    function restrict(uint256 id) public {
        id = mVest.valid(id) ? id : mVest.ids();
        mVest.restrict(id);
        assert(mVest.res(id) == 1);
    }

    function unrestrict(uint256 id) public {
        id = mVest.valid(id) ? id : mVest.ids();
        mVest.unrestrict(id);
        assert(mVest.res(id) == 0);
    }

    function yank(uint256 id, uint256 end) public {
        id = mVest.valid(id) ? id : mVest.ids();
        (, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = mVest.awards(id);
        mVest.yank(id, end);
        if (end < block.timestamp)  end = block.timestamp;
        if (end < fin) {
            end = toUint48(end);
            assert(mVest.fin(id) == end);
            if (end < bgn) {
                assert(mVest.bgn(id) == end);
                assert(mVest.clf(id) == end);
                assert(mVest.tot(id) == 0);
            } else if (end < clf) {
                assert(mVest.clf(id) == end);
                assert(mVest.tot(id) == 0);
            } else {
                assert(mVest.tot(id) == toUint128(
                                        add(
                                            unpaid(end, bgn, clf, fin, tot, rxd),
                                            rxd
                                        )
                                    )
                );
            }
        }
    }

    function move(uint id) public {
        id = mVest.valid(id) ? id : mVest.ids();
        address dst = mVest.usr(id) == address(this) ? msg.sender : address(0);
        mVest.move(id, dst);
        assert(mVest.usr(id) == dst);
    }
}
