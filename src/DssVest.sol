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

pragma solidity 0.6.12;

import "ds-deed/deed.sol";

interface IMKR {
    function mint(address usr, uint256 amt) external;
}

contract DssVest is DSDeed {

    // MKR Mainnet: 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    IMKR     public immutable MKR;
    uint256  public constant  MAX_VEST_PERIOD = 20 * 365 days;

    uint256 internal constant WAD = 10**18;

    uint256 internal locked;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Init(uint256 indexed id, address indexed usr);
    event Vest(uint256 indexed id);
    event Move(uint256 indexed id, address indexed dst);
    event Yank(uint256 indexed id);

    // --- Mutex  ---
    modifier lock {
        require(locked == 0, "dss-vest/system-locked");
        locked = 1;
        _;
        locked = 0;
    }

    struct Award {
        uint48  bgn;   // Start of vesting period
        uint48  clf;   // An optional cliff
        uint48  fin;   // End of vesting period
        uint128 amt;   // Total reward amount
        uint128 rxd;   // Amount of vest claimed
        address mgr;   // A manager address that can yank
    }
    mapping (uint256 => Award) public awards;

    // Governance must rely() this contract on MKR's GOV_GUARD to mint.
    constructor(address mkr, string memory name, string memory symbol) public DSDeed(name, symbol) {
        MKR = IMKR(mkr);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    /*
        @dev Govanance adds a vesting contract
        @param _usr The recipient of the reward
        @param _amt The total amount of the vest
        @param _bgn The starting timestamp of the vest
        @param _tau The duration of the vest (in seconds)
        @param _clf The cliff duration in seconds (i.e. 1 years)
        @param _pmt An optional lump sump payout from the vest amount
        @param _mgr An optional manager for the contract. Can yank if vesting ends prematurely.
        @return id  The id of the vesting contract
    */
    function init(address _usr, uint256 _amt, uint256 _bgn, uint256 _tau, uint256 _clf, uint256 _pmt, address _mgr) external auth lock returns (uint256 _id) {
        require(_usr != address(0),                       "dss-vest/invalid-user");
        require(_amt < uint128(-1),                       "dss-vest/amount-error");
        require(_bgn < block.timestamp + MAX_VEST_PERIOD, "dss-vest/bgn-too-far");
        require(_tau > 0,                                 "dss-vest/tau-zero");
        require(_tau <= MAX_VEST_PERIOD,                  "dss-vest/tau-too-long");
        require(_clf <= _tau,                             "dss-vest/clf-too-long");
        require(_pmt < uint128(-1),                       "dss-vest/payout-error");
        require(_pmt <= _amt,                             "dss-vest/bulk-payment-higher-than-amt");

        _id = mint(_usr);
        if (_amt - _pmt != 0) {      // safe because pmt <= amt
            awards[_id] = Award({
                bgn: uint48(_bgn),
                clf: uint48(_bgn + _clf),
                fin: uint48(_bgn + _tau),
                amt: uint128(_amt - _pmt),
                rxd: 0,
                mgr: _mgr
            });
        }
        if (_pmt != 0) {
            MKR.mint(_usr, _pmt);    // Initial payout
        }
        emit Init(_id, _usr);
    }

    /*
        @dev Owner of a vesting contract calls this to claim rewards
        @param id The id of the vesting contract
    */
    function vest(uint256 _id) external lock {
        Award memory _award = awards[_id];
        address _owner = _deeds[_id].guy;
        require(_owner == msg.sender, "dss-vest/only-user-can-claim");

        if (block.timestamp >= _award.fin) {  // Vesting period has ended.
            MKR.mint(_owner, sub(_award.amt, _award.rxd));
            remove(_id);
        } else if (block.timestamp >= _award.clf) {                              // Vesting in progress
            uint256 t = (block.timestamp - _award.bgn) * WAD / (_award.fin - _award.bgn); // 0 <= t < WAD
            uint256 mkr = (_award.amt * t) / WAD; // 0 <= mkr < _award.amt
            MKR.mint(_owner, sub(mkr, _award.rxd));
            awards[_id].rxd = uint128(mkr);
        }
        emit Vest(_id);
    }

    /*
        @dev Allows governance or the manager to remove a vesting contract
        @param id The id of the vesting contract
    */
    function yank(uint256 _id) external {
        require(wards[msg.sender] == 1 || awards[_id].mgr == msg.sender, "dss-vest/not-authorized");
        remove(_id);
        emit Yank(_id);
    }

    function remove(uint256 _id) internal {
        delete awards[_id];
        _burn(_id);
    }

    /*
        @dev Allows owner to move a contract to a different address
        @param _id  The id of the vesting contract
        @param _dst The address to send ownership of the contract to
    */
    //function move(uint256 _id, address _dst) external {
    //    require(this.ownerOf(_id) == msg.sender, "dss-vest/only-user-can-move");
    //    require(_dst != address(0), "dss-vest/zero-address-invalid");
    //    awards[_id].usr = _dst;
    //    emit Move(_id, _dst);
    //}

    /*
        @dev Return true if a contract is valid
        @param _id The id of the vesting contract
    */
    function valid(uint256 _id) external view returns (bool) {
        return _deeds[_id].guy != address(0);
    }

}
