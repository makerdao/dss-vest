// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.6.12;

import "../src/DssVest.sol";
import "./DSToken.sol";

contract DssVestMintableEchidnaTest {

    DssVestMintable internal mVest;
    DSToken internal gem;

    uint256 internal constant WAD = 10**18;
    uint256 internal immutable salt; // initialTimestamp

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

    function rxdLessOrEqualTot(uint256 id) public {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        assert(mVest.rxd(id) <= mVest.tot(id));
    }

    function clfGreaterOrEqualBgn(uint256 id) public {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        assert(mVest.clf(id) >= mVest.bgn(id));
    }

    function finGreaterOrEqualClf(uint256 id) public {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        assert(mVest.fin(id) >= mVest.clf(id));
    }

    function create(uint256 tot, uint256 bgn, uint256 tau, uint256 eta) public {
        tot = tot % uint128(-1);
        if (tot < WAD) tot = (1 + tot) * WAD;
        bgn = sub(salt, mVest.TWENTY_YEARS() / 2) + bgn % mVest.TWENTY_YEARS();
        tau = 1 + tau % mVest.TWENTY_YEARS();
        eta = eta % tau;
        if (tot / tau > mVest.cap()) {
            tot = 500 * WAD;
            tau = 365 days;
        }
        uint256 prevId = mVest.ids();
        uint256 id = mVest.create(address(this), tot, bgn, tau, eta, address(0));
        assert(mVest.ids() == add(prevId, 1));
        assert(mVest.ids() == id);
        assert(mVest.valid(id));
        assert(mVest.usr(id) == address(this));
        assert(mVest.bgn(id) == toUint48(bgn));
        assert(mVest.clf(id) == toUint48(add(bgn, eta)));
        assert(mVest.fin(id) == toUint48(add(bgn, tau)));
        assert(mVest.tot(id) == toUint128(tot));
        assert(mVest.rxd(id) == 0);
        assert(mVest.mgr(id) == address(0));
        assert(mVest.res(id) == 0);
    }

    function create_revert(address usr, uint256 tot, uint256 bgn, uint256 tau, uint256 eta, address mgr) public {
        try mVest.create(address(0), tot, bgn, tau, eta, mgr) returns (uint256 id) {
            assert(false); // invalid-user
        } catch {}
        tot = tot / tau > mVest.cap() ? tot : 0;
        try mVest.create(usr, tot, bgn, tau, eta, mgr) returns (uint256 id) {
            assert(false); // rate-too-high or no-vest-total-amount
        } catch {}
        bgn = bgn >= add(block.timestamp, mVest.TWENTY_YEARS()) || bgn <= sub(block.timestamp, mVest.TWENTY_YEARS()) ? bgn : 0;
        try mVest.create(usr, tot, bgn, tau, eta, mgr) returns (uint256 id) {
            assert(false); // bgn-too-far or bgn-too-long-ago
        } catch {}
        tau = tot / tau > mVest.cap() ? tau : 0;
        try mVest.create(usr, tot, bgn, tau, eta, mgr) returns (uint256 id) {
            assert(false); // rate-too-high or tau-zero
        } catch {}
        eta = eta > tau ? eta : ++tau;
        try mVest.create(usr, tot, bgn, tau, eta, mgr) returns (uint256 id) {
            assert(false); // eta-too-long
        } catch {}
    }

    function vest(uint256 id) public {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = mVest.awards(id);
        uint256 unpaidAmt = unpaid(block.timestamp, bgn, clf, fin, tot, rxd);
        uint256 supplyBefore = gem.totalSupply();
        uint256 usrBalanceBefore = gem.balanceOf(usr);
        mVest.vest(id);
        if (block.timestamp < clf) {
            assert(mVest.rxd(id) == rxd);
            assert(gem.totalSupply() == supplyBefore);
            assert(gem.balanceOf(usr) == usrBalanceBefore);
        }
        else {
            if (block.timestamp >= fin) {
                assert(mVest.rxd(id) == tot);
            }
            else {
                assert(mVest.rxd(id) == toUint128(add(rxd, unpaidAmt)));
            }
            assert(gem.totalSupply() == add(supplyBefore, unpaidAmt));
            assert(gem.balanceOf(usr) == add(usrBalanceBefore, unpaidAmt));
        }
    }

    function vest_amt(uint256 id, uint256 maxAmt) public {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
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
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        mVest.restrict(id);
        assert(mVest.res(id) == 1);
    }

    function unrestrict(uint256 id) public {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        mVest.unrestrict(id);
        assert(mVest.res(id) == 0);
    }

    function yank(uint256 id, uint256 end) public {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
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
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        address dst = mVest.usr(id) == address(this) ? msg.sender : address(0);
        mVest.move(id, dst);
        assert(mVest.usr(id) == dst);
    }
}
