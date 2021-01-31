pragma solidity ^0.6.7;

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

contract DssVestTest is DSTest {
    Hevm hevm;
    DssVest vest;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    address GOV_GUARD = 0x6eEB68B2C7A918f36B78E2DB80dcF279236DDFb8;

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));
        vest = new DssVest();

        // Set testing contract as a MKR Auth
        hevm.store(
            address(GOV_GUARD),
            keccak256(abi.encode(address(vest), uint256(1))),
            bytes32(uint256(1))
        );
        assertEq(GovGuard(GOV_GUARD).wards(address(vest)), 1);
    }

    function testCost() public {
        new DssVest();
    }

    function testInit() public {
        vest.init(address(this), 100 * 10**18, 100 days, 0);
        (address usr, uint48 bgn, uint48 fin, uint128 amt, uint128 rxd) = vest.awards(1);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now);
        assertEq(uint256(fin), now + 100 days);
        assertEq(uint256(amt), 100 * 10**18);
        assertEq(uint256(rxd), 0);
    }

    function testPmt() public {
        vest.init(address(this), 100 * 10**18, 100 days, 10 * 10**18);
        assertEq(Token(address(vest.MKR())).balanceOf(address(this)), 10*10**18);
    }

    function testVest() public {
        uint256 id = vest.init(address(this), 100 * 10**18, 100 days, 0);

        hevm.warp(now + 10 days);

        (address usr, uint48 bgn, uint48 fin, uint128 amt, uint128 rxd) = vest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * 10**18);
        assertEq(uint256(rxd), 0);
        assertEq(Token(address(vest.MKR())).balanceOf(address(this)), 0);

        vest.vest(id);
        (usr, bgn, fin, amt, rxd) = vest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 10 days);
        assertEq(uint256(fin), now + 90 days);
        assertEq(uint256(amt), 100 * 10**18);
        assertEq(uint256(rxd), 10 * 10**18);
        assertEq(Token(address(vest.MKR())).balanceOf(address(this)), 10*10**18);

        hevm.warp(now + 70 days);

        vest.vest(id);
        (usr, bgn, fin, amt, rxd) = vest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 80 days);
        assertEq(uint256(fin), now + 20 days);
        assertEq(uint256(amt), 100 * 10**18);
        assertEq(uint256(rxd), 80 * 10**18);
        assertEq(Token(address(vest.MKR())).balanceOf(address(this)), 80*10**18);
    }

    function testVestAfterTimeout() public {
        uint256 id = vest.init(address(this), 100 * 10**18, 100 days, 0);

        hevm.warp(now + 200 days);

        (address usr, uint48 bgn, uint48 fin, uint128 amt, uint128 rxd) = vest.awards(id);
        assertEq(usr, address(this));
        assertEq(uint256(bgn), now - 200 days);
        assertEq(uint256(fin), now - 100 days);
        assertEq(uint256(amt), 100 * 10**18);
        assertEq(uint256(rxd), 0);
        assertEq(Token(address(vest.MKR())).balanceOf(address(this)), 0);

        vest.vest(id);
        (usr, bgn, fin, amt, rxd) = vest.awards(id);
        // After final payout, vesting information is removed
        assertEq(usr, address(0));
        assertEq(uint256(bgn), 0);
        assertEq(uint256(fin), 0);
        assertEq(uint256(amt), 0);
        assertEq(uint256(rxd), 0);
        assertEq(Token(address(vest.MKR())).balanceOf(address(this)), 100*10**18);
        assertTrue(!vest.live(id));
    }

    function testMove() public {
        uint256 id = vest.init(address(this), 100 * 10**18, 100 days, 0);
        vest.move(id, address(3));

        (address usr,,,,) = vest.awards(id);
        assertEq(usr, address(3));
    }

    function testFailMoveToZeroAddress() public {
        uint256 id = vest.init(address(this), 100 * 10**18, 100 days, 0);
        vest.move(id, address(0));
    }

    function testYank() public {
        uint256 id = vest.init(address(this), 100 * 10**18, 100 days, 0);
        assertTrue(vest.live(id));
        vest.yank(id);
        assertTrue(!vest.live(id));
    }

    function testLive() public {
        uint256 id = vest.init(address(this), 100 * 10**18, 100 days, 0);
        assertTrue(vest.live(id));
        assertTrue(!vest.live(5));
    }
}
