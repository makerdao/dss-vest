// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.6.12;

import "../src/DssVest.sol";
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

    // Hevm
    Hevm hevm;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE = bytes20(uint160(uint256(keccak256("hevm cheat code"))));

    constructor() public {
        gem = new Dai(1);
        multisig = new Multisig();
        gem.mint(address(multisig), uint128(-1));
        tVest = new DssVestTransferrable(address(multisig), address(gem));
        tVest.file("cap", 500 * WAD / 365 days);
        multisig.approve(address(gem), address(tVest));
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

    function create(address usr, uint256 tot, uint256 bgn, uint256 tau, uint256 eta, address mgr) public {
        uint256 prevId = tVest.ids();
        try tVest.create(usr, tot, bgn, tau, eta, mgr) returns (uint256 id) {
            assert(tVest.ids() == add(prevId, 1));
            assert(tVest.ids() == id);
            assert(tVest.valid(id));
            assert(tVest.usr(id) == usr);
            assert(tVest.bgn(id) == toUint48(bgn));
            assert(tVest.clf(id) == toUint48(add(bgn, eta)));
            assert(tVest.fin(id) == toUint48(add(bgn, tau)));
            assert(tVest.tot(id) == toUint128(tot));
            assert(tVest.rxd(id) == 0);
            assert(tVest.mgr(id) == mgr);
            assert(tVest.res(id) == 0);
            // Set DssVestTransferrable awards slot n. 2 (clf, bgn, usr) to override awards(id).usr with address(this)
            hevm.store(address(tVest), keccak256(abi.encode(uint256(id), uint256(2))), bytesToBytes32(abi.encodePacked(uint48(tVest.clf(id)), uint48(tVest.bgn(id)), address(this))));
            assert(tVest.usr(id) == address(this));
        } catch Error(string memory errmsg) {
            assert(
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
        Award memory award = Award({
            usr: tVest.usr(id),
            bgn: toUint48(tVest.bgn(id)),
            clf: toUint48(tVest.clf(id)),
            fin: toUint48(tVest.fin(id)),
            mgr: tVest.mgr(id),
            res: toUint8(tVest.res(id)),
            tot: toUint128(tVest.tot(id)),
            rxd: toUint128(tVest.rxd(id))
        });
        uint256 unpaidAmt = unpaid(block.timestamp, award.bgn, award.clf, award.fin, award.tot, award.rxd);
        uint256 msigBalanceBefore = gem.balanceOf(address(multisig));
        uint256 usrBalanceBefore = gem.balanceOf(award.usr);
        uint256 supplyBefore = gem.totalSupply();
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
                    assert(tVest.rxd(id) == toUint128(add(award.rxd, unpaidAmt)));
                }
                assert(gem.balanceOf(address(multisig)) == sub(msigBalanceBefore, unpaidAmt));
                assert(gem.balanceOf(award.usr) == add(usrBalanceBefore, unpaidAmt));
            }
            assert(gem.totalSupply() == supplyBefore);
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
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        Award memory award = Award({
            usr: tVest.usr(id),
            bgn: toUint48(tVest.bgn(id)),
            clf: toUint48(tVest.clf(id)),
            fin: toUint48(tVest.fin(id)),
            mgr: tVest.mgr(id),
            res: toUint8(tVest.res(id)),
            tot: toUint128(tVest.tot(id)),
            rxd: toUint128(tVest.rxd(id))
        });
        uint256 unpaidAmt = unpaid(block.timestamp, award.bgn, award.clf, award.fin, award.tot, award.rxd);
        uint256 amt = maxAmt > unpaidAmt ? unpaidAmt : maxAmt;
        uint256 msigBalanceBefore = gem.balanceOf(address(multisig));
        uint256 usrBalanceBefore = gem.balanceOf(award.usr);
        uint256 supplyBefore = gem.totalSupply();
        try tVest.vest(id, maxAmt) {
            if (block.timestamp < award.clf) {
                assert(tVest.rxd(id) == award.rxd);
                assert(gem.balanceOf(address(multisig)) == msigBalanceBefore);
                assert(gem.balanceOf(award.usr) == usrBalanceBefore);
            }
            else {
                assert(tVest.rxd(id) == toUint128(add(award.rxd, amt)));
                assert(gem.balanceOf(address(multisig)) == sub(msigBalanceBefore, amt));
                assert(gem.balanceOf(award.usr) == add(usrBalanceBefore, amt));
            }
            assert(gem.totalSupply() == supplyBefore);
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
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        try tVest.restrict(id) {
            assert(tVest.res(id) == 1);
        } catch Error(string memory errmsg) {
            assert(tVest.usr(id) == address(0) && cmpStr(errmsg, "DssVest/invalid-award"));
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function unrestrict(uint256 id) public {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        try tVest.unrestrict(id) {
            assert(tVest.res(id) == 0);
        } catch Error(string memory errmsg) {
            assert(tVest.usr(id) == address(0) && cmpStr(errmsg, "DssVest/invalid-award"));
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }

    function yank(uint256 id, uint256 end) public {
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = tVest.awards(id);
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
                    assert(tVest.tot(id) == toUint128(
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
        id = tVest.ids() == 0 ? id : id % tVest.ids();
        address dst = tVest.usr(id) == address(this) ? msg.sender : address(0);
        try tVest.move(id, dst) {
            assert(tVest.usr(id) == dst);
        } catch Error(string memory errmsg) {
            assert(tVest.usr(id) != address(this) && cmpStr(errmsg, "DssVest/only-user-can-move"));
        } catch {
            assert(false); // echidna will fail if other revert cases are caught
        }
    }
}
