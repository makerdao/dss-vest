// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.12;

import "ds-test/test.sol";

import {DssVest, DssVestMintable, DssVestSuckable, DssVestTransferrable} from "./DssVest.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address, bytes32, bytes32) external;
    function load(address, bytes32) external returns (bytes32);
}

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface EndLike {
    function cage() external;
    function thaw() external;
    function wait() external returns (uint256);
    function debt() external returns (uint256);
}

interface GemLike {
    function approve(address, uint256) external returns (bool);
}

interface DaiLike is GemLike {
    function balanceOf(address) external returns (uint256);
}

interface DSTokenLike {
    function balanceOf(address) external returns (uint256);
}

interface MkrAuthorityLike {
    function wards(address) external returns (uint256);
}

interface VatLike {
    function wards(address) external view returns (uint256);
    function sin(address) external view returns (uint256);
    function debt() external view returns (uint256);
    function live() external view returns (uint256);
}

contract Manager {
    function yank(address dssvest, uint256 id) external {
        DssVest(dssvest).yank(id);
    }

    function gemApprove(address gem, address spender) external {
        GemLike(gem).approve(spender, type(uint256).max);
    }
}

contract ThirdPartyVest {
    function vest(address dssvest, uint256 id) external {
        DssVest(dssvest).vest(id);
    }
}

contract User {
    function vest(address dssvest, uint256 id) external {
        DssVest(dssvest).vest(id);
    }

    function restrict(address dssvest, uint256 id) external {
        DssVest(dssvest).restrict(id);
    }

    function unrestrict(address dssvest, uint256 id) external {
        DssVest(dssvest).unrestrict(id);
    }
}

contract DssVestTest is DSTest {
    // --- Math ---
    uint256 constant WAD = 10**18;
    uint256 constant RAY = 10**27;
    uint256 constant days_vest = WAD;

    // --- Hevm ---
    Hevm hevm;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    DssVestMintable          mVest;
    DssVestSuckable          sVest;
    DssVestTransferrable     tVest;
    Manager                   boss;

    ChainlogLike          chainlog;
    DSTokenLike                gem;
    MkrAuthorityLike     authority;
    VatLike                    vat;
    DaiLike                    dai;
    EndLike                    end;

    address                    VOW;

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));

         chainlog = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
              gem = DSTokenLike    (      chainlog.getAddress("MCD_GOV"));
        authority = MkrAuthorityLike(     chainlog.getAddress("GOV_GUARD"));
              vat = VatLike(              chainlog.getAddress("MCD_VAT"));
              dai = DaiLike(              chainlog.getAddress("MCD_DAI"));
              end = EndLike(              chainlog.getAddress("MCD_END"));
              VOW =                       chainlog.getAddress("MCD_VOW");

        mVest = new DssVestMintable(address(gem));
        mVest.file("cap", (2000 * WAD) / (4 * 365 days));
        sVest = new DssVestSuckable(address(chainlog));
        sVest.file("cap", (2000 * WAD) / (4 * 365 days));
        boss = new Manager();
        tVest = new DssVestTransferrable(address(boss), address(dai));
        tVest.file("cap", (2000 * WAD) / (4 * 365 days));
        boss.gemApprove(address(dai), address(tVest));


        // Set testing contract as a MKR Auth
        hevm.store(
            address(authority),
            keccak256(abi.encode(address(mVest), uint256(1))),
            bytes32(uint256(1))
        );
        assertEq(authority.wards(address(mVest)), 1);

        // Give admin access to vat
        hevm.store(
            address(vat),
            keccak256(abi.encode(address(sVest), uint256(0))),
            bytes32(uint256(1))
        );
        assertEq(vat.wards(address(sVest)), 1);

        // Give boss 10000 DAI
        hevm.store(
            address(dai),
            keccak256(abi.encode(address(boss), uint(2))),
            bytes32(uint256(10000 * WAD))
        );
        assertEq(dai.balanceOf(address(boss)), 10000 * WAD);
    }

    function testCost() public {
        new DssVestMintable(address(gem));
    }

    function testInit() public {
        mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(1));
        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 tot, uint128 rxd) = mVest.awards(1);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now);
        assertEq(uint256(clf), now);
        assertEq(uint256(fin), now + 100 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(mgr, address(1));
    }

    function testVest() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));

        hevm.warp(now + 10 days);

        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 tot, uint128 rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(gem.balanceOf(address(this)), 0);

        mVest.vest(id);
        (usr, bgn, clf, fin, mgr,, tot, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 10 * days_vest);
        assertEq(gem.balanceOf(address(this)), 10 * days_vest);

        hevm.warp(now + 70 days);

        mVest.vest(id, type(uint256).max);
        (usr, bgn, clf, fin, mgr,, tot, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 80 days);
        assertEq(uint256(fin), now + 20 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 80 * days_vest);
        assertEq(gem.balanceOf(address(this)), 80 * days_vest);
    }

    function testFailVestNonExistingAward() public {
        mVest.vest(9999);
    }

    function testVestInsideCliff() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 50 days, address(0));

        hevm.warp(now + 10 days);

        mVest.vest(id); // vest is inside cliff, no payout should happen
        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 tot, uint128 rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(clf), now + 40 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(mgr, address(0));
        assertEq(gem.balanceOf(address(this)), 0);
    }

    function testVestAfterTimeout() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));

        hevm.warp(now + 200 days);

        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 tot, uint128 rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 200 days);
        assertEq(uint256(fin), now - 100 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(gem.balanceOf(address(this)), 0);

        mVest.vest(id);
        (usr, bgn, clf, fin, mgr,, tot, rxd) = mVest.awards(id);
        // After final payout, vesting information is removed
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 200 days);
        assertEq(uint256(fin), now - 100 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 100 * days_vest);
        assertEq(gem.balanceOf(address(this)), 100*days_vest);
        assertTrue(!mVest.valid(id));
    }

    function testMove() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));
        mVest.move(id, address(3));

        (address usr,,,,,,,) = mVest.awards(id);
        assertEq(usr, address(3));
    }

    function testFailMoveToZeroAddress() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));
        mVest.move(id, address(0));
    }

    function testUnpaid() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 1 days, address(0));
        assertTrue(mVest.valid(id));

        assertEq(mVest.unpaid(id), 0);
        hevm.warp(block.timestamp + 43200);
        assertEq(mVest.unpaid(id), 0);                   // inside cliff
        hevm.warp(block.timestamp + 36 hours);
        assertEq(mVest.unpaid(id), days_vest * 2);       // past cliff
        hevm.warp(block.timestamp + 2 days);
        assertEq(mVest.unpaid(id), days_vest * 4);       // past cliff
        mVest.vest(id);
        assertEq(mVest.unpaid(id), 0);
        assertEq(gem.balanceOf(address(this)), days_vest * 4);
        hevm.warp(block.timestamp + 10 days);
        assertEq(mVest.unpaid(id), days_vest * 10);
        mVest.vest(id);
        assertEq(mVest.unpaid(id), 0);
        assertEq(gem.balanceOf(address(this)), days_vest * 14);
        hevm.warp(block.timestamp + 120 days);           // vesting complete
        assertEq(mVest.unpaid(id), days_vest * 86);
        mVest.vest(id);
        assertEq(gem.balanceOf(address(this)), 100 * days_vest);
    }

    function testAccrued() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp + 10 days, 100 days, 0, address(0));
        assertTrue(mVest.valid(id));

        assertEq(mVest.accrued(id), 0);
        hevm.warp(block.timestamp + 43200);
        assertEq(mVest.unpaid(id), 0);                   // inside cliff
        assertEq(mVest.accrued(id), 0);
        hevm.warp(block.timestamp + 12 hours + 11 days);
        assertEq(mVest.unpaid(id), days_vest * 2);       // past cliff
        assertEq(mVest.accrued(id), days_vest * 2);
        hevm.warp(block.timestamp + 2 days);
        assertEq(mVest.unpaid(id), days_vest * 4);       // past cliff
        assertEq(mVest.accrued(id), days_vest * 4);
        mVest.vest(id);
        assertEq(mVest.unpaid(id), 0);
        assertEq(mVest.accrued(id), days_vest * 4);
        assertEq(gem.balanceOf(address(this)), days_vest * 4);
        hevm.warp(block.timestamp + 10 days);
        assertEq(mVest.unpaid(id), days_vest * 10);
        assertEq(mVest.accrued(id), days_vest * 14);
        mVest.vest(id);
        assertEq(mVest.unpaid(id), 0);
        assertEq(mVest.accrued(id), days_vest * 14);
        assertEq(gem.balanceOf(address(this)), days_vest * 14);
        hevm.warp(block.timestamp + 120 days);           // vesting complete
        assertEq(mVest.unpaid(id), days_vest * 86);
        assertEq(mVest.accrued(id), days_vest * 100);
        mVest.vest(id);
        assertEq(gem.balanceOf(address(this)), 100 * days_vest);
    }

    function testFutureAccrual() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp + 10 days, 100 days, 0, address(0));
        assertEq(mVest.accrued(id), 0);               // accrual starts in 10 days
        hevm.warp(block.timestamp + 9 days);
        assertEq(mVest.accrued(id), 0);               // accrual starts in 1 days
        hevm.warp(block.timestamp + 2 days);
        assertEq(mVest.accrued(id), days_vest);       // accrual started 1 day ago
        hevm.warp(block.timestamp + 999 days);
        assertEq(mVest.accrued(id), days_vest * 100); // accrual ended
    }

    function testYank() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 1 days, address(0));
        assertTrue(mVest.valid(id));
        mVest.yank(id); // yank before cliff
        assertTrue(!mVest.valid(id));

        id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 1 days, address(0));
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 2 days);
        mVest.yank(id); // yank after cliff
        (, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot,) = mVest.awards(id);
        assertEq(bgn, block.timestamp - 2 days);
        assertEq(clf, block.timestamp - 1 days);
        assertEq(fin, block.timestamp);
        assertEq(uint256(tot), 100 * days_vest * 2 / 100);
        assertTrue(mVest.valid(id));
        assertEq(gem.balanceOf(address(this)), 0);
        mVest.vest(id);
        assertEq(gem.balanceOf(address(this)), 2 * days_vest);
        assertTrue(!mVest.valid(id));
    }

    function testYankInsideCliff() public {
        Manager manager = new Manager();
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 50 days, address(manager));

        hevm.warp(block.timestamp + 10 days);

        manager.yank(address(mVest), id);

        (, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot,) = mVest.awards(id);

        assertEq(bgn, block.timestamp - 10 days);
        assertEq(clf, block.timestamp);
        assertEq(fin, block.timestamp);
        assertEq(uint256(tot), 0);

        assertTrue(!mVest.valid(id));
    }

    function testYankBeforeBgn() public {
        Manager manager = new Manager();
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp + 10 days, 100 days, 50 days, address(manager));

        hevm.warp(block.timestamp + 5 days);

        manager.yank(address(mVest), id);

        (, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot,) = mVest.awards(id);

        assertEq(bgn, block.timestamp);
        assertEq(clf, block.timestamp);
        assertEq(fin, block.timestamp);
        assertEq(uint256(tot), 0);

        assertTrue(!mVest.valid(id));
    }

    function testDoubleYank() public {
        // Test case where vest is yanked twice, say by manager and then governance
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 1 days, address(0));
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 2 days);
        mVest.yank(id); // accrued two days before yank
        (,,, uint48 fin,,, uint128 tot,) = mVest.awards(id);
        assertEq(fin, block.timestamp);
        assertEq(tot, 2 * days_vest);
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 2 days);
        mVest.yank(id); // yank again later
        (,,, fin,,, tot,) = mVest.awards(id);
        assertEq(fin, block.timestamp - 2 days); // fin stays the same as the first yank
        assertEq(tot, 2 * days_vest);   // tot doesn't get updated on second yank
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        mVest.vest(id); // user collects at some future time
        assertTrue(!mVest.valid(id));
        assertEq(gem.balanceOf(address(this)), 2 * days_vest);
    }

    function testYankAfterVest() public {
        // Test case where yanked is called after a partial vest
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 1 days, address(0));
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 2 days);
        assertEq(mVest.unpaid(id), 2 * days_vest);
        mVest.vest(id); // collect some now
        assertEq(gem.balanceOf(address(this)), 2 * days_vest);

        hevm.warp(block.timestamp + 2 days);
        assertEq(mVest.unpaid(id), 2 * days_vest);
        assertEq(mVest.accrued(id), 4 * days_vest);

        mVest.yank(id); // yank 4 days after start
        (,,, uint48 fin,,, uint128 tot,) = mVest.awards(id);
        assertEq(fin, block.timestamp);
        assertEq(tot, 4 * days_vest);
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(mVest.unpaid(id), 2 * days_vest);
        assertEq(mVest.accrued(id), 4 * days_vest);
        mVest.vest(id); // user collects at some future time
        assertTrue(!mVest.valid(id));
        assertEq(gem.balanceOf(address(this)), 4 * days_vest);
    }

    function testYankSchedulePassed() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 20 days, address(0));

        hevm.warp(block.timestamp + 51 days);

        mVest.yank(id, now - 10 days); // Try to yank before cliff

        (,,, uint48 fin,,, uint128 tot,) = mVest.awards(id);
        assertEq(fin, block.timestamp);
        assertEq(tot, 51 * days_vest);   // tot is total amount
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(mVest.unpaid(id), 51 * days_vest);
        assertEq(mVest.accrued(id), 51 * days_vest);
        mVest.vest(id); // user collects at some future time
        assertTrue(!mVest.valid(id));
        assertEq(gem.balanceOf(address(this)), 51 * days_vest);
    }

    function testYankScheduleFutureAfterCliff() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 20 days, address(0));

        hevm.warp(block.timestamp + 11 days);

        mVest.yank(id, now + 10 days); // Schedule yank after cliff

        (,,, uint48 fin,,, uint128 tot,) = mVest.awards(id);
        assertEq(fin, block.timestamp + 10 days);
        assertEq(uint256(tot), 21 * days_vest);   // tot is total amount
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(mVest.unpaid(id), 21 * days_vest);
        assertEq(mVest.accrued(id), 21 * days_vest);
        mVest.vest(id); // user collects at some future time
        assertTrue(!mVest.valid(id));
        assertEq(gem.balanceOf(address(this)), 21 * days_vest);
    }

    function testYankScheduleFutureBeforeCliff() public {
        // Test case where yank is scheduled but before the cliff
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 20 days, address(0));
        mVest.yank(id, now + 10 days); // Schedule yank before cliff

        (,,, uint48 fin,,, uint128 tot,) = mVest.awards(id);
        assertEq(fin, block.timestamp + 10 days);
        assertEq(uint256(tot), 0);   // tot is total amount
        assertTrue(!mVest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(mVest.unpaid(id), 0);
        assertEq(mVest.accrued(id), 0);
        mVest.vest(id); // user collects at some future time
        assertTrue(!mVest.valid(id));
        assertEq(gem.balanceOf(address(this)), 0);
    }

    function testYankScheduleFutureAfterCompletion() public {
        // When the sheduled yank takes place after the natural conclusion of the vest,
        //  Pay out the remainder of the contract and no more.
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 20 days, address(0));

        hevm.warp(block.timestamp + 11 days);

        mVest.yank(id, now + 999 days); // Schedule yank after completion

        (,,, uint48 fin,,, uint128 tot,) = mVest.awards(id);
        assertEq(fin, block.timestamp + 89 days);
        assertEq(uint256(tot), 100 * days_vest);   // tot is total amount
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(mVest.unpaid(id), 100 * days_vest);
        assertEq(mVest.accrued(id), 100 * days_vest);
        mVest.vest(id); // user collects at some future time
        assertTrue(!mVest.valid(id));
        assertEq(gem.balanceOf(address(this)), 100 * days_vest);
    }

    function testMgrYank() public {
        Manager manager = new Manager();
        uint256 id1 = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 1 days, address(manager));

        assertTrue(mVest.valid(id1));
        hevm.warp(block.timestamp + 30 days);
        manager.yank(address(mVest), id1);
        assertTrue(mVest.valid(id1));
        assertEq(gem.balanceOf(address(this)), 0);
        mVest.vest(id1);
        assertEq(gem.balanceOf(address(this)), 30 * days_vest);
        assertTrue(!mVest.valid(id1));

        uint256 id2 = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 30 days, address(manager));
        assertTrue(id1 != id2);
        assertTrue(mVest.valid(id2));
        manager.yank(address(mVest), id2);
        assertTrue(!mVest.valid(id2));
    }

    function testUnRestrictedVest() public {
        ThirdPartyVest alice = new ThirdPartyVest();
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));

        hevm.warp(now + 10 days);

        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 tot, uint128 rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(gem.balanceOf(address(this)), 0);

        alice.vest(address(mVest), id);

        (usr, bgn, clf, fin, mgr,, tot, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 10 * days_vest);
        assertEq(gem.balanceOf(address(this)), 10 * days_vest);

        hevm.warp(now + 70 days);

        alice.vest(address(mVest), id);
        (usr, bgn, clf, fin, mgr,, tot, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 80 days);
        assertEq(uint256(fin), now + 20 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 80 * days_vest);
        assertEq(gem.balanceOf(address(this)), 80 * days_vest);
    }

    function testFailRestrictedVest() public {
        ThirdPartyVest alice = new ThirdPartyVest();
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));

        hevm.warp(now + 10 days);

        (address usr, uint48 bgn,, uint48 fin,,, uint128 tot, uint128 rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(gem.balanceOf(address(this)), 0);

        mVest.restrict(id);

        alice.vest(address(mVest), id);
    }

    function testRestrictions() public {
        User bob = new User();
        uint256 id = mVest.create(address(bob), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));

        assertEq(mVest.res(id), 0);

        bob.restrict(address(mVest), id);

        assertEq(mVest.res(id), 1);

        bob.vest(address(mVest), id);

        bob.unrestrict(address(mVest), id);

        assertEq(mVest.res(id), 0);

        // also test auth ability
        mVest.restrict(id);

        assertEq(mVest.res(id), 1);

        mVest.unrestrict(id);

        assertEq(mVest.res(id), 0);
    }

    function testFailRestrictNonExistingAward() public {
        mVest.restrict(9999);
    }

    function testFailUnrestrictNonExistingAward() public {
        mVest.unrestrict(9999);
    }

    function testFailMgrYankUnauthed() public {
        Manager manager = new Manager();
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(1));
        manager.yank(address(mVest), id);
    }

    function testLive() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));
        assertTrue(mVest.valid(id));
        assertTrue(!mVest.valid(5));
    }

    function testFailTotTooHigh() public {
        mVest.create(address(this), uint128(-1) + 1, block.timestamp, 100 days, 0 days, address(0));
    }

    function testFailZeroUser() public {
        mVest.create(address(0), 100 * days_vest + 1, block.timestamp, 100 days, 0 days, address(0));
    }

    function testFailStartTooFarInTheFuture() public {
        mVest.create(address(this), 100 * days_vest + 1, block.timestamp + (21 * 365 days), 100 days, 0 days, address(0));
    }

    function testFailStartTooFarInThePast() public {
        mVest.create(address(this), 100 * days_vest + 1, block.timestamp - (21 * 365 days), 100 days, 0 days, address(0));
    }

    function testFailStartTooLong() public {
        mVest.create(address(this), 100 * days_vest + 1, block.timestamp, 21 * 365 days, 0 days, address(0));
    }

    function testFailClfAfterTau() public {
        mVest.create(address(this), 100 * days_vest + 1, block.timestamp, 100 days, 101 days, address(0));
    }

    function testSuckableVest() public {
        uint256 originalSin = vat.sin(VOW);
        uint256 id = sVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0, address(0));
        assertTrue(sVest.valid(id));
        hevm.warp(block.timestamp + 1 days);
        sVest.vest(id);
        assertEq(dai.balanceOf(address(this)), 1 * days_vest);
        assertEq(vat.sin(VOW), originalSin + 1 * days_vest * RAY);
        hevm.warp(block.timestamp + 9 days);
        sVest.vest(id);
        assertEq(dai.balanceOf(address(this)), 10 * days_vest);
        assertEq(vat.sin(VOW), originalSin + 10 * days_vest * RAY);
        hevm.warp(block.timestamp + 365 days);
        sVest.vest(id);
        assertEq(dai.balanceOf(address(this)), 100 * days_vest);
        assertEq(vat.sin(VOW), originalSin + 100 * days_vest * RAY);
    }

    function testSuckableVestCaged() public {
        uint256 originalSin = vat.sin(VOW);
        uint256 id = sVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0, address(0));
        assertTrue(sVest.valid(id));

        hevm.warp(block.timestamp + 1 days);
        sVest.vest(id);
        assertEq(dai.balanceOf(address(this)), 1 * days_vest);
        assertEq(vat.sin(VOW), originalSin + 1 * days_vest * RAY);

        hevm.warp(block.timestamp + 9 days);

        // Get End auth to allow call `cage`
        hevm.store(
            address(end),
            keccak256(abi.encode(address(this), uint256(0))),
            bytes32(uint256(1))
        );
        end.cage();

        uint256 when = block.timestamp;

        try sVest.vest(id) {
            assertTrue(false);
        } catch Error(string memory errmsg) {
            assertTrue(vat.live() == 0 && cmpStr(errmsg, "DssVestSuckable/vat-not-live"));
            assertEq(dai.balanceOf(address(this)), 1 * days_vest);
            assertEq(vat.sin(VOW), 0); // true only if there is more surplus than debt in the system
        } catch {
            assertTrue(false);
        }

        hevm.warp(when + end.wait());
        uint256 vatDebt = vat.debt();

        // Coerce system surplus to zero to allow end `thaw` execution
        hevm.store(
            address(vat),
            keccak256(abi.encode(address(VOW), uint256(5))),
            bytes32(uint256(0))
        );

        end.thaw();

        uint256 endDebt = end.debt();
        assertEq(endDebt, vatDebt);
    }

    function testCap() public {
        // Test init at top limit
        uint256 id = mVest.create(address(this), 500 * WAD, block.timestamp, 365 days, 0, address(0));
        assertEq(id, 1);

        mVest.file("cap", (4000 * WAD) / (4 * 365 days));

        id = mVest.create(address(this), 1000 * WAD, block.timestamp, 365 days, 0, address(0));
        assertEq(id, 2);
    }

    function testFailCap() public {
        // Test failure at 1 over limit
        mVest.create(address(this), 501 * WAD, block.timestamp, 365 days, 0, address(0));
    }

    function testVestPartialTot() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));

        // Partial vesting
        hevm.warp(now + 10 days);

        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 tot, uint128 rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(mVest.unpaid(id), 10 * days_vest);
        assertEq(gem.balanceOf(address(this)), 0);

        mVest.vest(id, 5 * days_vest);

        (usr, bgn, clf, fin, mgr,, tot, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 5 * days_vest);
        assertEq(mVest.unpaid(id), 5 * days_vest);
        assertEq(gem.balanceOf(address(this)), 5 * days_vest);

        // Additional partial vesting calls, up to the entire amount owed at this time
        mVest.vest(id, 3 * days_vest);

        (usr, bgn, clf, fin, mgr,, tot, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 8 * days_vest);
        assertEq(mVest.unpaid(id), 2 * days_vest);
        assertEq(gem.balanceOf(address(this)), 8 * days_vest);

        mVest.vest(id, 2 * days_vest);

        (usr, bgn, clf, fin, mgr,, tot, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 10 * days_vest);
        assertEq(mVest.unpaid(id), 0);
        assertEq(gem.balanceOf(address(this)), 10 * days_vest);

        // Another partial vesting after subsequent elapsed time
        hevm.warp(now + 40 days);

        (usr, bgn, clf, fin, mgr,, tot, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 50 days);
        assertEq(uint256(fin), now + 50 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 10 * days_vest);
        assertEq(mVest.unpaid(id), 40 * days_vest);
        assertEq(gem.balanceOf(address(this)), 10 * days_vest);

        mVest.vest(id, 20 * days_vest);

        (usr, bgn, clf, fin, mgr,, tot, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 50 days);
        assertEq(uint256(fin), now + 50 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 30 * days_vest);
        assertEq(mVest.unpaid(id), 20 * days_vest);
        assertEq(gem.balanceOf(address(this)), 30 * days_vest);
    }

    function testTransferrableVest() public {
        User usr = new User();

        uint256 id = tVest.create(
            address(usr),
            100 * days_vest,
            block.timestamp,
            100 days,
            0,
            address(0)
        );

        assertTrue(tVest.valid(id));
        hevm.warp(block.timestamp + 1 days);
        tVest.vest(id);
        assertEq(dai.balanceOf(address(usr)), 1 * days_vest);
        assertEq(dai.balanceOf(address(boss)), 10000 * WAD - 1 * days_vest);
        hevm.warp(block.timestamp + 9 days);
        tVest.vest(id);
        assertEq(dai.balanceOf(address(usr)), 10 * days_vest);
        assertEq(dai.balanceOf(address(boss)), 10000 * WAD - 10 * days_vest);
        hevm.warp(block.timestamp + 365 days);
        tVest.vest(id);
        assertEq(dai.balanceOf(address(usr)), 100 * days_vest);
        assertEq(dai.balanceOf(address(boss)), 10000 * WAD - 100 * days_vest);
        hevm.warp(block.timestamp + 365 days);
        tVest.vest(id);
        assertEq(dai.balanceOf(address(usr)), 100 * days_vest);
        assertEq(dai.balanceOf(address(boss)), 10000 * WAD - 100 * days_vest);
    }

    function testWardsSlot0x0() public {
        // Load memory slot 0x0
        bytes32 mWards = hevm.load(address(mVest), keccak256(abi.encode(address(this), uint256(0))));
        bytes32 sWards = hevm.load(address(sVest), keccak256(abi.encode(address(this), uint256(0))));
        bytes32 tWards = hevm.load(address(tVest), keccak256(abi.encode(address(this), uint256(0))));

        // mVest wards
        assertEq(mVest.wards(address(this)), uint256(mWards)); // Assert wards = slot wards
        assertEq(uint256(mWards), 1);                          // Assert slot wards == 1

        // sVest wards
        assertEq(sVest.wards(address(this)), uint256(sWards)); // Assert wards = slot wards
        assertEq(uint256(sWards), 1);                          // Assert slot wards == 1

        // tVest wards
        assertEq(tVest.wards(address(this)), uint256(tWards)); // Assert wards = slot wards
        assertEq(uint256(tWards), 1);                          // Assert slot wards == 1
    }

    function testAwardSlot0x1() public {
        uint256 mId = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 10 days, address(0xdead));
        uint256 sId = sVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 10 days, address(0xdead));
        uint256 tId = tVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 10 days, address(0xdead));

        mVest.restrict(mId);
        sVest.restrict(sId);
        tVest.restrict(tId);

        hevm.warp(now + 10 days);

        mVest.vest(mId, 5 * days_vest);
        sVest.vest(sId, 5 * days_vest);
        tVest.vest(tId, 5 * days_vest);

        DssVest.Award memory mmemaward = testUnpackAward(address(mVest), mId);
        DssVest.Award memory smemaward = testUnpackAward(address(sVest), sId);
        DssVest.Award memory tmemaward = testUnpackAward(address(tVest), tId);

        // Assert usr = slot 0x1 offset 0 awards.usr
        assertEq(mVest.usr(mId), mmemaward.usr);
        assertEq(sVest.usr(sId), smemaward.usr);
        assertEq(tVest.usr(tId), tmemaward.usr);

        // Assert bgn = slot 0x1 offset 0 awards.bgn
        assertEq(mVest.bgn(mId), uint256(mmemaward.bgn));
        assertEq(sVest.bgn(sId), uint256(smemaward.bgn));
        assertEq(tVest.bgn(tId), uint256(tmemaward.bgn));

        // Assert clf = slot 0x1 offset 0 awards.clf
        assertEq(mVest.clf(mId), uint256(mmemaward.clf));
        assertEq(sVest.clf(sId), uint256(smemaward.clf));
        assertEq(tVest.clf(tId), uint256(tmemaward.clf));

        // Assert fin = slot 0x1 offset 1 awards.fin
        assertEq(mVest.fin(mId), uint256(mmemaward.fin));
        assertEq(sVest.fin(sId), uint256(smemaward.fin));
        assertEq(tVest.fin(tId), uint256(tmemaward.fin));

        // Assert mgr = slot 0x1 offset 1 awards.mgr
        assertEq(mVest.mgr(mId), mmemaward.mgr);
        assertEq(sVest.mgr(sId), smemaward.mgr);
        assertEq(tVest.mgr(tId), tmemaward.mgr);

        // Assert res = slot 0x1 offset 1 awards.res
        assertEq(mVest.res(mId), uint256(mmemaward.res));
        assertEq(sVest.res(sId), uint256(smemaward.res));
        assertEq(tVest.res(tId), uint256(tmemaward.res));

        // Assert tot = slot 0x1 offset 2 awards.tot
        assertEq(mVest.tot(mId), uint256(mmemaward.tot));
        assertEq(sVest.tot(sId), uint256(smemaward.tot));
        assertEq(tVest.tot(tId), uint256(tmemaward.tot));

        // Assert rxd = slot 0x1 offset 2 awards.rxd
        assertEq(mVest.rxd(mId), uint256(mmemaward.rxd));
        assertEq(sVest.rxd(sId), uint256(smemaward.rxd));
        assertEq(tVest.rxd(tId), uint256(tmemaward.rxd));
    }

    function testUnpackAward(address vest, uint256 id) internal returns (DssVest.Award memory award) {
        // Load memory slot 0x1 offset 0
        bytes32 awardsPacked0x10 = hevm.load(address(vest), keccak256(abi.encode(uint256(id), uint256(1))));

        // Load memory slot 0x1 offset 1
        bytes32 awardsPacked0x11 = hevm.load(address(vest), bytes32(uint256(1) + uint256(keccak256(abi.encode(uint256(id), uint256(1))))));

        // Load memory slot 0x1 offset 2
        bytes32 awardsPacked0x12 = hevm.load(address(vest), bytes32(uint256(2) + uint256(keccak256(abi.encode(uint256(id), uint256(1))))));

        // Unpack memory slot 0x1 offset 0
        bytes20 memusr;
        bytes6  membgn;
        bytes6  memclf;
        assembly {
            memclf := awardsPacked0x10
            membgn := shl(48, awardsPacked0x10)
            memusr := shl(96, awardsPacked0x10)
        }

        // Unpack memory slot 0x1 offset 1
        bytes6  memfin;
        bytes20 memmgr;
        bytes1  memres;
        assembly {
            memres := shl(40, awardsPacked0x11)
            memmgr := shl(48, awardsPacked0x11)
            memfin := shl(208, awardsPacked0x11)
        }

        // Unpack memory slot 0x1 offset 2
        bytes16 memtot;
        bytes16 memrxd;
        assembly {
            memrxd := awardsPacked0x12
            memtot := shl(128, awardsPacked0x12)
        }

        // awards.usr
        assertEq(address(uint160(memusr)), address(this));             // Assert slot awards.usr == address(this)

        // awards.bgn
        assertEq(uint256(uint48(membgn)), block.timestamp - 10 days);  // Assert slot awards.bgn == block.timestamp - 10 days

        // awards.clf
        assertEq(uint256(uint48(memclf)), block.timestamp);            // Assert slot awards.clf == bgn + eta

        // awards.fin
        assertEq(uint256(uint48(memfin)), block.timestamp + 90 days);  // Assert slot awards.fin == bgn + tau

        // awards.mgr
        assertEq(address(uint160(memmgr)), address(0xdead));           // Assert slot awards.mgr == address(0xdead)

        // awards.res
        assertEq(uint256(uint8(memres)), 1);                           // Assert slot awards.res == 1

        // awards.tot
        assertEq(uint256(uint128(memtot)), 100 * days_vest);           // Assert slot awards.tot == 100 * days_vest

        // awards.rxd
        assertEq(uint256(uint128(memrxd)), 5 * days_vest);             // Assert slot awards.rxd == 5 * days_vest

        return (
            DssVest.Award({
                usr: address(uint160(memusr)),
                bgn:  uint48(membgn),
                clf:  uint48(memclf),
                fin:  uint48(memfin),
                mgr: address(uint160(memmgr)),
                res:   uint8(memres),
                tot: uint128(memtot),
                rxd: uint128(memrxd)
            })
        );
    }

    function testCapSlot0x2() public {
        // Load memory slot 0x2
        bytes32 mCap = hevm.load(address(mVest), bytes32(uint256(2)));
        bytes32 sCap = hevm.load(address(sVest), bytes32(uint256(2)));
        bytes32 tCap = hevm.load(address(tVest), bytes32(uint256(2)));

        // mVest cap
        assertEq(mVest.cap(), uint256(mCap));                          // Assert cap = slot cap
        assertEq(uint256(mCap), (2000 * WAD) / (4 * 365 days));        // Assert slot cap == (2000 * WAD) / (4 * 365 days)

        // sVest cap
        assertEq(sVest.cap(), uint256(sCap));                          // Assert cap = slot cap
        assertEq(uint256(sCap), (2000 * WAD) / (4 * 365 days));        // Assert slot cap == (2000 * WAD) / (4 * 365 days)

        // tVest cap
        assertEq(tVest.cap(), uint256(tCap));                          // Assert cap = slot cap
        assertEq(uint256(tCap), (2000 * WAD) / (4 * 365 days));        // Assert slot cap == (2000 * WAD) / (4 * 365 days)
    }

    function testIdsSlot0x3() public {
        mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0, address(0xdead));
        sVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0, address(0xdead));
        tVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0, address(0xdead));

        // Load memory slot 0x3
        bytes32 mIds = hevm.load(address(mVest), bytes32(uint256(3)));
        bytes32 sIds = hevm.load(address(sVest), bytes32(uint256(3)));
        bytes32 tIds = hevm.load(address(tVest), bytes32(uint256(3)));

        // mVest ids
        assertEq(mVest.ids(), uint256(mIds));                          // Assert ids = slot ids
        assertEq(uint256(mIds), 1);                                    // Assert slot ids == 1

        // sVest ids
        assertEq(sVest.ids(), uint256(sIds));                          // Assert ids = slot ids
        assertEq(uint256(sIds), 1);                                    // Assert slot ids == 1

        // tVest ids
        assertEq(tVest.ids(), uint256(tIds));                          // Assert ids = slot ids
        assertEq(uint256(tIds), 1);                                    // Assert slot ids == 1
    }

    function cmpStr(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
    function testLockedSlot0x4() public {
        // Store memory slot 0x4
        hevm.store(address(mVest), bytes32(uint256(4)), bytes32(uint256(1)));
        hevm.store(address(sVest), bytes32(uint256(4)), bytes32(uint256(1)));
        hevm.store(address(tVest), bytes32(uint256(4)), bytes32(uint256(1)));

        // mVest locked
        try mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0, address(0xdead)) {}
        catch Error(string memory errmsg) {
            bytes32 mLocked = hevm.load(address(mVest), bytes32(uint256(4)));             // Load memory slot 0x4
            assertTrue(uint256(mLocked) == 1 && cmpStr(errmsg, "DssVest/system-locked")); // Assert slot locked == 1 and function reverts
        }

        // sVest locked
        try sVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0, address(0xdead)) {}
        catch Error(string memory errmsg) {
            bytes32 sLocked = hevm.load(address(sVest), bytes32(uint256(4)));             // Load memory slot 0x4
            assertTrue(uint256(sLocked) == 1 && cmpStr(errmsg, "DssVest/system-locked")); // Assert slot locked == 1 and function reverts
        }

        // tVest locked
        try tVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0, address(0xdead)) {}
        catch Error(string memory errmsg) {
            bytes32 tLocked = hevm.load(address(tVest), bytes32(uint256(4)));             // Load memory slot 0x4
            assertTrue(uint256(tLocked) == 1 && cmpStr(errmsg, "DssVest/system-locked")); // Assert slot locked == 1 and function reverts
        }
    }
}
