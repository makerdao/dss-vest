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
    uint256 internal immutable salt; // initialTimestamp

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
    function cmpStr(string memory a, string memory b) internal view returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function rxdLessOrEqualTot(uint256 id) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
        assert(sVest.rxd(id) <= sVest.tot(id));
    }

    function clfGreaterOrEqualBgn(uint256 id) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
        assert(sVest.clf(id) >= sVest.bgn(id));
    }

    function finGreaterOrEqualClf(uint256 id) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
        assert(sVest.fin(id) >= sVest.clf(id));
    }

    function create(uint256 tot, uint256 bgn, uint256 tau, uint256 eta) public {
        tot = tot % uint128(-1);
        if (tot < WAD) tot = (1 + tot) * WAD;
        bgn = sub(salt, sVest.TWENTY_YEARS() / 2) + bgn % sVest.TWENTY_YEARS();
        tau = 1 + tau % sVest.TWENTY_YEARS();
        eta = eta % tau;
        if (tot / tau > sVest.cap()) {
            tot = 500 * WAD;
            tau = 365 days;
        }
        uint256 prevId = sVest.ids();
        uint256 id = sVest.create(address(this), tot, bgn, tau, eta, address(0));
        assert(sVest.ids() == add(prevId, 1));
        assert(sVest.ids() == id);
        assert(sVest.valid(id));
        assert(sVest.usr(id) == address(this));
        assert(sVest.bgn(id) == toUint48(bgn));
        assert(sVest.clf(id) == toUint48(add(bgn, eta)));
        assert(sVest.fin(id) == toUint48(add(bgn, tau)));
        assert(sVest.tot(id) == toUint128(tot));
        assert(sVest.rxd(id) == 0);
        assert(sVest.mgr(id) == address(0));
        assert(sVest.res(id) == 0);
    }

     function create_revert(address usr, uint256 tot, uint256 bgn, uint256 tau, uint256 eta, address mgr) public {
        try sVest.create(usr, tot, bgn, tau, eta, mgr) returns (uint256 id) {
        } catch Error(string memory errmsg) {
            assert(
                usr == address(0)                                 && cmpStr(errmsg, "DssVest/invalid-user")         ||
                tot == 0                                          && cmpStr(errmsg, "DssVest/no-vest-total-amount") ||
                bgn >= add(block.timestamp, sVest.TWENTY_YEARS()) && cmpStr(errmsg, "DssVest/bgn-too-far")          ||
                bgn <= sub(block.timestamp, sVest.TWENTY_YEARS()) && cmpStr(errmsg, "DssVest/bgn-too-long-ago")     ||
                tau == 0                                          && cmpStr(errmsg, "DssVest/tau-zero")             ||
                tot /  tau > sVest.cap()                          && cmpStr(errmsg, "DssVest/rate-too-high")        ||
                tau >  sVest.TWENTY_YEARS()                       && cmpStr(errmsg, "DssVest/tau-too-long")         ||
                eta >  tau                                        && cmpStr(errmsg, "DssVest/eta-too-long")         ||
                sVest.ids() == type(uint256).max                  && cmpStr(errmsg, "DssVest/DssVest/ids-overflow")
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function vest(uint256 id) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
        (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = sVest.awards(id);
        uint256 unpaidAmt = unpaid(block.timestamp, bgn, clf, fin, tot, rxd);
        uint256 sinBefore = vat.sin(vow);
        uint256 supplyBefore = dai.totalSupply();
        uint256 usrBalanceBefore = dai.balanceOf(usr);
        sVest.vest(id);
        if (block.timestamp < clf) {
            assert(sVest.rxd(id) == rxd);
            assert(vat.sin(vow) == sinBefore);
            assert(dai.totalSupply() == supplyBefore);
            assert(dai.balanceOf(usr) == usrBalanceBefore);
        }
        else {
            if (block.timestamp >= fin) {
                assert(sVest.rxd(id) == tot);
            }
            else {
                assert(sVest.rxd(id) == toUint128(add(rxd, unpaidAmt)));
            }
            assert(vat.sin(vow) == add(sinBefore, mul(unpaidAmt, RAY)));
            assert(dai.totalSupply() == add(supplyBefore, unpaidAmt));
            assert(dai.balanceOf(usr) == add(usrBalanceBefore, unpaidAmt));
        }
    }

    function vest_amt(uint256 id, uint256 maxAmt) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
        (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = sVest.awards(id);
        uint256 unpaidAmt = unpaid(block.timestamp, bgn, clf, fin, tot, rxd);
        uint256 amt = maxAmt > unpaidAmt ? unpaidAmt : maxAmt;
        uint256 sinBefore = vat.sin(vow);
        uint256 supplyBefore = dai.totalSupply();
        uint256 usrBalanceBefore = dai.balanceOf(usr);
        sVest.vest(id, maxAmt);
        if (block.timestamp < clf) {
            assert(sVest.rxd(id) == rxd);
            assert(vat.sin(vow) == sinBefore);
            assert(dai.totalSupply() == supplyBefore);
            assert(dai.balanceOf(usr) == usrBalanceBefore);
        }
        else {
            assert(sVest.rxd(id) == toUint128(add(rxd, amt)));
            assert(vat.sin(vow) == add(sinBefore, mul(amt, RAY)));
            assert(dai.totalSupply() == add(supplyBefore, amt));
            assert(dai.balanceOf(usr) == add(usrBalanceBefore, amt));
        }
    }

    function restrict(uint256 id) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
        sVest.restrict(id);
        assert(sVest.res(id) == 1);
    }

    function unrestrict(uint256 id) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
        sVest.unrestrict(id);
        assert(sVest.res(id) == 0);
    }

    function yank(uint256 id, uint256 end) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
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

    function move(uint id) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
        address dst = sVest.usr(id) == address(this) ? msg.sender : address(0);
        sVest.move(id, dst);
        assert(sVest.usr(id) == dst);
    }
}
