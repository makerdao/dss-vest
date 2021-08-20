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
    uint256 internal immutable salt;

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

    function rxdLessOrEqualTot() public returns (bool) {
        uint256 id = tVest.ids();
        require(tVest.valid(id));
        return tVest.rxd(id) <= tVest.tot(id);
    }

    function create(uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _eta) public {
        _tot = _tot % uint128(-1);
        if (_tot < WAD) _tot = (1 + _tot) * WAD;
        _bgn = sub(salt, tVest.TWENTY_YEARS() / 2) + _bgn % tVest.TWENTY_YEARS();
        _tau = 1 + _tau % tVest.TWENTY_YEARS();
        _eta = _eta % _tau;
        if (_tot / _tau > tVest.cap()) {
            _tot = 500 * WAD;
            _tau = 365 days;
        }
        uint256 prevId = tVest.ids();
        uint256 id = tVest.create(address(this), _tot, _bgn, _tau, _eta, address(0));
        assert(tVest.ids() == add(prevId, 1));
        assert(tVest.ids() == id);
        assert(tVest.valid(id));
        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr, uint8 res, uint128 tot, uint128 rxd) = tVest.awards(id);
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
        id = tVest.valid(id) ? id : tVest.ids();
        (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = tVest.awards(id);
        uint256 unpaidAmt = unpaid(block.timestamp, bgn, clf, fin, tot, rxd);
        uint256 msigBalanceBefore = gem.balanceOf(address(multisig));
        uint256 usrBalanceBefore = gem.balanceOf(usr);
        uint256 supplyBefore = gem.totalSupply();
        tVest.vest(id);
        if (block.timestamp < clf) {
            assert(unpaidAmt == 0);
            assert(tVest.rxd(id) == rxd);
            assert(gem.balanceOf(address(multisig)) == msigBalanceBefore);
            assert(gem.balanceOf(usr) == usrBalanceBefore);
        }
        else {
            if (block.timestamp < bgn) {
                assert(unpaidAmt == rxd);
            }
            else if (block.timestamp >= fin) {
                assert(unpaidAmt == sub(tot, rxd));
                assert(tVest.rxd(id) == tot);
            } 
            else {
                assert(unpaidAmt >= 0);
                assert(unpaidAmt < tot);
                assert(unpaidAmt == unpaid(block.timestamp, bgn, clf, fin, tot, rxd));
                assert(tVest.rxd(id) == toUint128(add(rxd, unpaidAmt)));
            }
            assert(gem.balanceOf(address(multisig)) == sub(msigBalanceBefore, unpaidAmt));
            assert(gem.balanceOf(usr) == add(usrBalanceBefore, unpaidAmt));
        }
        assert(gem.totalSupply() == supplyBefore);
    }

    function vest_amt(uint256 id, uint256 maxAmt) public {
        id = tVest.valid(id) ? id : tVest.ids();
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
        id = tVest.valid(id) ? id : tVest.ids();
        tVest.restrict(id);
        assert(tVest.res(id) == 1);
    }

    function unrestrict(uint256 id) public {
        id = tVest.valid(id) ? id : tVest.ids();
        tVest.unrestrict(id);
        assert(tVest.res(id) == 0);
    }

    function yank(uint256 id, uint256 end) public {
        id = tVest.valid(id) ? id : tVest.ids();
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
        id = tVest.valid(id) ? id : tVest.ids();
        address dst = tVest.usr(id) == address(this) ? msg.sender : address(0);
        tVest.move(id, dst);
        assert(tVest.usr(id) == dst);
    }
}
