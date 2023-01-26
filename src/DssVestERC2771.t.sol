// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

//import "ds-test/test.sol";
import "../lib/forge-std/src/Test.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol";


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


contract DssVestERC2771Test is Test {
    // --- Math ---
    uint256 constant WAD = 10**18;
    uint256 constant RAY = 10**27;
    uint256 constant days_vest = WAD;

    // --- Hevm ---
    Hevm hevm;

    // init forwarder
    Forwarder forwarder = new Forwarder();
    bytes32 domainSeparator;
    bytes32 requestType;

    // DO NOT USE THESE KEYS IN PRODUCTION! They were generated and stored very unsafely.
    uint256 public constant wardPrivateKey =
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    address public wardAddress = vm.addr(wardPrivateKey); // = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    uint256 public constant mgrPrivateKey =
        0x3c69254ad72222e3ddf37667b8173dd773bdbdfd93d4af1d192815ff0662de5f;
    address public mgrAddress = vm.addr(mgrPrivateKey); // = 0x38d6703d37988C644D6d31551e9af6dcB762E618;

    uint256 public constant usrPrivateKey =
        0x8da4ef21b864d2cc526dbdb2a120bd2874c36c9d0a1fb7f8c63d7f7a8b41de8f;
    address public usrAddress = vm.addr(usrPrivateKey); // = 0x63FaC9201494f0bd17B9892B9fae4d52fe3BD377;

    address public constant relayer =
        0xDFcEB49eD21aE199b33A76B726E2bea7A72127B0;

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

        // deploy contracts as ward
        vm.startPrank(wardAddress);
        mVest = new DssVestMintable(address(forwarder), address(gem));
        mVest.file("cap", (2000 * WAD) / (4 * 365 days));
        sVest = new DssVestSuckable(address(forwarder), address(chainlog));
        sVest.file("cap", (2000 * WAD) / (4 * 365 days));
        boss = new Manager();
        tVest = new DssVestTransferrable(address(forwarder), address(boss), address(dai));
        tVest.file("cap", (2000 * WAD) / (4 * 365 days));
        boss.gemApprove(address(dai), address(tVest));
        vm.stopPrank();


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

        // register domain separator with forwarder. Since the forwarder does not check the domain separator, we can use any string as domain name.
        vm.recordLogs();
        forwarder.registerDomainSeparator(string(abi.encodePacked(address(mVest))), "v1.0"); // simply uses address string as name
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // the next line extracts the domain separator from the event emitted by the forwarder
        domainSeparator = logs[0].topics[1]; // internally, the forwarder calls this domainHash in registerDomainSeparator. But expects is as domainSeparator in execute().
        console.log("domainSeparator", vm.toString(domainSeparator));
        require(forwarder.domains(domainSeparator), "Registering failed");

        // register request type with forwarder. Since the forwarder does not check the request type, we can use any string as function name.
        vm.recordLogs();
        forwarder.registerRequestType("someFunctionName", "some function parameters");
        logs = vm.getRecordedLogs();
        // the next line extracts the request type from the event emitted by the forwarder
        requestType = logs[0].topics[1];
        console.log("requestType", vm.toString(requestType));
        require(forwarder.typeHashes(requestType), "Registering failed");
    }

    /**
     * @notice Create a new vest as ward using a meta tx that is sent by relayer
     */
    function testInitERC2771() public {
        // build request
        bytes memory payload = abi.encodeWithSelector(
            mVest.create.selector,
            usrAddress, 
            100 * days_vest, 
            block.timestamp, 
            100 days, 
            0 days, 
            mgrAddress
        );

        IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
            from: wardAddress,
            to: address(mVest),
            value: 0,
            gas: 1000000,
            nonce: forwarder.getNonce(wardAddress),
            data: payload,
            validUntil: block.timestamp + 1 hours // like this, the signature will expire after 1 hour. So the platform hotwallet can take some time to execute the transaction.
        });

        bytes memory suffixData = "0";


        // pack and hash request
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    forwarder._getEncoded(request, requestType, suffixData)
                )
            )
        );

        // sign request.        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            wardPrivateKey,
            digest
        );
        bytes memory signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        require(address(this) != wardAddress, "sender is the ward");
        vm.prank(relayer);
        forwarder.execute(
            request,
            domainSeparator,
            requestType,
            suffixData,
            signature
        );

        console.log("signing address: ", request.from);
        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 tot, uint128 rxd) = mVest.awards(1);
        assertEq(usr, usrAddress);
        assertEq(uint256(bgn), block.timestamp);
        assertEq(uint256(clf), block.timestamp);
        assertEq(uint256(fin), block.timestamp + 100 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(mgr, mgrAddress);
    }

    /**
     * @notice Trigger payout as user using a meta tx that is sent by relayer
     * @dev Many local variables had to be removed to avoid stack too deep error
     */
    function testVestERC2771() public {
        vm.prank(wardAddress);
        uint256 id = mVest.create(usrAddress, 100 * days_vest, block.timestamp, 100 days, 0 days, mgrAddress);

        hevm.warp(block.timestamp + 10 days);

        (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = mVest.awards(id);
        assertEq(usr, usrAddress);
        assertEq(uint256(bgn), block.timestamp - 10 days);
        assertEq(uint256(fin), block.timestamp + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(gem.balanceOf(usrAddress), 0);

        IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
            from: usrAddress,
            to: address(mVest),
            value: 0,
            gas: 1000000,
            nonce: forwarder.getNonce(usrAddress),
            data: abi.encodeWithSelector(
            bytes4(keccak256(bytes("vest(uint256)"))),
            id
        ),
            validUntil: block.timestamp + 1 hours // like this, the signature will expire after 1 hour. So the platform hotwallet can take some time to execute the transaction.
        });

        // sign request.        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            usrPrivateKey,
            keccak256(abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    forwarder._getEncoded(request, requestType, "0")
                )
            ))
        );

        vm.prank(relayer);
        forwarder.execute(
            request,
            domainSeparator,
            requestType,
            "0",
            abi.encodePacked(r, s, v)
        );

        (usr, bgn, clf, fin,,, tot, rxd) = mVest.awards(id);
        assertEq(usr, usrAddress);
        assertEq(uint256(bgn), block.timestamp - 10 days);
        assertEq(uint256(fin), block.timestamp + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 10 * days_vest);
        assertEq(gem.balanceOf(usrAddress), 10 * days_vest);
    }

    /**
     * @notice Yank a vesting contract as manager using a meta tx that is sent by relayer.
     */
    function testYankAfterVestERC2771() public {
        // Test case where yanked is called after a partial vest
        vm.prank(wardAddress);
        uint256 id = mVest.create(usrAddress, 100 * days_vest, block.timestamp, 100 days, 1 days, mgrAddress);
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 2 days);
        assertEq(mVest.unpaid(id), 2 * days_vest);

        // usr collects some of their value
        vm.prank(usrAddress);
        mVest.vest(id); // collect some now
        assertEq(gem.balanceOf(usrAddress), 2 * days_vest);

        hevm.warp(block.timestamp + 2 days);
        assertEq(mVest.unpaid(id), 2 * days_vest);
        assertEq(mVest.accrued(id), 4 * days_vest);

        // prepare meta-tx to yank as mgr
        bytes memory payload = abi.encodeWithSelector(
            bytes4(keccak256(bytes("yank(uint256)"))),//mVest.yank.selector, // address not unique, so must calculate selector manually
            id
        );

        IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
            from: mgrAddress,
            to: address(mVest),
            value: 0,
            gas: 1000000,
            nonce: forwarder.getNonce(mgrAddress),
            data: payload,
            validUntil: block.timestamp + 1 hours // like this, the signature will expire after 1 hour. So the platform hotwallet can take some time to execute the transaction.
        });

        bytes memory suffixData = "0";


        // pack and hash request
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    forwarder._getEncoded(request, requestType, suffixData)
                )
            )
        );

        // sign request.        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            mgrPrivateKey,
            digest
        );
        bytes memory signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        vm.prank(relayer);
        forwarder.execute(
            request,
            domainSeparator,
            requestType,
            suffixData,
            signature
        );
        (,,, uint48 fin,,, uint128 tot,) = mVest.awards(id);
        assertEq(fin, block.timestamp);
        assertEq(tot, 4 * days_vest);
        assertTrue(mVest.valid(id));
        hevm.warp(block.timestamp + 999 days);
        assertEq(mVest.unpaid(id), 2 * days_vest);
        assertEq(mVest.accrued(id), 4 * days_vest);
        mVest.vest(id); // user collects at some future time
        assertTrue(!mVest.valid(id));
        assertEq(gem.balanceOf(usrAddress), 4 * days_vest);
    }
}
