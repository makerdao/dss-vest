// SPDX-License-Identifier: AGPL-3.0-or-later
//
// dss-vest - Token vesting contract
//
// Copyright (C) 2020-2021  Servo Farms, LLC
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
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.6.12;

interface IERC20 {
    function mint(address usr, uint256 amt) external;
}

contract DssVest {

    IERC20   public immutable GEM;
    uint256  public constant  MAX_VEST_PERIOD = 20 * 365 days;

    uint256 internal constant WAD = 10**18;

    uint256 internal locked;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Init(uint256 indexed id, address indexed usr);
    event Vest(uint256 indexed id);
    event Move(uint256 indexed id, address indexed dst);
    event Yank(uint256 indexed id);

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth {
        require(wards[msg.sender] == 1, "dss-vest/not-authorized");
        _;
    }

    // --- Mutex  ---
    modifier lock {
        require(locked == 0, "dss-vest/system-locked");
        locked = 1;
        _;
        locked = 0;
    }

    struct Award {
        address usr;   // Vesting recipient
        uint48  bgn;   // Start of vesting period
        uint48  clf;   // An optional cliff
        uint48  fin;   // End of vesting period
        uint128 amt;   // Total reward amount
        uint128 rxd;   // Amount of vest claimed
        address mgr;   // A manager address that can yank
    }
    mapping (uint256 => Award) public awards;
    uint256 public ids;

    // This contract must be authorized to 'mint' on the token
    constructor(address gem) public {
        GEM = IERC20(gem);
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
        @param _mgr An optional manager for the contract. Can yank if vesting ends prematurely.
        @return id  The id of the vesting contract
    */
    function init(address _usr, uint256 _amt, uint256 _bgn, uint256 _tau, uint256 _clf, address _mgr) external auth lock returns (uint256 id) {
        require(_usr != address(0),                       "dss-vest/invalid-user");
        require(_amt < uint128(-1),                       "dss-vest/amount-error");
        require(_amt > 0,                                 "dss-vest/no-vest-amt");
        require(_bgn < block.timestamp + MAX_VEST_PERIOD, "dss-vest/bgn-too-far");
        require(_bgn > block.timestamp - MAX_VEST_PERIOD, "dss-vest/bgn-too-long-ago");
        require(_tau > 0,                                 "dss-vest/tau-zero");
        require(_tau <= MAX_VEST_PERIOD,                  "dss-vest/tau-too-long");
        require(_clf <= _tau,                             "dss-vest/clf-too-long");

        id = ++ids;
        awards[id] = Award({
            usr: _usr,
            bgn: uint48(_bgn),
            clf: uint48(_bgn + _clf),
            fin: uint48(_bgn + _tau),
            amt: uint128(_amt),
            rxd: 0,
            mgr: _mgr
        });
        emit Init(id, _usr);
    }

    /*
        @dev Owner of a vesting contract calls this to claim rewards
        @param id The id of the vesting contract
    */
    function vest(uint256 _id) external lock {
        Award memory _award = awards[_id];
        require(_award.usr == msg.sender, "dss-vest/only-user-can-claim");

        uint256 gem = unpaid(_award.bgn, _award.clf, _award.fin, _award.amt, _award.rxd);
        if (gem > 0) {
            GEM.mint(_award.usr, gem);
            awards[_id].rxd += uint128(gem);
        }
        if (block.timestamp >= _award.fin) delete awards[_id];
        emit Vest(_id);
    }

    /*
        @dev amount of tokens accrued, not accounting for tokens paid
        @param bgn the start time of the contract
        @param end the end time of the contract
        @param amt the total amount of the contract
    */
    function accrued(uint48 bgn, uint48 fin, uint128 amt) internal view returns (uint256 gem) {
        if (block.timestamp < bgn) {
            gem = 0;
        } else if (block.timestamp >= fin) {
            gem = amt;
        } else {
            uint256 t = (block.timestamp - bgn) * WAD / (fin - bgn); // 0 <= t < WAD
            gem = (amt * t) / WAD; // 0 <= gem < _award.amt
        }
    }

    function accrued(uint256 id) external view returns (uint256 amt) {
        Award memory _award = awards[id];
        require(_award.usr != address(0), "dss-vest/invalid-award");
        amt = accrued(_award.bgn, _award.fin, _award.amt);
    }

    /*
        @dev return the amount of vested, claimable GEM for a given ID
        @param id The id of the vesting contract
    */
    function unpaid(uint256 id) external view returns (uint256 gem) {
        Award memory _award = awards[id];
        require(_award.usr != address(0), "dss-vest/invalid-award");
        return unpaid(_award.bgn, _award.clf, _award.fin, _award.amt, _award.rxd);
    }

    function unpaid(uint48 bgn, uint48 clf, uint48 fin, uint128 amt, uint128 rxd) internal view returns (uint256 gem) {
        if (block.timestamp < clf) {
            return 0;
        } else {
            return sub(accrued(bgn, fin, amt), rxd);
        }
    }

    /*
        @dev Allows governance or the manager to remove a vesting contract
        @param id The id of the vesting contract
    */
    function yank(uint256 _id) external {
        require(wards[msg.sender] == 1 || awards[_id].mgr == msg.sender, "dss-vest/not-authorized");
        Award memory _award = awards[_id];
        require(_award.usr != address(0), "dss-vest/invalid-award");

        uint256 gem = unpaid(_award.bgn, _award.clf, _award.fin, _award.amt, _award.rxd);
        if (gem == 0) {
            delete awards[_id];
        } else {         // Contract is past cliff vest
            awards[_id].fin = uint48(block.timestamp);
            awards[_id].amt = uint128(gem);
        }

        emit Yank(_id);
    }

    /*
        @dev Allows owner to move a contract to a different address
        @param _id  The id of the vesting contract
        @param _dst The address to send ownership of the contract to
    */
    function move(uint256 _id, address _dst) external {
        require(awards[_id].usr == msg.sender, "dss-vest/only-user-can-move");
        require(_dst != address(0), "dss-vest/zero-address-invalid");
        awards[_id].usr = _dst;
        emit Move(_id, _dst);
    }

    /*
        @dev Return true if a contract is valid
        @param _id The id of the vesting contract
    */
    function valid(uint256 _id) external view returns (bool) {
        return awards[_id].usr != address(0);
    }
}
