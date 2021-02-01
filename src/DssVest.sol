// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2021 - Brian McMichael <brian@brianmcmichael.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.6.11;

interface IMKR {
    function mint(address usr, uint256 amt) external;
}

contract DssVest {

    // MKR Mainnet: 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    IMKR public immutable MKR;

    uint256 internal constant WAD = 10**18;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Init(uint256 indexed id);
    event Vest(uint256 indexed id);
    event Move(uint256 indexed id);
    event Yank(uint256 indexed id);

    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth {
        require(wards[msg.sender] == 1, "dss-vest/not-authorized");
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

    // Governance must rely() this contract on MKR's GOV_GUARD to mint.
    constructor(address mkr) public {
        MKR = IMKR(mkr);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function init(address _usr, uint256 _amt, uint256 _tau, uint256 _pmt) external auth returns (uint256 id) {
        require(_usr != address(0),  "dss-vest/invalid-user");
        require(_amt < uint128(-1),  "dss-vest/amount-error");
        require(_tau < 5 * 365 days, "dss-vest/tau-too-long");
        require(_pmt < uint128(-1),  "dss-vest/payout-error");
        require(_pmt <= _amt,        "dss-vest/bulk-payment-higher-than-amt");

        id = ++ids;
        if (_amt - _pmt != 0) {      // safe because pmt <= amt
            awards[id] = Award({
                usr: _usr,
                bgn: uint48(block.timestamp),
                fin: uint48(block.timestamp + _tau),
                amt: uint128(_amt - _pmt),
                rxd: 0
            });
        }
        if (_pmt != 0) {
            MKR.mint(_usr, _pmt);    // Initial payout
        }
        emit Init(id);
    }

    function vest(uint256 _id) external {
        Award memory _award = awards[_id];
        require(_award.usr == msg.sender, "dss-vest/only-user-can-claim");

        if (block.timestamp >= _award.fin) {  // Vesting period has ended.
            MKR.mint(_award.usr, sub(_award.amt, _award.rxd)); // TODO prove this can't fail. Look for remainder errors in formula below.
            delete awards[_id];
        } else {                              // Vesting in progress
            uint256 t = (block.timestamp - _award.bgn) * WAD / (_award.fin - _award.bgn);
            uint256 mkr = (_award.amt * t) / WAD;
            MKR.mint(_award.usr, sub(mkr, _award.rxd));
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
        require(_usr != address(0), "dss-vest/zero-address-invalid");
        awards[_id].usr = _usr;
        emit Move(_id);
    }

    function live(uint256 _id) external view returns (bool) {
        return awards[_id].usr != address(0);
    }
}
