// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.12;

import "ds-test/test.sol";

import "./DssVest.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external;
}

interface GemLike {
    function approve(address, uint256) external returns (bool);
}

interface GovGuard {
    function wards(address) external returns (uint256);
}

interface Token {
    function balanceOf(address) external returns (uint256);
}

interface VatLikeTest {
    function wards(address) external view returns (uint256);
    function sin(address) external view returns (uint256);
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
    Hevm hevm;
    DssVestMintable      mVest;
    DssVestSuckable      sVest;
    DssVestTransferrable tVest;
    Manager boss;

    address constant MKR_TOKEN = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    address constant VAT = 0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B;
    address constant DAI_JOIN = 0x9759A6Ac90977b93B58547b4A71c78317f391A28;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant VOW = 0xA950524441892A31ebddF91d3cEEFa04Bf454466;
    uint256 constant WAD = 10**18;
    uint256 constant RAY = 10**27;
    uint256 constant days_vest = WAD;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    address GOV_GUARD = 0x6eEB68B2C7A918f36B78E2DB80dcF279236DDFb8;

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));
        mVest = new DssVestMintable(MKR_TOKEN);
        mVest.file("cap", (2000 * WAD) / (4 * 365 days));
        sVest = new DssVestSuckable(CHAINLOG);
        sVest.file("cap", (2000 * WAD) / (4 * 365 days));
        boss = new Manager();
        tVest = new DssVestTransferrable(address(boss), address(DAI));
        tVest.file("cap", (2000 * WAD) / (4 * 365 days));
        boss.gemApprove(address(DAI), address(tVest));

        // Set testing contract as a MKR Auth
        hevm.store(
            address(GOV_GUARD),
            keccak256(abi.encode(address(mVest), uint256(1))),
            bytes32(uint256(1))
        );
        assertEq(GovGuard(GOV_GUARD).wards(address(mVest)), 1);

        // Give admin access to vat
        hevm.store(
            address(VAT),
            keccak256(abi.encode(address(sVest), uint256(0))),
            bytes32(uint256(1))
        );
        assertEq(VatLikeTest(VAT).wards(address(sVest)), 1);

        // Give boss 10000 DAI
        hevm.store(
            address(DAI),
            keccak256(abi.encode(address(boss), uint(2))),
            bytes32(uint256(10000 * WAD))
        );
        assertEq(Token(DAI).balanceOf(address(boss)), 10000 * WAD);
    }

    function testCost() public {
        new DssVestMintable(MKR_TOKEN);
    }

    function testInit() public {
        mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(1));
        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 amt, uint128 rxd) = mVest.awards(1);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now);
        assertEq(uint256(clf), now);
        assertEq(uint256(fin), now + 100 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(mgr, address(1));
    }

    function testVest() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));

        hevm.warp(now + 10 days);

        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 amt, uint128 rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 0);

        mVest.vest(id);
        (usr, bgn, clf, fin, mgr,, amt, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 10 * days_vest);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 10 * days_vest);

        hevm.warp(now + 70 days);

        mVest.vest(id, type(uint256).max);
        (usr, bgn, clf, fin, mgr,, amt, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 80 days);
        assertEq(uint256(fin), now + 20 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 80 * days_vest);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 80 * days_vest);
    }

    function testFailVestNonExistingAward() public {
        mVest.vest(9999);
    }

    function testVestInsideCliff() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 50 days, address(0));

        hevm.warp(now + 10 days);

        mVest.vest(id); // vest is inside cliff, no payout should happen
        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 amt, uint128 rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(clf), now + 40 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(mgr, address(0));
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 0);
    }

    function testVestAfterTimeout() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));

        hevm.warp(now + 200 days);

        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 amt, uint128 rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 200 days);
        assertEq(uint256(fin), now - 100 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 0);

        mVest.vest(id);
        (usr, bgn, clf, fin, mgr,, amt, rxd) = mVest.awards(id);
        // After final payout, vesting information is removed
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 200 days);
        assertEq(uint256(fin), now - 100 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 100 * days_vest);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 100*days_vest);
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
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), days_vest * 4);
        hevm.warp(block.timestamp + 10 days);
        assertEq(mVest.unpaid(id), days_vest * 10);
        mVest.vest(id);
        assertEq(mVest.unpaid(id), 0);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), days_vest * 14);
        hevm.warp(block.timestamp + 120 days);           // vesting complete
        assertEq(mVest.unpaid(id), days_vest * 86);
        mVest.vest(id);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 100 * days_vest);
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
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), days_vest * 4);
        hevm.warp(block.timestamp + 10 days);
        assertEq(mVest.unpaid(id), days_vest * 10);
        assertEq(mVest.accrued(id), days_vest * 14);
        mVest.vest(id);
        assertEq(mVest.unpaid(id), 0);
        assertEq(mVest.accrued(id), days_vest * 14);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), days_vest * 14);
        hevm.warp(block.timestamp + 120 days);       // vesting complete
        assertEq(mVest.unpaid(id), days_vest * 86);
        assertEq(mVest.accrued(id), days_vest * 100);
        mVest.vest(id);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 100 * days_vest);
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
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 0);
        mVest.vest(id);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 2 * days_vest);
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
        (,,, uint48 fin,,, uint128 amt,) = mVest.awards(id);
        assertEq(fin, block.timestamp);
        assertEq(amt, 2 * days_vest);
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 2 days);
        mVest.yank(id); // yank again later
        (,,, fin,,, amt,) = mVest.awards(id);
        assertEq(fin, block.timestamp - 2 days); // fin stays the same as the first yank
        assertEq(amt, 2 * days_vest);   // amt doesn't get updated on second yank
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        mVest.vest(id); // user collects at some future time
        assertTrue(!mVest.valid(id));
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 2 * days_vest);
    }

    function testYankAfterVest() public {
        // Test case where yanked is called after a partial vest
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 1 days, address(0));
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 2 days);
        assertEq(mVest.unpaid(id), 2 * days_vest);
        mVest.vest(id); // collect some now
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 2 * days_vest);

        hevm.warp(block.timestamp + 2 days);
        assertEq(mVest.unpaid(id), 2 * days_vest);
        assertEq(mVest.accrued(id), 4 * days_vest);

        mVest.yank(id); // yank 4 days after start
        (,,, uint48 fin,,, uint128 amt,) = mVest.awards(id);
        assertEq(fin, block.timestamp);
        assertEq(amt, 4 * days_vest);
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(mVest.unpaid(id), 2 * days_vest);
        assertEq(mVest.accrued(id), 4 * days_vest);
        mVest.vest(id); // user collects at some future time
        assertTrue(!mVest.valid(id));
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 4 * days_vest);
    }

    function testYankSchedulePassed() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 20 days, address(0));

        hevm.warp(block.timestamp + 51 days);

        mVest.yank(id, now - 10 days); // Try to yank before cliff

        (,,, uint48 fin,,, uint128 amt,) = mVest.awards(id);
        assertEq(fin, block.timestamp);
        assertEq(amt, 51 * days_vest);   // amt is total amount
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(mVest.unpaid(id), 51 * days_vest);
        assertEq(mVest.accrued(id), 51 * days_vest);
        mVest.vest(id); // user collects at some future time
        assertTrue(!mVest.valid(id));
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 51 * days_vest);
    }

    function testYankScheduleFutureAfterCliff() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 20 days, address(0));

        hevm.warp(block.timestamp + 11 days);

        mVest.yank(id, now + 10 days); // Schedule yank after cliff

        (,,, uint48 fin,,, uint128 amt,) = mVest.awards(id);
        assertEq(fin, block.timestamp + 10 days);
        assertEq(uint256(amt), 21 * days_vest);   // amt is total amount
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(mVest.unpaid(id), 21 * days_vest);
        assertEq(mVest.accrued(id), 21 * days_vest);
        mVest.vest(id); // user collects at some future time
        assertTrue(!mVest.valid(id));
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 21 * days_vest);
    }

    function testYankScheduleFutureBeforeCliff() public {
        // Test case where yank is scheduled but before the cliff
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 20 days, address(0));
        mVest.yank(id, now + 10 days); // Schedule yank before cliff

        (,,, uint48 fin,,, uint128 amt,) = mVest.awards(id);
        assertEq(fin, block.timestamp + 10 days);
        assertEq(uint256(amt), 0);   // amt is total amount
        assertTrue(!mVest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(mVest.unpaid(id), 0);
        assertEq(mVest.accrued(id), 0);
        mVest.vest(id); // user collects at some future time
        assertTrue(!mVest.valid(id));
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 0);
    }

    function testYankScheduleFutureAfterCompletion() public {
        // When the sheduled yank takes place after the natural conclusion of the vest,
        //  Pay out the remainder of the contract and no more.
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 20 days, address(0));

        hevm.warp(block.timestamp + 11 days);

        mVest.yank(id, now + 999 days); // Schedule yank after completion

        (,,, uint48 fin,,, uint128 amt,) = mVest.awards(id);
        assertEq(fin, block.timestamp + 89 days);
        assertEq(uint256(amt), 100 * days_vest);   // amt is total amount
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(mVest.unpaid(id), 100 * days_vest);
        assertEq(mVest.accrued(id), 100 * days_vest);
        mVest.vest(id); // user collects at some future time
        assertTrue(!mVest.valid(id));
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 100 * days_vest);
    }

    function testMgrYank() public {
        Manager manager = new Manager();
        uint256 id1 = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 1 days, address(manager));

        assertTrue(mVest.valid(id1));
        hevm.warp(block.timestamp + 30 days);
        manager.yank(address(mVest), id1);
        assertTrue(mVest.valid(id1));
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 0);
        mVest.vest(id1);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 30 * days_vest);
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

        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 amt, uint128 rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 0);

        alice.vest(address(mVest), id);

        (usr, bgn, clf, fin, mgr,, amt, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 10 * days_vest);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 10 * days_vest);

        hevm.warp(now + 70 days);

        alice.vest(address(mVest), id);
        (usr, bgn, clf, fin, mgr,, amt, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 80 days);
        assertEq(uint256(fin), now + 20 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 80 * days_vest);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 80 * days_vest);
    }

    function testFailRestrictedVest() public {
        ThirdPartyVest alice = new ThirdPartyVest();
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));

        hevm.warp(now + 10 days);

        (address usr, uint48 bgn,, uint48 fin,,, uint128 amt, uint128 rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 0);

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

    function testFailAmtTooHigh() public {
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
        uint256 originalSin = VatLikeTest(VAT).sin(VOW);
        uint256 id = sVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0, address(0));
        assertTrue(sVest.valid(id));
        hevm.warp(block.timestamp + 1 days);
        sVest.vest(id);
        assertEq(Token(DAI).balanceOf(address(this)), 1 * days_vest);
        assertEq(VatLikeTest(VAT).sin(VOW), originalSin + 1 * days_vest * RAY);
        hevm.warp(block.timestamp + 9 days);
        sVest.vest(id);
        assertEq(Token(DAI).balanceOf(address(this)), 10 * days_vest);
        assertEq(VatLikeTest(VAT).sin(VOW), originalSin + 10 * days_vest * RAY);
        hevm.warp(block.timestamp + 365 days);
        sVest.vest(id);
        assertEq(Token(DAI).balanceOf(address(this)), 100 * days_vest);
        assertEq(VatLikeTest(VAT).sin(VOW), originalSin + 100 * days_vest * RAY);
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

    function testVestPartialAmt() public {
        uint256 id = mVest.create(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));

        // Partial vesting
        hevm.warp(now + 10 days);

        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 amt, uint128 rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(mVest.unpaid(id), 10 * days_vest);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 0);

        mVest.vest(id, 5 * days_vest);

        (usr, bgn, clf, fin, mgr,, amt, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 5 * days_vest);
        assertEq(mVest.unpaid(id), 5 * days_vest);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 5 * days_vest);

        // Additional partial vesting calls, up to the entire amount owed at this time
        mVest.vest(id, 3 * days_vest);

        (usr, bgn, clf, fin, mgr,, amt, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 8 * days_vest);
        assertEq(mVest.unpaid(id), 2 * days_vest);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 8 * days_vest);

        mVest.vest(id, 2 * days_vest);

        (usr, bgn, clf, fin, mgr,, amt, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 10 * days_vest);
        assertEq(mVest.unpaid(id), 0);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 10 * days_vest);

        // Another partial vesting after subsequent elapsed time
        hevm.warp(now + 40 days);

        (usr, bgn, clf, fin, mgr,, amt, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 50 days);
        assertEq(uint256(fin), now + 50 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 10 * days_vest);
        assertEq(mVest.unpaid(id), 40 * days_vest);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 10 * days_vest);

        mVest.vest(id, 20 * days_vest);

        (usr, bgn, clf, fin, mgr,, amt, rxd) = mVest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 50 days);
        assertEq(uint256(fin), now + 50 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 30 * days_vest);
        assertEq(mVest.unpaid(id), 20 * days_vest);
        assertEq(Token(address(mVest.gem())).balanceOf(address(this)), 30 * days_vest);
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
        assertEq(Token(DAI).balanceOf(address(usr)), 1 * days_vest);
        assertEq(Token(DAI).balanceOf(address(boss)), 10000 * WAD - 1 * days_vest);
        hevm.warp(block.timestamp + 9 days);
        tVest.vest(id);
        assertEq(Token(DAI).balanceOf(address(usr)), 10 * days_vest);
        assertEq(Token(DAI).balanceOf(address(boss)), 10000 * WAD - 10 * days_vest);
        hevm.warp(block.timestamp + 365 days);
        tVest.vest(id);
        assertEq(Token(DAI).balanceOf(address(usr)), 100 * days_vest);
        assertEq(Token(DAI).balanceOf(address(boss)), 10000 * WAD - 100 * days_vest);
        hevm.warp(block.timestamp + 365 days);
        tVest.vest(id);
        assertEq(Token(DAI).balanceOf(address(usr)), 100 * days_vest);
        assertEq(Token(DAI).balanceOf(address(boss)), 10000 * WAD - 100 * days_vest);
    }
}
