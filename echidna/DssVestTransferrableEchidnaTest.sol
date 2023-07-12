// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import {DssVest, DssVestTransferrable} from "../src/DssVest.sol";
import                  {Dai} from "./Dai.sol";

interface Hevm {
    function store(address, bytes32, bytes32) external;
    function load(address, bytes32) external returns (bytes32);
}

/// @dev A contract that will receive Dai, and allows for it to be retrieved.
contract Multisig {

    function approve(address dai, address vest) external {
        Dai(dai).approve(vest, type(uint256).max);
    }
}

contract DssVestTransferrableEchidnaTest {

    DssVestTransferrable internal tVest;
    Dai internal gem;
    Multisig internal multisig;

    uint256 internal constant  WAD      = 10 ** 18;
    uint256 internal constant  THOUSAND = 10 ** 3;
    uint256 internal constant  MILLION  = 10 ** 6;
    uint256 internal constant  TIME     = 30 days;
    uint256 internal constant  MIN      = THOUSAND; // Initial cap amount
    uint256 internal constant  MAX      = MILLION;  // Max cap amount
    uint256 internal constant  WARDS_MEMORY_SLOT    = 1;
    uint256 internal constant  AWARDS_MEMORY_SLOT   = 2;
    uint256 internal constant  CAP_MEMORY_SLOT      = 3;
    uint256 internal constant  IDS_MEMORY_SLOT      = 4;
    uint256 internal constant  LOCK_MEMORY_SLOT     = 5;
    uint256 internal immutable salt;                // initialTimestamp

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

    constructor() {
        gem = new Dai(1);
        multisig = new Multisig();
        gem.mint(address(multisig), type(uint128).max);
        tVest = new DssVestTransferrable(address(0x1), address(multisig), address(gem), MIN * WAD / TIME);
        multisig.approve(address(gem), address(tVest));
        salt = block.timestamp;
        hevm = Hevm(address(CHEAT_CODE));
    }

    // --- Math ---
    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x + y;
        assert(z >= x); // check if there is an addition overflow
    }
    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x - y;
        assert(z <= x); // check if there is a subtraction overflow
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
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        assert(tVest.rxd(id) <= tVest.tot(id));
    }

    function clfGreaterOrEqualBgn(uint256 id) public view {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        assert(tVest.clf(id) >= tVest.bgn(id));
    }

    function finGreaterOrEqualClf(uint256 id) public view {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        assert(tVest.fin(id) >= tVest.clf(id));
    }

    function commit(bytes32 bch) public {
        try tVest.commit(bch) {
            assert(tVest.commitments(bch) == true);
        } catch Error(string memory errmsg) {
            assert(tVest.wards(address(this)) == 0 && cmpStr(errmsg, "DssVest/not-authorized"));
        }
    }

    function claim(bytes32 bch, address usr, uint256 tot, uint256 bgn, uint256 tau, uint256 eta, address mgr, bytes32 slt) public {
        uint256 prevId = tVest.ids();
        bool committed = tVest.commitments(bch);
        bytes32 contentHash = keccak256(abi.encodePacked(usr, tot, bgn, tau, eta, mgr, slt));
        try tVest.claim(bch, usr, tot, bgn, tau, eta, mgr, slt) returns (uint256 id) {
            assert(tVest.ids() == _add(prevId, 1));
            assert(tVest.ids() == id);
            assert(tVest.valid(id));
            assert(tVest.usr(id) == usr);
            assert(tVest.bgn(id) == toUint48(bgn));
            assert(tVest.clf(id) == toUint48(_add(bgn, eta)));
            assert(tVest.fin(id) == toUint48(_add(bgn, tau)));
            assert(tVest.tot(id) == toUint128(tot));
            assert(tVest.rxd(id) == 0);
            assert(tVest.mgr(id) == mgr);
            assert(tVest.res(id) == 1);
            assert(bch == contentHash); // hash must match contents
            assert(committed == true); // commitment must have been true before
            assert(tVest.commitments(bch) == false); // commitment must be false after
            _mutusr(id);
        } catch Error(string memory errmsg) {
            bytes32 tLocked = hevm.load(address(tVest), bytes32(uint256(LOCK_MEMORY_SLOT)));      // Load memory slot containing locked flag
            assert(
                uint256(tLocked) == 1                                    && cmpStr(errmsg, "DssVest/system-locked")        ||
                // authorization is not required for this function
                // tVest.wards(address(this)) == 0                          && cmpStr(errmsg, "DssVest/not-authorized")       ||
                usr == address(0)                                        && cmpStr(errmsg, "DssVest/invalid-user")         ||
                tot == 0                                                 && cmpStr(errmsg, "DssVest/no-vest-total-amount") ||
                bgn >= block.timestamp + tVest.TWENTY_YEARS()            && cmpStr(errmsg, "DssVest/bgn-too-far")          ||
                block.timestamp + tVest.TWENTY_YEARS() < block.timestamp && cmpStr(errmsg, "DssVest/add-overflow")         ||
                bgn <= block.timestamp - tVest.TWENTY_YEARS()            && cmpStr(errmsg, "DssVest/bgn-too-long-ago")     ||
                block.timestamp - tVest.TWENTY_YEARS() > block.timestamp && cmpStr(errmsg, "DssVest/sub-underflow")        ||
                tau == 0                                                 && cmpStr(errmsg, "DssVest/tau-zero")             ||
                tot /  tau > tVest.cap()                                 && cmpStr(errmsg, "DssVest/rate-too-high")        ||
                tau >  tVest.TWENTY_YEARS()                              && cmpStr(errmsg, "DssVest/tau-too-long")         ||
                eta >  tau                                               && cmpStr(errmsg, "DssVest/eta-too-long")         ||
                tVest.ids() == type(uint256).max                         && cmpStr(errmsg, "DssVest/ids-overflow")         ||
                uint48(bgn) != bgn                                       && cmpStr(errmsg, "DssVest/uint48-overflow")      ||
                uint48(bgn + eta) != bgn + eta                           && cmpStr(errmsg, "DssVest/uint48-overflow")      ||
                bgn + eta < bgn                                          && cmpStr(errmsg, "DssVest/add-overflow")         ||
                uint48(bgn + tau) != bgn + tau                           && cmpStr(errmsg, "DssVest/uint48-overflow")      ||
                bgn + tau < bgn                                          && cmpStr(errmsg, "DssVest/add-overflow")         ||
                uint128(tot) != tot                                      && cmpStr(errmsg, "DssVest/uint128-overflow")     ||
                committed == false                                       && cmpStr(errmsg, "DssVest/commitment-not-found") ||
                bch != contentHash                                       && cmpStr(errmsg, "DssVest/invalid-hash")   
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function create(address usr, uint256 tot, uint256 bgn, uint256 tau, uint256 eta, address mgr) public {
        uint256 prevId = tVest.ids();
        try tVest.create(usr, tot, bgn, tau, eta, mgr) returns (uint256 id) {
            assert(tVest.ids() == _add(prevId, 1));
            assert(tVest.ids() == id);
            assert(tVest.valid(id));
            assert(tVest.usr(id) == usr);
            assert(tVest.bgn(id) == toUint48(bgn));
            assert(tVest.clf(id) == toUint48(_add(bgn, eta)));
            assert(tVest.fin(id) == toUint48(_add(bgn, tau)));
            assert(tVest.tot(id) == toUint128(tot));
            assert(tVest.rxd(id) == 0);
            assert(tVest.mgr(id) == mgr);
            assert(tVest.res(id) == 1);
            _mutusr(id);
        } catch Error(string memory errmsg) {
            bytes32 tLocked = hevm.load(address(tVest), bytes32(uint256(LOCK_MEMORY_SLOT)));      // Load memory slot containing locked flag
            assert(
                uint256(tLocked) == 1                                    && cmpStr(errmsg, "DssVest/system-locked")        ||
                tVest.wards(address(this)) == 0                          && cmpStr(errmsg, "DssVest/not-authorized")       ||
                usr == address(0)                                        && cmpStr(errmsg, "DssVest/invalid-user")         ||
                tot == 0                                                 && cmpStr(errmsg, "DssVest/no-vest-total-amount") ||
                bgn >= block.timestamp + tVest.TWENTY_YEARS()            && cmpStr(errmsg, "DssVest/bgn-too-far")          ||
                block.timestamp + tVest.TWENTY_YEARS() < block.timestamp && cmpStr(errmsg, "DssVest/add-overflow")         ||
                bgn <= block.timestamp - tVest.TWENTY_YEARS()            && cmpStr(errmsg, "DssVest/bgn-too-long-ago")     ||
                block.timestamp - tVest.TWENTY_YEARS() > block.timestamp && cmpStr(errmsg, "DssVest/sub-underflow")        ||
                tau == 0                                                 && cmpStr(errmsg, "DssVest/tau-zero")             ||
                tot /  tau > tVest.cap()                                 && cmpStr(errmsg, "DssVest/rate-too-high")        ||
                tau >  tVest.TWENTY_YEARS()                              && cmpStr(errmsg, "DssVest/tau-too-long")         ||
                eta >  tau                                               && cmpStr(errmsg, "DssVest/eta-too-long")         ||
                tVest.ids() == type(uint256).max                         && cmpStr(errmsg, "DssVest/ids-overflow")         ||
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
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        DssVest.Award memory award = DssVest.Award({
            usr: tVest.usr(id),
            bgn: toUint48(tVest.bgn(id)),
            clf: toUint48(tVest.clf(id)),
            fin: toUint48(tVest.fin(id)),
            mgr: tVest.mgr(id),
            res: toUint8(tVest.res(id)),
            tot: toUint128(tVest.tot(id)),
            rxd: toUint128(tVest.rxd(id))
        });
        uint256         timeDelta = block.timestamp - award.bgn;
        uint256        accruedAmt = accrued(block.timestamp, award.bgn, award.fin, award.tot);
        uint256         unpaidAmt = unpaid(block.timestamp, award.bgn, award.clf, award.fin, award.tot, award.rxd);
        uint256 msigBalanceBefore = gem.balanceOf(address(multisig));
        uint256  usrBalanceBefore = gem.balanceOf(award.usr);
        uint256      supplyBefore = gem.totalSupply();
        try tVest.vest(id) {
            if (block.timestamp < award.clf) {
                assert(tVest.rxd(id) == award.rxd);
                assert(gem.balanceOf(address(multisig)) == msigBalanceBefore);
                assert(gem.balanceOf(award.usr) == usrBalanceBefore);
            }
            else {
                if (block.timestamp >= award.fin) {
                    assert(tVest.rxd(id) == award.tot);
                }
                else {
                    assert(tVest.rxd(id) == toUint128(_add(award.rxd, unpaidAmt)));
                }
                assert(gem.balanceOf(address(multisig)) == _sub(msigBalanceBefore, unpaidAmt));
                assert(gem.balanceOf(award.usr) == _add(usrBalanceBefore, unpaidAmt));
            }
            assert(gem.totalSupply() == supplyBefore);
        } catch Error(string memory errmsg) {
            bytes32 tLocked = hevm.load(address(tVest), bytes32(uint256(LOCK_MEMORY_SLOT)));      // Load memory slot containing locked flag
            assert(
                uint256(tLocked) == 1                                                 && cmpStr(errmsg, "DssVest/system-locked")       ||
                award.usr == address(0)                                               && cmpStr(errmsg, "DssVest/invalid-award")       ||
                award.res !=0 && award.usr != address(this)                           && cmpStr(errmsg, "DssVest/only-user-can-claim") ||
                accruedAmt - award.rxd > accruedAmt                                   && cmpStr(errmsg, "DssVest/sub-underflow")       ||
                award.fin - award.bgn > award.fin                                     && cmpStr(errmsg, "DssVest/sub-underflow")       ||
                timeDelta > block.timestamp                                           && cmpStr(errmsg, "DssVest/sub-underflow")       ||
                timeDelta != 0 && (award.tot * timeDelta) / timeDelta != award.tot    && cmpStr(errmsg, "DssVest/mul-overflow")        ||
                award.rxd + unpaidAmt < award.rxd                                     && cmpStr(errmsg, "DssVest/add-overflow")        ||
                uint128(award.rxd + unpaidAmt) != (award.rxd + unpaidAmt)             && cmpStr(errmsg, "DssVest/uint128-overflow")    ||
                gem.balanceOf(address(multisig)) < unpaidAmt                          && cmpStr(errmsg, "gem/insufficient-balance")    ||
                gem.allowance(address(multisig), address(tVest)) != type(uint256).max &&
                gem.allowance(address(multisig), address(tVest)) < unpaidAmt          && cmpStr(errmsg, "gem/insufficient-allowance")
            );
        } catch {
            assert(
                gem.allowance(address(multisig), address(tVest)) != type(uint256).max                                           &&
                gem.allowance(address(multisig), address(tVest)) - unpaidAmt > gem.allowance(address(multisig), address(tVest)) ||
                gem.balanceOf(address(multisig)) - unpaidAmt > unpaidAmt                                                        ||
                gem.balanceOf(award.usr) + unpaidAmt < unpaidAmt
            );
        }
    }

    function vest_amt(uint256 id, uint256 maxAmt) public {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        DssVest.Award memory award = DssVest.Award({
            usr: tVest.usr(id),
            bgn: toUint48(tVest.bgn(id)),
            clf: toUint48(tVest.clf(id)),
            fin: toUint48(tVest.fin(id)),
            mgr: tVest.mgr(id),
            res: toUint8(tVest.res(id)),
            tot: toUint128(tVest.tot(id)),
            rxd: toUint128(tVest.rxd(id))
        });
        uint256         timeDelta = block.timestamp - award.bgn;
        uint256        accruedAmt = accrued(block.timestamp, award.bgn, award.fin, award.tot);
        uint256         unpaidAmt = unpaid(block.timestamp, award.bgn, award.clf, award.fin, award.tot, award.rxd);
        uint256               amt = maxAmt > unpaidAmt ? unpaidAmt : maxAmt;
        uint256 msigBalanceBefore = gem.balanceOf(address(multisig));
        uint256  usrBalanceBefore = gem.balanceOf(award.usr);
        uint256      supplyBefore = gem.totalSupply();
        try tVest.vest(id, maxAmt) {
            if (block.timestamp < award.clf) {
                assert(tVest.rxd(id) == award.rxd);
                assert(gem.balanceOf(address(multisig)) == msigBalanceBefore);
                assert(gem.balanceOf(award.usr) == usrBalanceBefore);
            }
            else {
                assert(tVest.rxd(id) == toUint128(_add(award.rxd, amt)));
                assert(gem.balanceOf(address(multisig)) == _sub(msigBalanceBefore, amt));
                assert(gem.balanceOf(award.usr) == _add(usrBalanceBefore, amt));
            }
            assert(gem.totalSupply() == supplyBefore);
        } catch Error(string memory errmsg) {
            bytes32 tLocked = hevm.load(address(tVest), bytes32(uint256(LOCK_MEMORY_SLOT)));      // Load memory slot containing locked flag
            assert(
                uint256(tLocked) == 1                                                 && cmpStr(errmsg, "DssVest/system-locked")       ||
                award.usr == address(0)                                               && cmpStr(errmsg, "DssVest/invalid-award")       ||
                award.res != 0 && award.usr != address(this)                          && cmpStr(errmsg, "DssVest/only-user-can-claim") ||
                accruedAmt - award.rxd > accruedAmt                                   && cmpStr(errmsg, "DssVest/sub-underflow")       ||
                award.fin - award.bgn > award.fin                                     && cmpStr(errmsg, "DssVest/sub-underflow")       ||
                timeDelta > block.timestamp                                           && cmpStr(errmsg, "DssVest/sub-underflow")       ||
                timeDelta != 0 && (award.tot * timeDelta) / timeDelta != award.tot    && cmpStr(errmsg, "DssVest/mul-overflow")        ||
                award.rxd + amt < award.rxd                                           && cmpStr(errmsg, "DssVest/add-overflow")        ||
                uint128(award.rxd + amt) != (award.rxd + amt)                         && cmpStr(errmsg, "DssVest/uint128-overflow")    ||
                gem.balanceOf(address(multisig)) < amt                                && cmpStr(errmsg, "gem/insufficient-balance")    ||
                gem.allowance(address(multisig), address(tVest)) != type(uint256).max &&
                gem.allowance(address(multisig), address(tVest)) < amt                && cmpStr(errmsg, "gem/insufficient-allowance")
            );
        } catch {
            assert(
                gem.allowance(address(multisig), address(tVest)) != type(uint256).max                                     &&
                gem.allowance(address(multisig), address(tVest)) - amt > gem.allowance(address(multisig), address(tVest)) ||
                gem.balanceOf(address(multisig)) - amt > amt                                                              ||
                gem.balanceOf(award.usr) + amt < amt
            );
        }
    }

    function restrict(uint256 id) public {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        try tVest.restrict(id) {
            assert(tVest.res(id) == 1);
        } catch Error(string memory errmsg) {
            bytes32 tLocked = hevm.load(address(tVest), bytes32(uint256(LOCK_MEMORY_SLOT)));      // Load memory slot containing locked flag
            assert(
                uint256(tLocked) == 1           && cmpStr(errmsg, "DssVest/system-locked") ||
                tVest.usr(id) == address(0)     && cmpStr(errmsg, "DssVest/invalid-award") ||
                tVest.wards(address(this)) == 0 &&
                tVest.usr(id) != address(this)  && cmpStr(errmsg, "DssVest/not-authorized")
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function unrestrict(uint256 id) public {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        try tVest.unrestrict(id) {
            assert(tVest.res(id) == 0);
        } catch Error(string memory errmsg) {
            bytes32 tLocked = hevm.load(address(tVest), bytes32(uint256(LOCK_MEMORY_SLOT)));      // Load memory slot containing locked flag
            assert(
               uint256(tLocked) == 1           && cmpStr(errmsg, "DssVest/system-locked") ||
               tVest.usr(id) == address(0)     && cmpStr(errmsg, "DssVest/invalid-award") ||
               tVest.wards(address(this)) == 0 &&
               tVest.usr(id) != address(this)  && cmpStr(errmsg, "DssVest/not-authorized")
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function yank(uint256 id, uint256 end) public {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 tot, uint128 rxd) = tVest.awards(id);
        uint256  timeDelta = block.timestamp - bgn;
        uint256 accruedAmt = accrued(block.timestamp, bgn, fin, tot);
        uint256  unpaidAmt = unpaid(block.timestamp, bgn, clf, fin, tot, rxd);
        try tVest.yank(id, end) {
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
                    assert(tVest.tot(id) == toUint128(_add(unpaidAmt, rxd)));
                }
            }
        } catch Error(string memory errmsg) {
            bytes32 tLocked = hevm.load(address(tVest), bytes32(uint256(LOCK_MEMORY_SLOT)));      // Load memory slot containing locked flag
            assert(
                uint256(tLocked) == 1                                              && cmpStr(errmsg, "DssVest/system-locked")    ||
                tVest.wards(address(this)) == 0 && mgr != address(this)            && cmpStr(errmsg, "DssVest/not-authorized")   ||
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
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        try tVest.move(id, dst) {
            assert(tVest.usr(id) == dst);
            _mutusr(id);
        } catch Error(string memory errmsg) {
            bytes32 tLocked = hevm.load(address(tVest), bytes32(uint256(LOCK_MEMORY_SLOT)));      // Load memory slot containing locked flag
            assert(
                uint256(tLocked) == 1           && cmpStr(errmsg, "DssVest/system-locked")       ||
                tVest.usr(id) != address(this)  && cmpStr(errmsg, "DssVest/only-user-can-move")  ||
                dst == address(0)               && cmpStr(errmsg, "DssVest/zero-address-invalid")
            );
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    // --- Time-Based Fuzz Mutations ---

    function mutlock() private clock(1 hours) {
        bytes32 tLocked = hevm.load(address(tVest), bytes32(uint256(LOCK_MEMORY_SLOT)));          // Load memory slot 0x4
        uint256 locked = uint256(tLocked) == 0 ? 1 : 0;
        // Set DssVestTransferrable locked slot to override 0 with 1 and vice versa
        hevm.store(address(tVest), bytes32(uint256(LOCK_MEMORY_SLOT)), bytes32(uint256(locked)));
        tLocked = hevm.load(address(tVest), bytes32(uint256(LOCK_MEMORY_SLOT)));
        assert(uint256(tLocked) == locked);
    }
    function mutauth() private clock(1 hours) {
        uint256 wards = tVest.wards(address(this)) == 1 ? 0 : 1;
        // Set DssVestTransferrable wards slot to override address(this) wards
        hevm.store(address(tVest), keccak256(abi.encode(address(this), uint256(WARDS_MEMORY_SLOT))), bytes32(uint256(wards)));
        assert(tVest.wards(address(this)) == wards);
    }
    function mutusr(uint256 id) private clock(1 days) {
        id = tVest.ids() == 0 ? 0 : id % tVest.ids();
        if (id == 0) return;
        _mutusr(id);
    }
    function _mutusr(uint256 id) internal {
        address usr = tVest.usr(id) == address(this) ? address(0) : address(this);
        // Set DssVestTrasferrable awards slot (clf, bgn, usr) to override awards(id).usr with address(this)
        hevm.store(address(tVest), keccak256(abi.encode(uint256(id), uint256(AWARDS_MEMORY_SLOT))), bytesToBytes32(abi.encodePacked(uint48(tVest.clf(id)), uint48(tVest.bgn(id)), usr)));
        assert(tVest.usr(id) == usr);
    }
    function mutcap(uint256 bump) private clock(90 days) {
        bump %= MAX;
        if (bump == 0) return;
        uint256 data = bump > MIN ? bump * WAD / TIME : MIN * WAD / TIME;
        // Set DssVestTransferrable cap slot to override cap with data
        hevm.store(address(tVest), bytes32(uint256(CAP_MEMORY_SLOT)), bytes32(uint256(data)));
        assert(tVest.cap() == data);
    }
}
