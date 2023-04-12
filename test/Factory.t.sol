// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

//import "ds-test/test.sol";
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
import "../src/Factory.sol";

contract DssVestFactoryDemo is Test {
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
    address public platformAdminAddress = vm.addr(platformAdminPrivateKey); // = 0x38d6703d37988C644D6d31551e9af6dcB762E618;

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

    DssVestMintable          mVest;

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

        // deploy factory
        DssVestNaiveFactory factory = new DssVestNaiveFactory();

        // Deploy instance
        mVest = DssVestMintable(factory.createDssVestMintable(address(forwarder), address(companyToken), companyAdminAddress));

        require(mVest.isTrustedForwarder(address(forwarder)), "Forwarder not trusted");
        require(address(mVest.gem()) == address(companyToken), "Token not set");
        require(mVest.wards(companyAdminAddress) == 1, "Company admin is not a ward");
        require(mVest.wards(address(this)) == 0, "Msg.sender is a ward");
        
        console.log("factory address: ", address(factory));
        console.log("clone address: ", address(mVest));

        // initialize vesting contract 
        vm.startPrank(companyAdminAddress);
        //mVest = new DssVestMintable(address(forwarder), address(companyToken));
        mVest.file("cap", (totalVestAmount / vestDuration) ); 

        // grant minting allowance
        companyToken.increaseMintingAllowance(address(mVest), totalVestAmount);
        vm.stopPrank();
    }

    function testNoWrongWardslocal() public {

        vm.startPrank(platformAdminAddress);
        // Deploy instance
        DssVestNaiveFactory factory = new DssVestNaiveFactory();
        mVest = DssVestMintable(factory.createDssVestMintable(address(forwarder), address(companyToken), companyAdminAddress));
        vm.stopPrank();

        console.log("factory address: ", address(factory));
        console.log("companyAdminAddress: ", companyAdminAddress);
        console.log("test account address: ", address(this));
        console.log("platformAdminAddress: ", platformAdminAddress);

        require(mVest.isTrustedForwarder(address(forwarder)), "Forwarder not trusted");
        require(address(mVest.gem()) == address(companyToken), "Token not set");
        require(mVest.wards(companyAdminAddress) == 1, "Company admin is not a ward");
        require(mVest.wards(address(factory)) == 0, "Factory is a ward");
        require(mVest.wards(platformAdminAddress) == 0, "Platform is a ward");
        require(mVest.wards(address(this)) == 0, "Test account is a ward");
        
    }


    /**
     * @notice does the full setup and payout without meta tx
     * @dev Many local variables had to be removed to avoid stack too deep error
     */
    function testDemoEverythinglocal() public {

        uint startDate = block.timestamp;
        // create vest as company admin
        vm.prank(companyAdminAddress);
        uint256 id = mVest.create(employeeAddress, totalVestAmount, block.timestamp, vestDuration, vestCliff, companyAdminAddress);

        // accrued and claimable tokens can be checked at any time
        uint timeShift = 9 * 30 days;
        vm.warp(startDate + timeShift);
        uint unpaid = mVest.unpaid(id);
        assertEq(unpaid, 0, "unpaid is wrong: no tokens should be claimable yet");
        uint accrued = mVest.accrued(id);
        assertEq(accrued, totalVestAmount * timeShift / vestDuration, "accrued is wrong: some tokens should be accrued already");

        // claim tokens as employee
        timeShift = 2 * 365 days;
        vm.warp(startDate + timeShift);
        assertEq(companyToken.balanceOf(employeeAddress), 0, "employee already has tokens");
        vm.prank(employeeAddress);
        mVest.vest(id);
        assertEq(companyToken.balanceOf(employeeAddress), totalVestAmount * timeShift / vestDuration, "employee has received wrong token amount");
    }
}
