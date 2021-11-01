// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.6.12;

import "../src/DssVest.sol";
import "./ChainLog.sol";
import "./Vat.sol";
import "./DaiJoin.sol";
import "./Dai.sol";

interface Hevm {
    function store(address, bytes32, bytes32) external;
}

struct Award {
    address usr;   // Vesting recipient
    uint48  bgn;   // Start of vesting period  [timestamp]
    uint48  clf;   // The cliff date           [timestamp]
    uint48  fin;   // End of vesting period    [timestamp]
    address mgr;   // A manager address that can yank
    uint8   res;   // Restricted
    uint128 tot;   // Total reward amount
    uint128 rxd;   // Amount of vest claimed
}

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

    // Hevm
    Hevm hevm;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256("hevm cheat code"))));

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
        hevm = Hevm(address(CHEAT_CODE));
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
    function toUint8(uint256 x) internal pure returns (uint8 z) {
        z = uint8(x);
        assert(z == x);
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
    function bytesToBytes32(bytes memory source) internal pure returns (bytes32 result) {
        assembly {
            result := mload(add(source, 32))
        }
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

    function create(address usr, uint256 tot, uint256 bgn, uint256 tau, uint256 eta, address mgr) public {
        uint256 prevId = sVest.ids();
        try sVest.create(usr, tot, bgn, tau, eta, mgr) returns (uint256 id) {
            assert(sVest.ids() == add(prevId, 1));
            assert(sVest.ids() == id);
            assert(sVest.valid(id));
            assert(sVest.usr(id) == usr);
            assert(sVest.bgn(id) == toUint48(bgn));
            assert(sVest.clf(id) == toUint48(add(bgn, eta)));
            assert(sVest.fin(id) == toUint48(add(bgn, tau)));
            assert(sVest.tot(id) == toUint128(tot));
            assert(sVest.rxd(id) == 0);
            assert(sVest.mgr(id) == mgr);
            assert(sVest.res(id) == 0);
            // Set DssVestSuckable awards slot n. 2 (clf, bgn, usr) to override awards(id).usr with address(this)
            hevm.store(address(sVest), keccak256(abi.encode(uint256(id), uint256(2))), bytesToBytes32(abi.encodePacked(uint48(sVest.clf(id)), uint48(sVest.bgn(id)), address(this))));
            assert(sVest.usr(id) == address(this));
        } catch Error(string memory errmsg) {
            assert(
                usr == address(0)                                        && cmpStr(errmsg, "DssVest/invalid-user")         ||
                tot == 0                                                 && cmpStr(errmsg, "DssVest/no-vest-total-amount") ||
                bgn >= block.timestamp + sVest.TWENTY_YEARS()            && cmpStr(errmsg, "DssVest/bgn-too-far")          ||
                block.timestamp + sVest.TWENTY_YEARS() < block.timestamp && cmpStr(errmsg, "DssVest/add-overflow")         ||
                bgn <= block.timestamp - sVest.TWENTY_YEARS()            && cmpStr(errmsg, "DssVest/bgn-too-long-ago")     ||
                block.timestamp - sVest.TWENTY_YEARS() > block.timestamp && cmpStr(errmsg, "DssVest/sub-underflow")        ||
                tau == 0                                                 && cmpStr(errmsg, "DssVest/tau-zero")             ||
                tot /  tau > sVest.cap()                                 && cmpStr(errmsg, "DssVest/rate-too-high")        ||
                tau >  sVest.TWENTY_YEARS()                              && cmpStr(errmsg, "DssVest/tau-too-long")         ||
                eta >  tau                                               && cmpStr(errmsg, "DssVest/eta-too-long")         ||
                sVest.ids() == type(uint256).max                         && cmpStr(errmsg, "DssVest/ids-overflow")         ||
                uint48(bgn) != bgn                                       && cmpStr(errmsg, "DssVest/uint48-overflow")      ||
                uint48(bgn + eta) != bgn + eta                           && cmpStr(errmsg, "DssVest/uint48-overflow")      ||
                bgn + eta < bgn                                          && cmpStr(errmsg, "DssVest/add-overflow")         ||
                uint48(bgn + tau) != bgn + tau                           && cmpStr(errmsg, "DssVest/uint48-overflow")      ||
                bgn + tau < bgn                                          && cmpStr(errmsg, "DssVest/add-overflow")         ||
                uint128(tot) != tot                                      && cmpStr(errmsg, "DssVest/uint128-overflow")
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function vest(uint256 id) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
        Award memory award = Award({
            usr: sVest.usr(id),
            bgn: toUint48(sVest.bgn(id)),
            clf: toUint48(sVest.clf(id)),
            fin: toUint48(sVest.fin(id)),
            mgr: sVest.mgr(id),
            res: toUint8(sVest.res(id)),
            tot: toUint128(sVest.tot(id)),
            rxd: toUint128(sVest.rxd(id))
        });
        uint256 unpaidAmt = unpaid(block.timestamp, award.bgn, award.clf, award.fin, award.tot, award.rxd);
        uint256 sinBefore = vat.sin(vow);
        uint256 supplyBefore = dai.totalSupply();
        uint256 usrBalanceBefore = dai.balanceOf(award.usr);
        try sVest.vest(id) {
            if (block.timestamp < award.clf) {
                assert(sVest.rxd(id) == award.rxd);
                assert(vat.sin(vow) == sinBefore);
                assert(dai.totalSupply() == supplyBefore);
                assert(dai.balanceOf(award.usr) == usrBalanceBefore);
            }
            else {
                if (block.timestamp >= award.fin) {
                    assert(sVest.rxd(id) == award.tot);
                }
                else {
                    assert(sVest.rxd(id) == toUint128(add(award.rxd, unpaidAmt)));
                }
                assert(vat.sin(vow) == add(sinBefore, mul(unpaidAmt, RAY)));
                assert(dai.totalSupply() == add(supplyBefore, unpaidAmt));
                assert(dai.balanceOf(award.usr) == add(usrBalanceBefore, unpaidAmt));
            }
        } catch Error(string memory errmsg) {
            assert(
                award.usr == address(0)                   && cmpStr(errmsg, "DssVest/invalid-award")       ||
                award.res == 1 && award.usr != msg.sender && cmpStr(errmsg, "DssVest/only-user-can-claim")
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function vest_amt(uint256 id, uint256 maxAmt) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
        Award memory award = Award({
            usr: sVest.usr(id),
            bgn: toUint48(sVest.bgn(id)),
            clf: toUint48(sVest.clf(id)),
            fin: toUint48(sVest.fin(id)),
            mgr: sVest.mgr(id),
            res: toUint8(sVest.res(id)),
            tot: toUint128(sVest.tot(id)),
            rxd: toUint128(sVest.rxd(id))
        });
        uint256 unpaidAmt = unpaid(block.timestamp, award.bgn, award.clf, award.fin, award.tot, award.rxd);
        uint256 amt = maxAmt > unpaidAmt ? unpaidAmt : maxAmt;
        uint256 sinBefore = vat.sin(vow);
        uint256 supplyBefore = dai.totalSupply();
        uint256 usrBalanceBefore = dai.balanceOf(award.usr);
        try sVest.vest(id, maxAmt) {
            if (block.timestamp < award.clf) {
                assert(sVest.rxd(id) == award.rxd);
                assert(vat.sin(vow) == sinBefore);
                assert(dai.totalSupply() == supplyBefore);
                assert(dai.balanceOf(award.usr) == usrBalanceBefore);
            }
            else {
                assert(sVest.rxd(id) == toUint128(add(award.rxd, amt)));
                assert(vat.sin(vow) == add(sinBefore, mul(amt, RAY)));
                assert(dai.totalSupply() == add(supplyBefore, amt));
                assert(dai.balanceOf(award.usr) == add(usrBalanceBefore, amt));
            }
        } catch Error(string memory errmsg) {
            assert(
                award.usr == address(0)                   && cmpStr(errmsg, "DssVest/invalid-award")       ||
                award.res == 1 && award.usr != msg.sender && cmpStr(errmsg, "DssVest/only-user-can-claim")
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function restrict(uint256 id) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
        try sVest.restrict(id) {
            assert(sVest.res(id) == 1);
        } catch Error(string memory errmsg) {
            assert(sVest.usr(id) == address(0) && cmpStr(errmsg, "DssVest/invalid-award"));
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function unrestrict(uint256 id) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
        try sVest.unrestrict(id) {
            assert(sVest.res(id) == 0);
        } catch Error(string memory errmsg) {
            assert(sVest.usr(id) == address(0) && cmpStr(errmsg, "DssVest/invalid-award"));
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function yank(uint256 id, uint256 end) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
        (address usr, uint48 bgn, uint48 clf, uint48 fin,, uint256 res, uint128 tot, uint128 rxd) = sVest.awards(id);
        try sVest.yank(id, end) {
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
        } catch Error(string memory errmsg) {
            assert(usr == address(0) && cmpStr(errmsg, "DssVest/invalid-award"));
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function move(uint id) public {
        id = sVest.ids() == 0 ? id : id % sVest.ids();
        address dst = sVest.usr(id) == address(this) ? msg.sender : address(0);
        try sVest.move(id, dst) {
            assert(sVest.usr(id) == dst);
        } catch Error(string memory errmsg) {
            assert(sVest.usr(id) != address(this) && cmpStr(errmsg, "DssVest/only-user-can-move"));
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }
}
