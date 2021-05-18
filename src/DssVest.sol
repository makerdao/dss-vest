// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DssVest - Token vesting contract
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

    address public   immutable gem;

    uint256 public   constant  TWENTY_YEARS = 20 * 365 days;
    uint256 internal constant  WAD = 10**18;

    uint256 internal locked;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Init(uint256 indexed id,   address indexed usr);
    event Vest(uint256 indexed id,   uint256 indexed amt);
    event Move(uint256 indexed id,   address indexed dst);
    event File(bytes32 indexed what, uint256 indexed data);
    event Yank(uint256 indexed id);

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth {
        require(wards[msg.sender] == 1, "DssVest/not-authorized");
        _;
    }

    // --- Mutex  ---
    modifier lock {
        require(locked == 0, "DssVest/system-locked");
        locked = 1;
        _;
        locked = 0;
    }

    struct Award {
        address usr;   // Vesting recipient
        uint48  bgn;   // Start of vesting period  [timestamp]
        uint48  clf;   // The cliff date           [timestamp]
        uint48  fin;   // End of vesting period    [timestamp]
        uint128 tot;   // Total reward amount
        uint128 rxd;   // Amount of vest claimed
        address mgr;   // A manager address that can yank
    }
    mapping (uint256 => Award) public awards;
    uint256 public ids;

    uint256 public cap; // Maximum per-second issuance token rate

    // This contract must be authorized to 'mint' on the token
    constructor(address _gem, uint256 _cap) public {
        gem = _gem;
        cap = _cap;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function toUint48(uint256 x) internal pure returns (uint48 z) {
        require((z = uint48(x)) == x);
    }
    function toUint128(uint256 x) internal pure returns (uint128 z) {
        require((z = uint128(x)) == x);
    }

    /*
        @dev Govanance adds a vesting contract
        @param _usr The recipient of the reward
        @param _tot The total amount of the vest
        @param _bgn The starting timestamp of the vest
        @param _tau The duration of the vest (in seconds)
        @param _clf The cliff duration in seconds (i.e. 1 years)
        @param _mgr An optional manager for the contract. Can yank if vesting ends prematurely.
        @return id  The id of the vesting contract
    */
    function init(address _usr, uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _clf, address _mgr) external auth lock returns (uint256 id) {
        require(_usr != address(0),                        "DssVest/invalid-user");
        require(_tot < uint128(-1),                        "DssVest/amount-error");
        require(_tot > 0,                                  "DssVest/no-vest-total-amount");
        require(_bgn < add(block.timestamp, TWENTY_YEARS), "DssVest/bgn-too-far");
        require(_bgn > sub(block.timestamp, TWENTY_YEARS), "DssVest/bgn-too-long-ago");
        require(_tau > 0,                                  "DssVest/tau-zero");
        require(_tot / _tau <= cap,                        "DssVest/tot-too-high");
        require(_tau <= TWENTY_YEARS,                      "DssVest/tau-too-long");
        require(_clf <= _tau,                              "DssVest/clf-too-long");
        require(id < uint256(-1),                          "DssVest/id-overflow");

        id = ++ids;
        awards[id] = Award({
            usr: _usr,
            bgn: toUint48(_bgn),
            clf: toUint48(add(_bgn, _clf)),
            fin: toUint48(add(_bgn, _tau)),
            tot: toUint128(_tot),
            rxd: 0,
            mgr: _mgr
        });
        emit Init(id, _usr);
    }

    /*
        @dev Owner of a vesting contract calls this to claim rewards
        @param _id The id of the vesting contract
    */
    function vest(uint256 _id) external lock {
        Award memory _award = awards[_id];
        require(_award.usr == msg.sender, "DssVest/only-user-can-claim");

        uint256 amt = unpaid(block.timestamp, _award.bgn, _award.clf, _award.fin, _award.tot, _award.rxd);
        IERC20(gem).mint(_award.usr, amt);
        awards[_id].rxd = toUint128(add(awards[_id].rxd, amt));
        emit Vest(_id, amt);
    }

    /*
        @dev amount of tokens accrued, not accounting for tokens paid
        @param _id The id of the vesting contract
    */
    function accrued(uint256 _id) external view returns (uint256 amt) {
        Award memory _award = awards[_id];
        require(_award.usr != address(0), "DssVest/invalid-award");
        amt = accrued(block.timestamp, _award.bgn, _award.fin, _award.tot);
    }

    /*
        @dev amount of tokens accrued, not accounting for tokens paid
        @param _time the timestamp to perform the calculation
        @param _bgn  the start time of the contract
        @param _end  the end time of the contract
        @param _amt  the total amount of the contract
    */
    function accrued(uint256 _time, uint48 _bgn, uint48 _fin, uint128 _tot) internal pure returns (uint256 amt) {
        if (_time < _bgn) {
            amt = 0;
        } else if (_time >= _fin) {
            amt = _tot;
        } else {
            uint256 t = mul(sub(_time, _bgn), WAD) / sub(_fin, _bgn); // 0 <= t < WAD
            amt = mul(_tot, t) / WAD; // 0 <= gem < _award.tot
        }
    }

    /*
        @dev return the amount of vested, claimable GEM for a given ID
        @param _id The id of the vesting contract
    */
    function unpaid(uint256 _id) external view returns (uint256 amt) {
        Award memory _award = awards[_id];
        require(_award.usr != address(0), "DssVest/invalid-award");
        amt = unpaid(block.timestamp, _award.bgn, _award.clf, _award.fin, _award.tot, _award.rxd);
    }

    /*
        @dev amount of tokens accrued, not accounting for tokens paid
        @param _time the timestamp to perform the calculation
        @param _bgn  the start time of the contract
        @param _clf  the timestamp of the cliff
        @param _end  the end time of the contract
        @param _tot  the total amount of the contract
        @param _rxd  the number of gems received
    */
    function unpaid(uint256 _time, uint48 _bgn, uint48 _clf, uint48 _fin, uint128 _tot, uint128 _rxd) internal pure returns (uint256 amt) {
        amt = _time < _clf ? 0 : sub(accrued(_time, _bgn, _fin, _tot), _rxd);
    }

    /*
        @dev Allows governance or the manager to remove a vesting contract
        @param _id The id of the vesting contract
    */
    function yank(uint256 _id) external {
        yank(_id, block.timestamp);
    }

    /*
        @dev Allows governance or the manager to remove a vesting contract
        @param _id  The id of the vesting contract
        @param _end A scheduled time to end the vest
    */
    function yank(uint256 _id, uint256 _end) public {
        require(wards[msg.sender] == 1 || awards[_id].mgr == msg.sender, "DssVest/not-authorized");
        Award memory _award = awards[_id];
        require(_award.usr != address(0), "DssVest/invalid-award");
        if (_end < block.timestamp) {
            _end = block.timestamp;
        } else if (_end > _award.fin) {
            _end = _award.fin;
        }
        awards[_id].fin = toUint48(_end);
        awards[_id].tot = toUint128(add(
                                    unpaid(_end, _award.bgn, _award.clf, _award.fin, _award.tot, _award.rxd),
                                    _award.rxd)
                                );
        emit Yank(_id);
    }

    function file(bytes32 what, uint256 data) external auth {
        if      (what == "cap")         cap = data;     // The maximum amount of tokens that can be streamed per year per vest
        else revert("DssVest/file-unrecognized-param");
        emit File(what, data);
    }

    /*
        @dev Allows owner to move a contract to a different address
        @param _id  The id of the vesting contract
        @param _dst The address to send ownership of the contract to
    */
    function move(uint256 _id, address _dst) external {
        require(awards[_id].usr == msg.sender, "DssVest/only-user-can-move");
        require(_dst != address(0), "DssVest/zero-address-invalid");
        awards[_id].usr = _dst;
        emit Move(_id, _dst);
    }

    /*
        @dev Return true if a contract is valid
        @param _id The id of the vesting contract
    */
    function valid(uint256 _id) external view returns (bool) {
        return awards[_id].rxd < awards[_id].tot;
    }
}
