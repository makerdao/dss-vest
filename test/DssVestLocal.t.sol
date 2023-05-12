// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "../lib/forge-std/src/Test.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol";
import "@tokenize.it/contracts/contracts/Token.sol";
import "@tokenize.it/contracts/contracts/AllowList.sol";
import "@tokenize.it/contracts/contracts/FeeSettings.sol";
import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import {DssVestMintable} from "../src/DssVest.sol";
import "../src/DssVestNaiveFactory.sol";

contract DssVestLocal is Test {
    uint256 constant totalVestAmount = 42e18; // 42 tokens
    uint256 constant vestDuration = 4 * 365 days; // 4 years
    uint256 constant vestCliff = 1 * 365 days; // 1 year

    // init forwarder
    Forwarder forwarder = new Forwarder();
    bytes32 domainSeparator;
    bytes32 requestType;

    // DO NOT USE THESE KEYS IN PRODUCTION! They were generated and stored very unsafely.
    uint256 public constant platformAdminPrivateKey =
        0x3c69254ad72222e3ddf37667b8173dd773bdbdfd93d4af1d192815ff0662de5f;
    address public platformAdminAddress = vm.addr(companyAdminPrivateKey); // = 0x38d6703d37988C644D6d31551e9af6dcB762E618;

    uint256 public constant companyAdminPrivateKey =
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    address public companyAdminAddress = vm.addr(companyAdminPrivateKey); // = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    uint256 public constant employeePrivateKey =
        0x8da4ef21b864d2cc526dbdb2a120bd2874c36c9d0a1fb7f8c63d7f7a8b41de8f;
    address public employeeAddress = vm.addr(employeePrivateKey); // = 0x63FaC9201494f0bd17B9892B9fae4d52fe3BD377;

    address public constant relayer =
        0xDFcEB49eD21aE199b33A76B726E2bea7A72127B0;

    address public constant platformFeeCollector =
        0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;

    uint tokenFeeDenominator = 100;
    uint paymentTokenFeeDenominator = 200;
    Token companyToken;

    function setUp() public {

        vm.warp(60 * 365 days); // in local testing, the time would start at 1. This causes problems with the vesting contract. So we warp to 60 years.

        // // deploy the clone library
        // Clones clones = new Clones();

        // deploy tokenize.it platform and company token
        vm.startPrank(platformAdminAddress);
        AllowList allowList = new AllowList();
        Fees memory fees = Fees(
            tokenFeeDenominator,
            paymentTokenFeeDenominator,
            paymentTokenFeeDenominator,
            0
        );

        FeeSettings feeSettings = new FeeSettings(fees, platformFeeCollector);

        companyToken = new Token(
            address(forwarder),
            feeSettings,
            companyAdminAddress,
            allowList,
            0, // set requirements 0 in order to keep this test simple
            "Company Token",
            "COMPT"
        );
        vm.stopPrank();
    }

    function testFileWrongKeylocal() public {
        DssVestMintable vest = new DssVestMintable(address(forwarder), address(companyToken));
        vm.expectRevert("DssVest/file-unrecognized-param");
        vest.file("wrongKey", 0x123);
    }
}
