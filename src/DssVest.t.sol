// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.12;

import "ds-test/test.sol";

import "./DssVest.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external;
}

interface GovGuard {
    function wards(address) external returns (uint256);
}

interface Token {
    function balanceOf(address) external returns (uint256);
}

contract Manager {
    function yank(address dssvest, uint256 id) external {
        DssVest(dssvest).yank(id);
    }
}

contract DssVestTest is DSTest {
    Hevm hevm;
    DssVest vest;

    address constant MKR_TOKEN = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    uint256 constant WAD = 10**18;
    uint256 constant days_vest = WAD;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    address GOV_GUARD = 0x6eEB68B2C7A918f36B78E2DB80dcF279236DDFb8;

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));
        vest = new DssVest(MKR_TOKEN);

        // Set testing contract as a MKR Auth
        hevm.store(
            address(GOV_GUARD),
            keccak256(abi.encode(address(vest), uint256(1))),
            bytes32(uint256(1))
        );
        assertEq(GovGuard(GOV_GUARD).wards(address(vest)), 1);
    }

    function testCost() public {
        new DssVest(MKR_TOKEN);
    }

    function testInit() public {
        vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(1));
        (address usr, uint48 bgn, uint48 clf, uint48 fin, uint128 amt, uint128 rxd, address mgr) = vest.awards(1);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now);
        assertEq(uint256(clf), now);
        assertEq(uint256(fin), now + 100 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(mgr, address(1));
    }

    function testVest() public {
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));

        hevm.warp(now + 10 days);

        (address usr, uint48 bgn, uint48 clf, uint48 fin, uint128 amt, uint128 rxd, address mgr) = vest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 0);

        vest.vest(id);
        (usr, bgn, clf, fin, amt, rxd, mgr) = vest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 10 * days_vest);
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 10 * days_vest);

        hevm.warp(now + 70 days);

        vest.vest(id);
        (usr, bgn, clf, fin, amt, rxd, mgr) = vest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 80 days);
        assertEq(uint256(fin), now + 20 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 80 * days_vest);
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 80 * days_vest);
    }

    function testVestInsideCliff() public {
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 50 days, address(0));

        hevm.warp(now + 10 days);

        vest.vest(id); // vest is inside cliff, no payout should happen
        (address usr, uint48 bgn, uint48 clf, uint48 fin, uint128 amt, uint128 rxd, address mgr) = vest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(clf), now + 40 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(mgr, address(0));
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 0);
    }

    function testVestAfterTimeout() public {
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));

        hevm.warp(now + 200 days);

        (address usr, uint48 bgn, uint48 clf, uint48 fin, uint128 amt, uint128 rxd, address mgr) = vest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 200 days);
        assertEq(uint256(fin), now - 100 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 0);

        vest.vest(id);
        (usr, bgn, clf, fin, amt, rxd, mgr) = vest.awards(id);
        // After final payout, vesting information is removed
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 200 days);
        assertEq(uint256(fin), now - 100 days);
        assertEq(uint256(amt), 100 * days_vest);
        assertEq(uint256(rxd), 100 * days_vest);
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 100*days_vest);
        assertTrue(!vest.valid(id));
    }

    function testMove() public {
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));
        vest.move(id, address(3));

        (address usr,,,,,,) = vest.awards(id);
        assertEq(usr, address(3));
    }

    function testFailMoveToZeroAddress() public {
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));
        vest.move(id, address(0));
    }

    function testUnpaid() public {
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 1 days, address(0));
        assertTrue(vest.valid(id));

        assertEq(vest.unpaid(id), 0);
        hevm.warp(block.timestamp + 43200);
        assertEq(vest.unpaid(id), 0);                   // inside cliff
        hevm.warp(block.timestamp + 36 hours);
        assertEq(vest.unpaid(id), days_vest * 2);       // past cliff
        hevm.warp(block.timestamp + 2 days);
        assertEq(vest.unpaid(id), days_vest * 4);       // past cliff
        vest.vest(id);
        assertEq(vest.unpaid(id), 0);
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), days_vest * 4);
        hevm.warp(block.timestamp + 10 days);
        assertEq(vest.unpaid(id), days_vest * 10);
        vest.vest(id);
        assertEq(vest.unpaid(id), 0);
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), days_vest * 14);
        hevm.warp(block.timestamp + 120 days);           // vesting complete
        assertEq(vest.unpaid(id), days_vest * 86);
        vest.vest(id);
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 100 * days_vest);
    }

    function testAccrued() public {
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp + 10 days, 100 days, 0, address(0));
        assertTrue(vest.valid(id));

        assertEq(vest.accrued(id), 0);
        hevm.warp(block.timestamp + 43200);
        assertEq(vest.unpaid(id), 0);                   // inside cliff
        assertEq(vest.accrued(id), 0);
        hevm.warp(block.timestamp + 12 hours + 11 days);
        assertEq(vest.unpaid(id), days_vest * 2);       // past cliff
        assertEq(vest.accrued(id), days_vest * 2);
        hevm.warp(block.timestamp + 2 days);
        assertEq(vest.unpaid(id), days_vest * 4);       // past cliff
        assertEq(vest.accrued(id), days_vest * 4);
        vest.vest(id);
        assertEq(vest.unpaid(id), 0);
        assertEq(vest.accrued(id), days_vest * 4);
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), days_vest * 4);
        hevm.warp(block.timestamp + 10 days);
        assertEq(vest.unpaid(id), days_vest * 10);
        assertEq(vest.accrued(id), days_vest * 14);
        vest.vest(id);
        assertEq(vest.unpaid(id), 0);
        assertEq(vest.accrued(id), days_vest * 14);
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), days_vest * 14);
        hevm.warp(block.timestamp + 120 days);       // vesting complete
        assertEq(vest.unpaid(id), days_vest * 86);
        assertEq(vest.accrued(id), days_vest * 100);
        vest.vest(id);
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 100 * days_vest);
    }

    function testFutureAccrual() public {
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp + 10 days, 100 days, 0, address(0));
        assertEq(vest.accrued(id), 0);               // accrual starts in 10 days
        hevm.warp(block.timestamp + 9 days);
        assertEq(vest.accrued(id), 0);               // accrual starts in 1 days
        hevm.warp(block.timestamp + 2 days);
        assertEq(vest.accrued(id), days_vest);       // accrual started 1 day ago
        hevm.warp(block.timestamp + 999 days);
        assertEq(vest.accrued(id), days_vest * 100); // accrual ended
    }

    function testYank() public {
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 1 days, address(0));
        assertTrue(vest.valid(id));
        vest.yank(id); // yank before cliff
        assertTrue(!vest.valid(id));

        id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 1 days, address(0));
        assertTrue(vest.valid(id));
        hevm.warp(block.timestamp + 2 days);
        vest.yank(id); // yank after cliff
        assertTrue(vest.valid(id));
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 0);
        vest.vest(id);
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 2 * days_vest);
        assertTrue(!vest.valid(id));
    }

    function testYankInsideCliff() public {
        Manager manager = new Manager();
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 50 days, address(manager));

        hevm.warp(now + 10 days);

        manager.yank(address(vest), id);

        assertTrue(!vest.valid(id));
    }

    function testDoubleYank() public {
        // Test case where vest is yanked twice, say by manager and then governance
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 1 days, address(0));
        assertTrue(vest.valid(id));
        hevm.warp(block.timestamp + 2 days);
        vest.yank(id); // accrued two days before yank
        (,,, uint48 fin, uint128 amt,,) = vest.awards(id);
        assertEq(fin, block.timestamp);
        assertEq(amt, 2 * days_vest);
        assertTrue(vest.valid(id));
        hevm.warp(block.timestamp + 2 days);
        vest.yank(id); // yank again later
        (,,, fin, amt,,) = vest.awards(id);
        assertEq(fin, block.timestamp - 2 days); // fin stays the same as the first yank
        assertEq(amt, 2 * days_vest);   // amt doesn't get updated on second yank
        assertTrue(vest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        vest.vest(id); // user collects at some future time
        assertTrue(!vest.valid(id));
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 2 * days_vest);
    }

    function testYankAfterVest() public {
        // Test case where vest is yanked twice, say by manager and then governance
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 1 days, address(0));
        assertTrue(vest.valid(id));
        hevm.warp(block.timestamp + 2 days);
        assertEq(vest.unpaid(id), 2 * days_vest);
        vest.vest(id); // collect some now
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 2 * days_vest);

        hevm.warp(block.timestamp + 2 days);
        assertEq(vest.unpaid(id), 2 * days_vest);
        assertEq(vest.accrued(id), 4 * days_vest);

        vest.yank(id); // yank 4 days after start
        (,,, uint48 fin, uint128 amt,,) = vest.awards(id);
        assertEq(fin, block.timestamp);
        assertEq(amt, 4 * days_vest);   // amt doesn't get updated on second yank
        assertTrue(vest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(vest.unpaid(id), 2 * days_vest);
        assertEq(vest.accrued(id), 4 * days_vest);
        vest.vest(id); // user collects at some future time
        assertTrue(!vest.valid(id));
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 4 * days_vest);
    }

    function testYankSchedulePassed() public {
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 20 days, address(0));

        hevm.warp(block.timestamp + 51 days);

        vest.yank(id, now - 10 days); // Try to yank before cliff

        (,,, uint48 fin, uint128 amt,,) = vest.awards(id);
        assertEq(fin, block.timestamp);
        assertEq(amt, 51 * days_vest);   // amt is total amount
        assertTrue(vest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(vest.unpaid(id), 51 * days_vest);
        assertEq(vest.accrued(id), 51 * days_vest);
        vest.vest(id); // user collects at some future time
        assertTrue(!vest.valid(id));
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 51 * days_vest);
    }

    function testYankScheduleFutureAfterCliff() public {
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 20 days, address(0));

        hevm.warp(block.timestamp + 11 days);

        vest.yank(id, now + 10 days); // Schedule yank after cliff

        (,,, uint48 fin, uint128 amt,,) = vest.awards(id);
        assertEq(fin, block.timestamp + 10 days);
        assertEq(uint256(amt), 21 * days_vest);   // amt is total amount
        assertTrue(vest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(vest.unpaid(id), 21 * days_vest);
        assertEq(vest.accrued(id), 21 * days_vest);
        vest.vest(id); // user collects at some future time
        assertTrue(!vest.valid(id));
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 21 * days_vest);
    }

    function testYankScheduleFutureBeforeCliff() public {
        // Test case where yank is scheduled but before the cliff
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 20 days, address(0));
        vest.yank(id, now + 10 days); // Schedule yank before cliff

        (,,, uint48 fin, uint128 amt,,) = vest.awards(id);
        assertEq(fin, block.timestamp + 10 days);
        assertEq(uint256(amt), 0);   // amt is total amount
        assertTrue(!vest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(vest.unpaid(id), 0);
        assertEq(vest.accrued(id), 0);
        vest.vest(id); // user collects at some future time
        assertTrue(!vest.valid(id));
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 0);
    }

    function testYankScheduleFutureAfterCompletion() public {
        // When the sheduled yank takes place after the natural conclusion of the vest,
        //  Pay out the remainder of the contract and no more.
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 20 days, address(0));

        hevm.warp(block.timestamp + 11 days);

        vest.yank(id, now + 999 days); // Schedule yank after completion

        (,,, uint48 fin, uint128 amt,,) = vest.awards(id);
        assertEq(fin, block.timestamp + 89 days);
        assertEq(uint256(amt), 100 * days_vest);   // amt is total amount
        assertTrue(vest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(vest.unpaid(id), 100 * days_vest);
        assertEq(vest.accrued(id), 100 * days_vest);
        vest.vest(id); // user collects at some future time
        assertTrue(!vest.valid(id));
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 100 * days_vest);
    }

    function testMgrYank() public {
        Manager manager = new Manager();
        uint256 id1 = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 1 days, address(manager));

        assertTrue(vest.valid(id1));
        hevm.warp(block.timestamp + 30 days);
        manager.yank(address(vest), id1);
        assertTrue(vest.valid(id1));
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 0);
        vest.vest(id1);
        assertEq(Token(address(vest.gem())).balanceOf(address(this)), 30 * days_vest);
        assertTrue(!vest.valid(id1));

        uint256 id2 = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 30 days, address(manager));
        assertTrue(id1 != id2);
        assertTrue(vest.valid(id2));
        manager.yank(address(vest), id2);
        assertTrue(!vest.valid(id2));
    }

    function testFailMgrYankUnauthed() public {
        Manager manager = new Manager();
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(1));
        manager.yank(address(vest), id);
    }

    function testLive() public {
        uint256 id = vest.init(address(this), 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));
        assertTrue(vest.valid(id));
        assertTrue(!vest.valid(5));
    }

    function testFailAmtTooHigh() public {
        vest.init(address(this), uint128(-1) + 1, block.timestamp, 100 days, 0 days, address(0));
    }

    function testFailZeroUser() public {
        vest.init(address(0), 100 * days_vest + 1, block.timestamp, 100 days, 0 days, address(0));
    }

    function testFailStartTooFarInTheFuture() public {
        vest.init(address(this), 100 * days_vest + 1, block.timestamp + (21 * 365 days), 100 days, 0 days, address(0));
    }

    function testFailStartTooFarInThePast() public {
        vest.init(address(this), 100 * days_vest + 1, block.timestamp - (21 * 365 days), 100 days, 0 days, address(0));
    }

    function testFailStartTooLong() public {
        vest.init(address(this), 100 * days_vest + 1, block.timestamp, 21 * 365 days, 0 days, address(0));
    }

    function testFailClfAfterTau() public {
        vest.init(address(this), 100 * days_vest + 1, block.timestamp, 100 days, 101 days, address(0));
    }
}
