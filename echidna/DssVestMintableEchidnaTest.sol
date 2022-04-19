// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.6.12;

import {DssVest, DssVestMintable} from "../src/DssVest.sol";
import         {DSToken} from "./DSToken.sol";

interface Hevm {
    function store(address, bytes32, bytes32) external;
    function load(address, bytes32) external returns (bytes32);
}

contract DssVestMintableEchidnaTest {

    DssVestMintable internal mVest;
    DSToken         internal gem;

    uint256 internal constant  WAD  = 10 ** 18;
    uint256 internal constant  YEAR = 365 days;
    uint256 internal constant  MIN  = 500;      // Initial cap amount
    uint256 internal constant  MAX  = 2000;     // Max cap amount
    uint256 internal immutable salt;            // initialTimestamp


    // Clock
    uint256 internal last;
    modifier clock(uint256 time) {
        if (last <= block.timestamp - time)
        _;
        last = block.timestamp;
    }

    // Hevm
    Hevm hevm;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256("hevm cheat code"))));

    constructor() public {
        gem = new DSToken("MKR");
        mVest = new DssVestMintable(address(gem));
        mVest.file("cap", MIN * WAD / YEAR);
        gem.setOwner(address(mVest));
        salt = block.timestamp;
        hevm = Hevm(address(CHEAT_CODE));
    }

    // --- Math ---
    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x + y;
        assert(z >= x); // check if there is an addition overflow
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
            amt = tot * (time - bgn) / (fin - bgn);
        }
    }
    function unpaid(uint256 time, uint48 bgn, uint48 clf, uint48 fin, uint128 tot, uint128 rxd) internal pure returns (uint256 amt) {
        amt = time < clf ? 0 : (accrued(time, bgn, fin, tot) - rxd);
    }
    function cmpStr(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
    function bytesToBytes32(bytes memory source) internal pure returns (bytes32 result) {
        assembly {
            result := mload(add(source, 32))
        }
    }

    function rxdLessOrEqualTot(uint256 id) public view {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        assert(mVest.rxd(id) <= mVest.tot(id));
    }

    function clfGreaterOrEqualBgn(uint256 id) public view {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        assert(mVest.clf(id) >= mVest.bgn(id));
    }

    function finGreaterOrEqualClf(uint256 id) public view {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        assert(mVest.fin(id) >= mVest.clf(id));
    }

    function create(address usr, uint256 tot, uint256 bgn, uint256 tau, uint256 eta, address mgr) public {
        uint256 prevId = mVest.ids();
        try mVest.create(usr, tot, bgn, tau, eta, mgr) returns (uint256 id) {
            assert(mVest.ids() == _add(prevId, 1));
            assert(mVest.ids() == id);
            assert(mVest.valid(id));
            assert(mVest.usr(id) == usr);
            assert(mVest.bgn(id) == toUint48(bgn));
            assert(mVest.clf(id) == toUint48(_add(bgn, eta)));
            assert(mVest.fin(id) == toUint48(_add(bgn, tau)));
            assert(mVest.tot(id) == toUint128(tot));
            assert(mVest.rxd(id) == 0);
            assert(mVest.mgr(id) == mgr);
            assert(mVest.res(id) == 0);
            _mutusr(id);
        } catch Error(string memory errmsg) {
            bytes32 mLocked = hevm.load(address(mVest), bytes32(uint256(4)));      // Load memory slot 0x4
            assert(
                uint256(mLocked) == 1                                    && cmpStr(errmsg, "DssVest/system-locked")        ||
                mVest.wards(address(this)) == 0                          && cmpStr(errmsg, "DssVest/not-authorized")       ||
                usr == address(0)                                        && cmpStr(errmsg, "DssVest/invalid-user")         ||
                tot == 0                                                 && cmpStr(errmsg, "DssVest/no-vest-total-amount") ||
                bgn >= block.timestamp + mVest.TWENTY_YEARS()            && cmpStr(errmsg, "DssVest/bgn-too-far")          ||
                block.timestamp + mVest.TWENTY_YEARS() < block.timestamp && cmpStr(errmsg, "DssVest/add-overflow")         ||
                bgn <= block.timestamp - mVest.TWENTY_YEARS()            && cmpStr(errmsg, "DssVest/bgn-too-long-ago")     ||
                block.timestamp - mVest.TWENTY_YEARS() > block.timestamp && cmpStr(errmsg, "DssVest/sub-underflow")        ||
                tau == 0                                                 && cmpStr(errmsg, "DssVest/tau-zero")             ||
                tot /  tau > mVest.cap()                                 && cmpStr(errmsg, "DssVest/rate-too-high")        ||
                tau >  mVest.TWENTY_YEARS()                              && cmpStr(errmsg, "DssVest/tau-too-long")         ||
                eta >  tau                                               && cmpStr(errmsg, "DssVest/eta-too-long")         ||
                mVest.ids() == type(uint256).max                         && cmpStr(errmsg, "DssVest/ids-overflow")         ||
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
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        DssVest.Award memory award = DssVest.Award({
            usr: mVest.usr(id),
            bgn: toUint48(mVest.bgn(id)),
            clf: toUint48(mVest.clf(id)),
            fin: toUint48(mVest.fin(id)),
            mgr: mVest.mgr(id),
            res: toUint8(mVest.res(id)),
            tot: toUint128(mVest.tot(id)),
            rxd: toUint128(mVest.rxd(id))
        });
        uint256        timeDelta = block.timestamp - award.bgn;
        uint256       accruedAmt = accrued(block.timestamp, award.bgn, award.fin, award.tot);
        uint256        unpaidAmt = unpaid(block.timestamp, award.bgn, award.clf, award.fin, award.tot, award.rxd);
        uint256     supplyBefore = gem.totalSupply();
        uint256 usrBalanceBefore = gem.balanceOf(award.usr);
        try mVest.vest(id) {
            if (block.timestamp < award.clf) {
                assert(mVest.rxd(id) == award.rxd);
                assert(gem.totalSupply() == supplyBefore);
                assert(gem.balanceOf(award.usr) == usrBalanceBefore);
            }
            else {
                if (block.timestamp >= award.fin) {
                    assert(mVest.rxd(id) == award.tot);
                }
                else {
                    assert(mVest.rxd(id) == toUint128(_add(award.rxd, unpaidAmt)));
                }
                assert(gem.totalSupply() == _add(supplyBefore, unpaidAmt));
                assert(gem.balanceOf(award.usr) == _add(usrBalanceBefore, unpaidAmt));
            }
        } catch Error(string memory errmsg) {
            bytes32 mLocked = hevm.load(address(mVest), bytes32(uint256(4)));      // Load memory slot 0x4
            assert(
                uint256(mLocked) == 1                                              && cmpStr(errmsg, "DssVest/system-locked")       ||
                award.usr == address(0)                                            && cmpStr(errmsg, "DssVest/invalid-award")       ||
                award.res != 0 && award.usr != address(this)                       && cmpStr(errmsg, "DssVest/only-user-can-claim") ||
                accruedAmt - award.rxd > accruedAmt                                && cmpStr(errmsg, "DssVest/sub-underflow")       ||
                award.fin - award.bgn > award.fin                                  && cmpStr(errmsg, "DssVest/sub-underflow")       ||
                timeDelta > block.timestamp                                        && cmpStr(errmsg, "DssVest/sub-underflow")       ||
                timeDelta != 0 && (award.tot * timeDelta) / timeDelta != award.tot && cmpStr(errmsg, "DssVest/mul-overflow")        ||
                award.rxd + unpaidAmt < award.rxd                                  && cmpStr(errmsg, "DssVest/add-overflow")        ||
                uint128(award.rxd + unpaidAmt) != (award.rxd + unpaidAmt)          && cmpStr(errmsg, "DssVest/uint128-overflow")    ||
                gem.balanceOf(award.usr) + unpaidAmt < gem.balanceOf(award.usr)    && cmpStr(errmsg, "ds-math-add-overflow")        ||
                gem.totalSupply() + unpaidAmt < gem.totalSupply()                  && cmpStr(errmsg, "ds-math-add-overflow")
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function vest_amt(uint256 id, uint256 maxAmt) public {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        DssVest.Award memory award = DssVest.Award({
            usr: mVest.usr(id),
            bgn: toUint48(mVest.bgn(id)),
            clf: toUint48(mVest.clf(id)),
            fin: toUint48(mVest.fin(id)),
            mgr: mVest.mgr(id),
            res: toUint8(mVest.res(id)),
            tot: toUint128(mVest.tot(id)),
            rxd: toUint128(mVest.rxd(id))
        });
        uint256        timeDelta = block.timestamp - award.bgn;
        uint256       accruedAmt = accrued(block.timestamp, award.bgn, award.fin, award.tot);
        uint256        unpaidAmt = unpaid(block.timestamp, award.bgn, award.clf, award.fin, award.tot, award.rxd);
        uint256              amt = maxAmt > unpaidAmt ? unpaidAmt : maxAmt;
        uint256     supplyBefore = gem.totalSupply();
        uint256 usrBalanceBefore = gem.balanceOf(award.usr);
        try mVest.vest(id, maxAmt) {
            if (block.timestamp < award.clf) {
                assert(mVest.rxd(id) == award.rxd);
                assert(gem.totalSupply() == supplyBefore);
                assert(gem.balanceOf(award.usr) == usrBalanceBefore);
            }
            else {
                assert(mVest.rxd(id) == toUint128(_add(award.rxd, amt)));
                assert(gem.totalSupply() == _add(supplyBefore, amt));
                assert(gem.balanceOf(award.usr) == _add(usrBalanceBefore, amt));
            }
        } catch Error(string memory errmsg) {
            bytes32 mLocked = hevm.load(address(mVest), bytes32(uint256(4)));      // Load memory slot 0x4
            assert(
                uint256(mLocked) == 1                                              && cmpStr(errmsg, "DssVest/system-locked")       ||
                award.usr == address(0)                                            && cmpStr(errmsg, "DssVest/invalid-award")       ||
                award.res != 0 && award.usr != address(this)                       && cmpStr(errmsg, "DssVest/only-user-can-claim") ||
                accruedAmt - award.rxd > accruedAmt                                && cmpStr(errmsg, "DssVest/sub-underflow")       ||
                award.fin - award.bgn > award.fin                                  && cmpStr(errmsg, "DssVest/sub-underflow")       ||
                timeDelta > block.timestamp                                        && cmpStr(errmsg, "DssVest/sub-underflow")       ||
                timeDelta != 0 && (award.tot * timeDelta) / timeDelta != award.tot && cmpStr(errmsg, "DssVest/mul-overflow")        ||
                award.rxd + amt < award.rxd                                        && cmpStr(errmsg, "DssVest/add-overflow")        ||
                uint128(award.rxd + amt) != (award.rxd + amt)                      && cmpStr(errmsg, "DssVest/uint128-overflow")    ||
                gem.balanceOf(award.usr) + amt < gem.balanceOf(award.usr)          && cmpStr(errmsg, "ds-math-add-overflow")        ||
                gem.totalSupply() + amt < gem.totalSupply()                        && cmpStr(errmsg, "ds-math-add-overflow")
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function restrict(uint256 id) public {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        try mVest.restrict(id) {
            assert(mVest.res(id) == 1);
        } catch Error(string memory errmsg) {
            bytes32 mLocked = hevm.load(address(mVest), bytes32(uint256(4)));      // Load memory slot 0x4
            assert(
                uint256(mLocked) == 1           && cmpStr(errmsg, "DssVest/system-locked") ||
                mVest.usr(id) == address(0)     && cmpStr(errmsg, "DssVest/invalid-award") ||
                mVest.wards(address(this)) == 0 &&
                mVest.usr(id) != address(this)  && cmpStr(errmsg, "DssVest/not-authorized")
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function unrestrict(uint256 id) public {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        try mVest.unrestrict(id) {
            assert(mVest.res(id) == 0);
        } catch Error(string memory errmsg) {
            bytes32 mLocked = hevm.load(address(mVest), bytes32(uint256(4)));      // Load memory slot 0x4
            assert(
               uint256(mLocked) == 1           && cmpStr(errmsg, "DssVest/system-locked") ||
               mVest.usr(id) == address(0)     && cmpStr(errmsg, "DssVest/invalid-award") ||
               mVest.wards(address(this)) == 0 &&
               mVest.usr(id) != address(this)  && cmpStr(errmsg, "DssVest/not-authorized")
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function yank(uint256 id, uint256 end) public {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 tot, uint128 rxd) = mVest.awards(id);
        uint256  timeDelta = block.timestamp - bgn;
        uint256 accruedAmt = accrued(block.timestamp, bgn, fin, tot);
        uint256  unpaidAmt = unpaid(block.timestamp, bgn, clf, fin, tot, rxd);
        try mVest.yank(id, end) {
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
                    assert(mVest.tot(id) == toUint128(_add(unpaidAmt, rxd)));
                }
            }
        } catch Error(string memory errmsg) {
            bytes32 mLocked = hevm.load(address(mVest), bytes32(uint256(4)));      // Load memory slot 0x4
            assert(
                uint256(mLocked) == 1                                              && cmpStr(errmsg, "DssVest/system-locked")    ||
                mVest.wards(address(this)) == 0 && mgr != address(this)            && cmpStr(errmsg, "DssVest/not-authorized")   ||
                usr == address(0)                                                  && cmpStr(errmsg, "DssVest/invalid-award")    ||
                uint128(end) != end                                                && cmpStr(errmsg, "DssVest/uint128-overflow") ||
                uint128(unpaidAmt + rxd) != (unpaidAmt + rxd)                      && cmpStr(errmsg, "DssVest/uint128-overflow") ||
                unpaidAmt + rxd < unpaidAmt                                        && cmpStr(errmsg, "DssVest/add-overflow")     ||
                accruedAmt - rxd > accruedAmt                                      && cmpStr(errmsg, "DssVest/sub-underflow")    ||
                fin - bgn > fin                                                    && cmpStr(errmsg, "DssVest/sub-underflow")    ||
                timeDelta > block.timestamp                                        && cmpStr(errmsg, "DssVest/sub-underflow")    ||
                timeDelta != 0 && (tot * timeDelta) / timeDelta != tot             && cmpStr(errmsg, "DssVest/mul-overflow")
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function move(uint256 id, address dst) public {
        id = mVest.ids() == 0 ? id : id % mVest.ids();
        try mVest.move(id, dst){
            assert(mVest.usr(id) == dst);
            _mutusr(id);
        } catch Error(string memory errmsg) {
            bytes32 mLocked = hevm.load(address(mVest), bytes32(uint256(4)));      // Load memory slot 0x4
            assert(
                uint256(mLocked) == 1          && cmpStr(errmsg, "DssVest/system-locked")       ||
                mVest.usr(id) != address(this) && cmpStr(errmsg, "DssVest/only-user-can-move")  ||
                dst == address(0)              && cmpStr(errmsg, "DssVest/zero-address-invalid")
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    // --- Time-Based Fuzz Mutations ---

    function mutlock() private clock(1 hours) {
        bytes32 mLocked = hevm.load(address(mVest), bytes32(uint256(4)));          // Load memory slot 0x4
        uint256 locked = uint256(mLocked) == 0 ? 1 : 0;
        // Set DssVestMintable locked slot n. 4 to override 0 with 1 and vice versa
        hevm.store(address(mVest), bytes32(uint256(4)), bytes32(uint256(locked)));
        mLocked = hevm.load(address(mVest), bytes32(uint256(4)));
        assert(uint256(mLocked) == locked);
    }
    function mutauth() private clock(1 hours) {
        uint256 wards = mVest.wards(address(this)) == 1 ? 0 : 1;
        // Set DssVestMintable wards slot n. 0 to override address(this) wards
        hevm.store(address(mVest), keccak256(abi.encode(address(this), uint256(0))), bytes32(uint256(wards)));
        assert(mVest.wards(address(this)) == wards);
    }
    function mutusr(uint256 id) private clock(1 days) {
        id = mVest.ids() == 0 ? 0 : id % mVest.ids();
        if (id == 0) return;
        _mutusr(id);
    }
    function _mutusr(uint256 id) internal {
        address usr = mVest.usr(id) == address(this) ? address(0) : address(this);
        // Set DssVestMintable awards slot n. 1 (clf, bgn, usr) to override awards(id).usr with address(this)
        hevm.store(address(mVest), keccak256(abi.encode(uint256(id), uint256(1))), bytesToBytes32(abi.encodePacked(uint48(mVest.clf(id)), uint48(mVest.bgn(id)), usr)));
        assert(mVest.usr(id) == usr);
    }
    function mutcap(uint256 bump) private clock(90 days) {
        bump %= MAX;
        if (bump == 0) return;
        uint256 data = bump > MIN ? bump * WAD / YEAR : MIN * WAD / YEAR;
        // Set DssVestMintable cap slot n. 2 to override cap with data
        hevm.store(address(mVest), bytes32(uint256(2)), bytes32(uint256(data)));
        assert(mVest.cap() == data);
    }
}
