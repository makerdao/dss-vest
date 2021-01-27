pragma solidity ^0.6.7;

interface IMKR {
    function mint(address usr, uint256 amt) external;
}

contract DssVest {

    IMKR public constant MKR = IMKR(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2);

    uint256 internal constant WAD = 10**18;

    event Rely(address usr);
    event Deny(address usr);
    event Init(address indexed usr, uint256 amt, uint256 fin);
    event Vest(uint256 id);
    event Yank(uint256 id);

    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth {
        require(wards[msg.sender] == 1, "ChainLog/not-authorized");
        _;
    }

    struct Award {
        address usr;   // Vesting recipient
        uint48  bgn;   // Start of vesting period
        uint48  fin;   // End of vesting period
        uint128 amt;   // Total reward amount
        uint128 rxd;   // Amount of vest claimed
    }
    mapping (uint256 => Award) public awards;
    uint256 public ids;

    // Governance must rely() this contract on MKR to mint.
    constructor() public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function init(address _usr, uint256 _amt, uint256 _tau, uint256 _pmt) external auth returns (uint256 id) {
        require(_usr != address(0),  "dss-vest/invalid-user");
        require(_amt < uint128(-1),  "dss-vest/amount-error");
        require(_tau < 5 * 365 days, "dss-vest/tau-too-long");
        require(_pmt < uint128(-1),  "dss-vest/payout-error");
        require(_pmt <= _amt,        "dss-vest/bulk-payment-higher-than-amt");

        id = ++ids;
        if (_pmt != 0) {
            MKR.mint(_usr, _pmt);    // Initial payout
        }

        if (_amt - _pmt != 0) {      // safe because pmt <= amt
            awards[id] = Award({
                usr: _usr,
                bgn: uint48(block.timestamp),
                fin: uint48(block.timestamp + _tau),
                amt: uint128(_amt - _pmt),
                rxd: 0
            });
        }
        emit Init(_usr, _amt, block.timestamp + _tau);
    }

    function vest(uint256 _id) external {
        Award memory _award = awards[_id];
        require(_award.usr != address(0), "dss-vest/invalid-vesting-award");
        require(_award.usr == msg.sender, "dss-vest/only-user-can-claim");

        if (block.timestamp >= _award.fin) {  // Vesting period has ended.
            MKR.mint(_award.usr, _award.amt - _award.rxd); // TODO safemath
            delete awards[_id];
        } else {                              // Vesting in progress
            uint256 t = (block.timestamp - _award.bgn) * WAD / (_award.fin - _award.bgn);
            uint256 mkr = (_award.amt * t) / WAD;
            MKR.mint(_award.usr, mkr - _award.rxd);
            awards[_id].rxd = uint128(mkr);
        }
        emit Vest(_id);
    }

    function yank(uint256 _id) external auth {
        delete awards[_id];
        emit Yank(_id);
    }

    function move(uint256 _id, address _usr) external {
        require(awards[_id].usr == msg.sender, "dss-vest/only-user-can-move");
        awards[_id].usr = _usr;
    }

    function active(uint256 _id) external view returns (bool) {
        return awards[_id].usr != address(0);
    }
}
