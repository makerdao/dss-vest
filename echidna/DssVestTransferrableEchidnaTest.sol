// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.6.12;

import "../src/DssVest.sol";
import "./Dai.sol";

/// @dev A contract that will receive Dai, and allows for it to be retrieved.
contract Multisig {

    function approve(address dai, address vest) external {
        Dai(dai).approve(vest, uint256(-1));
    }
}

contract DssVestTransferrableEchidnaTest {

    DssVestTransferrable internal tVest;
    Dai internal gem;
    Multisig internal multisig;

    uint256 internal constant WAD = 10**18;
    uint256 internal immutable salt; // initialTimestamp

    constructor() public {
        gem = new Dai(1);
        multisig = new Multisig();
        gem.mint(address(multisig), uint128(-1));
        tVest = new DssVestTransferrable(address(multisig), address(gem));
        tVest.file("cap", 500 * WAD / 365 days);
        multisig.approve(address(gem), address(tVest));
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
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        assert(tVest.rxd(id) <= tVest.tot(id));
    }

    function clfGreaterOrEqualBgn(uint256 id) public {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        assert(tVest.clf(id) >= tVest.bgn(id));
    }

    function finGreaterOrEqualClf(uint256 id) public {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        assert(tVest.fin(id) >= tVest.clf(id));
    }

    function create(uint256 tot, uint256 bgn, uint256 tau, uint256 eta) public {
        tot = tot % uint128(-1);
        if (tot < WAD) tot = (1 + tot) * WAD;
        bgn = sub(salt, tVest.TWENTY_YEARS() / 2) + bgn % tVest.TWENTY_YEARS();
        tau = 1 + tau % tVest.TWENTY_YEARS();
        eta = eta % tau;
        if (tot / tau > tVest.cap()) {
            tot = 500 * WAD;
            tau = 365 days;
        }
        uint256 prevId = tVest.ids();
        uint256 id = tVest.create(address(this), tot, bgn, tau, eta, address(0));
        assert(tVest.ids() == add(prevId, 1));
        assert(tVest.ids() == id);
        assert(tVest.valid(id));
        assert(tVest.usr(id) == address(this));
        assert(tVest.bgn(id) == toUint48(bgn));
        assert(tVest.clf(id) == toUint48(add(bgn, eta)));
        assert(tVest.fin(id) == toUint48(add(bgn, tau)));
        assert(tVest.tot(id) == toUint128(tot));
        assert(tVest.rxd(id) == 0);
        assert(tVest.mgr(id) == address(0));
        assert(tVest.res(id) == 0);
    }

    function create_revert(address usr, uint256 tot, uint256 bgn, uint256 tau, uint256 eta, address mgr) public {
        try tVest.create(usr, tot, bgn, tau, eta, mgr) {
        } catch Error(string memory errmsg) {
            assert(
                usr == address(0)                                 && cmpStr(errmsg, "DssVest/invalid-user")         ||
                tot == 0                                          && cmpStr(errmsg, "DssVest/no-vest-total-amount") ||
                bgn >= add(block.timestamp, tVest.TWENTY_YEARS()) && cmpStr(errmsg, "DssVest/bgn-too-far")          ||
                bgn <= sub(block.timestamp, tVest.TWENTY_YEARS()) && cmpStr(errmsg, "DssVest/bgn-too-long-ago")     ||
                tau == 0                                          && cmpStr(errmsg, "DssVest/tau-zero")             ||
                tot /  tau > tVest.cap()                          && cmpStr(errmsg, "DssVest/rate-too-high")        ||
                tau >  tVest.TWENTY_YEARS()                       && cmpStr(errmsg, "DssVest/tau-too-long")         ||
                eta >  tau                                        && cmpStr(errmsg, "DssVest/eta-too-long")         ||
                tVest.ids() == type(uint256).max                  && cmpStr(errmsg, "DssVest/DssVest/ids-overflow")
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function vest(uint256 id) public {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = tVest.awards(id);
        uint256 unpaidAmt = unpaid(block.timestamp, bgn, clf, fin, tot, rxd);
        uint256 msigBalanceBefore = gem.balanceOf(address(multisig));
        uint256 usrBalanceBefore = gem.balanceOf(usr);
        uint256 supplyBefore = gem.totalSupply();
        tVest.vest(id);
        if (block.timestamp < clf) {
            assert(tVest.rxd(id) == rxd);
            assert(gem.balanceOf(address(multisig)) == msigBalanceBefore);
            assert(gem.balanceOf(usr) == usrBalanceBefore);
        }
        else {
            if (block.timestamp >= fin) {
                assert(tVest.rxd(id) == tot);
            }
            else {
                assert(tVest.rxd(id) == toUint128(add(rxd, unpaidAmt)));
            }
            assert(gem.balanceOf(address(multisig)) == sub(msigBalanceBefore, unpaidAmt));
            assert(gem.balanceOf(usr) == add(usrBalanceBefore, unpaidAmt));
        }
        assert(gem.totalSupply() == supplyBefore);
    }

    function vest_amt(uint256 id, uint256 maxAmt) public {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = tVest.awards(id);
        uint256 unpaidAmt = unpaid(block.timestamp, bgn, clf, fin, tot, rxd);
        uint256 amt = maxAmt > unpaidAmt ? unpaidAmt : maxAmt;
        uint256 msigBalanceBefore = gem.balanceOf(address(multisig));
        uint256 usrBalanceBefore = gem.balanceOf(usr);
        uint256 supplyBefore = gem.totalSupply();
        tVest.vest(id, maxAmt);
        if (block.timestamp < clf) {
            assert(tVest.rxd(id) == rxd);
            assert(gem.balanceOf(address(multisig)) == msigBalanceBefore);
            assert(gem.balanceOf(usr) == usrBalanceBefore);
        }
        else {
            assert(tVest.rxd(id) == toUint128(add(rxd, amt)));
            assert(gem.balanceOf(address(multisig)) == sub(msigBalanceBefore, amt));
            assert(gem.balanceOf(usr) == add(usrBalanceBefore, amt));
        }
        assert(gem.totalSupply() == supplyBefore);
    }

    function restrict(uint256 id) public {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        tVest.restrict(id);
        assert(tVest.res(id) == 1);
    }

    function unrestrict(uint256 id) public {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        tVest.unrestrict(id);
        assert(tVest.res(id) == 0);
    }

    function yank(uint256 id, uint256 end) public {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        (, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = tVest.awards(id);
        tVest.yank(id, end);
        if (end < block.timestamp)  end = block.timestamp;
        if (end < fin) {
            end = toUint48(end);
            assert(tVest.fin(id) == end);
            if (end < bgn) {
                assert(tVest.bgn(id) == end);
                assert(tVest.clf(id) == end);
                assert(tVest.tot(id) == 0);
            } else if (end < clf) {
                assert(tVest.clf(id) == end);
                assert(tVest.tot(id) == 0);
            } else {
                assert(tVest.tot(id) == toUint128(
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
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        address dst = tVest.usr(id) == address(this) ? msg.sender : address(0);
        tVest.move(id, dst);
        assert(tVest.usr(id) == dst);
    }
}
