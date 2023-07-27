// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DssVest - Token vesting contract
//
// Copyright (C) 2021 Dai Foundation
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

pragma solidity 0.8.17;

import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

interface MintLike {
    function mint(address, uint256) external;
}

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface DaiJoinLike {
    function exit(address, uint256) external;
}

interface VatLike {
    function hope(address) external;
    function suck(address, address, uint256) external;
    function live() external view returns (uint256);
}

interface TokenLike {
    function transferFrom(address, address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

abstract contract DssVest is ERC2771Context, Initializable {
    // --- Data ---
    mapping (address => uint256) public wards;

    struct Award {
        address usr;   // Vesting recipient
        uint48  bgn;   // Start of vesting period  [timestamp]
        uint48  clf;   // The cliff date           [timestamp]
        uint48  fin;   // End of vesting period    [timestamp]
        address mgr;   // A manager address that can yank
        uint8   res;   // Restricted
        uint128 tot;   // Total reward amount
        uint128 rxd;   // Amount of vest claimed
    }
    mapping (uint256 => Award) public awards;

    uint256 public cap; // Maximum per-second issuance token rate

    uint256 public ids; // Total vestings

    uint256 internal locked;

    uint256 public constant  TWENTY_YEARS = 20 * 365 days;

    mapping (bytes32 => bool) public commitments; // hashes that can be used to create vesting plans
    mapping (bytes32 => uint256) public revocations; // revocations of commitments with revocation timestamp

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);

    event File(bytes32 indexed what, uint256 data);

    event Commit(bytes32 indexed hash);
    event Revoke(bytes32 indexed hash, uint256 end);
    event Claim(bytes32 indexed hash, uint256 indexed id);
    event Init(uint256 indexed id, address indexed usr);
    event Vest(uint256 indexed id, uint256 amt);
    event Restrict(uint256 indexed id);
    event Unrestrict(uint256 indexed id);
    event Yank(uint256 indexed id, uint256 end);
    event Move(uint256 indexed id, address indexed dst);

    // Getters to access only to the value desired
    function usr(uint256 _id) external view returns (address) {
        return awards[_id].usr;
    }

    function bgn(uint256 _id) external view returns (uint256) {
        return awards[_id].bgn;
    }

    function clf(uint256 _id) external view returns (uint256) {
        return awards[_id].clf;
    }

    function fin(uint256 _id) external view returns (uint256) {
        return awards[_id].fin;
    }

    function mgr(uint256 _id) external view returns (address) {
        return awards[_id].mgr;
    }

    function res(uint256 _id) external view returns (uint256) {
        return awards[_id].res;
    }

    function tot(uint256 _id) external view returns (uint256) {
        return awards[_id].tot;
    }

    function rxd(uint256 _id) external view returns (uint256) {
        return awards[_id].rxd;
    }

    /**
        @dev Base vesting logic contract constructor
        @param _trustedForwarder The trusted forwarder contract to be used for meta-transactions (see EIP-2771)
        @param _cap The maximum per-second issuance token rate
    */
    constructor (address _trustedForwarder, uint256 _cap) ERC2771Context(_trustedForwarder) initializer {
        initialize(_msgSender(), _cap);   
    }

    /**
        @notice Initialize the contract
        @dev This function can only be called once. Because the child contracts use the `initializer` modifier,
             it can not be used here. Instead, this function is protected manually with the `initialized` flag.
             Since this contract is abstract, it should not be possible to call this function directly in the first place.
        @dev The forwarder can not be initialized, so it can not be changed for cloned contracts. Instead, it is inherited 
             from the logic contract (the forwarder address is copied into the bytecode of the logic contract during contract
             creation because it is private immutable).
        @param _ward The address to be granted admin rights to the contract
        @param _cap The maximum per-second issuance token rate
     */
    function initialize(address _ward, uint256 _cap) public onlyInitializing { 
        wards[_ward] = 1;
        emit Rely(_ward);
        cap = _cap;
        emit File("cap", _cap);
    }

    // --- Mutex ---
    modifier lock {
        require(locked == 0, "DssVest/system-locked");
        locked = 1;
        _;
        locked = 0;
    }

    // --- Auth ---
    modifier auth {
        require(wards[_msgSender()] == 1, "DssVest/not-authorized");
        _;
    }

    function rely(address _usr) external auth {
        wards[_usr] = 1;
        emit Rely(_usr);
    }
    function deny(address _usr) external auth {
        wards[_usr] = 0;
        emit Deny(_usr);
    }

    /**
        @dev (Required) Set the per-second token issuance rate.
        @param what  The tag of the value to change (ex. bytes32("cap"))
        @param data  The value to update (ex. cap of 1000 tokens/yr == 1000*WAD/365 days)
    */
    function file(bytes32 what, uint256 data) external lock auth {
        if      (what == "cap")         cap = data;     // The maximum amount of tokens that can be streamed per-second per vest
        else revert("DssVest/file-unrecognized-param");
        emit File(what, data);
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x > y ? y : x;
    }
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "DssVest/add-overflow");
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "DssVest/sub-underflow");
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "DssVest/mul-overflow");
    }
    function toUint48(uint256 x) internal pure returns (uint48 z) {
        require((z = uint48(x)) == x, "DssVest/uint48-overflow");
    }
    function toUint128(uint256 x) internal pure returns (uint128 z) {
        require((z = uint128(x)) == x, "DssVest/uint128-overflow");
    }

    /** 
        @dev commit to the creation of an award without revealing the award's contents yet
        @param bch  Blind Commitment Hash - The hash of the award's contents, see hash in `claim` for details
    */
    function commit(bytes32 bch) external lock auth {
        commitments[bch] = true;
        emit Commit(bch);
    }

    /** 
        @dev Store the timestamp of a commitment revocation. This can be used to prevent a commitment from being claimed if the cliff has not been reached yet.
        @notice This function can be called again and will update the timestamp, which could be used to grant more tokens.
        @param bch  Blind Commitment Hash - The hash of the award's contents, see hash in `claim` for details
        @param end  When to terminate the vesting contract that can be created from the commitment. Any time in the past will be capped to the current timestamp.
    */
    function revoke(bytes32 bch, uint256 end) external lock auth {
        require(commitments[bch], "DssVest/commitment-not-found");
        end = block.timestamp > end ? block.timestamp : end; // can not revoke in the past
        revocations[bch] = end;
        emit Revoke(bch, end);
    }

    /**
        @dev Create a vesting contract from an earlier commitment
        @param _bch The hash of the award's contents
        @param _usr The recipient of the reward
        @param _tot The total amount of the vest
        @param _bgn The starting timestamp of the vest
        @param _tau The duration of the vest (in seconds)
        @param _eta The cliff duration in seconds (i.e. 1 years)
        @param _mgr An optional manager for the contract. Can yank if vesting ends prematurely.
        @param _slt The salt used to increase privacy when committing
        @return id  The id of the vesting contract
    */
    function claim(bytes32 _bch, address _usr, uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _eta, address _mgr, bytes32 _slt) public lock returns (uint256 id) {
        require(_bch == keccak256(abi.encodePacked(_usr, _tot, _bgn, _tau, _eta, _mgr, _slt)), "DssVest/invalid-hash");
        require(commitments[_bch], "DssVest/commitment-not-found");
        uint48 revocationTime = toUint48(revocations[_bch]);
        if ( revocationTime < _bgn + _eta  ) {
            // commitment has been revoked before the cliff: vesting plan is cancelled
            require(revocationTime == 0, "DssVest/commitment-revoked-before-cliff");
        } else if ( revocationTime < _bgn + _tau ) {
            // commitment has been revoked after the cliff, but before the end: vesting plan values have to be updated
            // goal: behave as if the vesting plan was created when committed, and yanked when revoked
            _tot = mul(_tot, sub(revocationTime, _bgn)) / _tau; // newTot as amount accrued if yanked at revocationTime
            _tau = sub(revocationTime, _bgn); // new duration as time between bgn and revocationTime
        }
        // commitment can claimed now. If values needed to be updated, they have been updated above.
        commitments[_bch] = false;
        id = _create(_usr, _tot, _bgn, _tau, _eta, _mgr);
        emit Claim(_bch, id);
    }

    /**
        @dev Governance adds a vesting contract
        @param _usr The recipient of the reward
        @param _tot The total amount of the vest
        @param _bgn The starting timestamp of the vest
        @param _tau The duration of the vest (in seconds)
        @param _eta The cliff duration in seconds (i.e. 1 years)
        @param _mgr An optional manager for the contract. Can yank if vesting ends prematurely.
        @return id  The id of the vesting contract
    */
    function create(address _usr, uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _eta, address _mgr) external lock auth returns (uint256 id) {
        return _create(_usr, _tot, _bgn, _tau, _eta, _mgr);
    }


    /**
        @dev Governance adds a vesting contract
        @param _usr The recipient of the reward
        @param _tot The total amount of the vest
        @param _bgn The starting timestamp of the vest
        @param _tau The duration of the vest (in seconds)
        @param _eta The cliff duration in seconds (i.e. 1 years)
        @param _mgr An optional manager for the contract. Can yank if vesting ends prematurely.
        @return id  The id of the vesting contract
    */
    function _create(address _usr, uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _eta, address _mgr) internal returns (uint256 id) {
        require(_usr != address(0),                        "DssVest/invalid-user");
        require(_tot > 0,                                  "DssVest/no-vest-total-amount");
        require(_bgn < add(block.timestamp, TWENTY_YEARS), "DssVest/bgn-too-far");
        require(_bgn > sub(block.timestamp, TWENTY_YEARS), "DssVest/bgn-too-long-ago");
        require(_tau > 0,                                  "DssVest/tau-zero");
        require(_tot / _tau <= cap,                        "DssVest/rate-too-high");
        require(_tau <= TWENTY_YEARS,                      "DssVest/tau-too-long");
        require(_eta <= _tau,                              "DssVest/eta-too-long");
        require(ids < type(uint256).max,                   "DssVest/ids-overflow");

        id = ++ids;
        awards[id] = Award({
            usr: _usr,
            bgn: toUint48(_bgn),
            clf: toUint48(add(_bgn, _eta)),
            fin: toUint48(add(_bgn, _tau)),
            tot: toUint128(_tot),
            rxd: 0,
            mgr: _mgr,
            res: 1
        });
        emit Init(id, _usr);
    }

    /**
        @dev Anyone (or only owner of a vesting contract if restricted) calls this to claim all available rewards
        @param _id     The id of the vesting contract
    */
    function vest(uint256 _id) external {
        _vest(_id, type(uint256).max);
    }

    /**
        @dev Anyone (or only owner of a vesting contract if restricted) calls this to claim rewards
        @param _id     The id of the vesting contract
        @param _maxAmt The maximum amount to vest
    */
    function vest(uint256 _id, uint256 _maxAmt) external {
        _vest(_id, _maxAmt);
    }

    /**
        @dev Anyone (or only owner of a vesting contract if restricted) calls this to claim rewards
        @param _id     The id of the vesting contract
        @param _maxAmt The maximum amount to vest
    */
    function _vest(uint256 _id, uint256 _maxAmt) internal lock {
        Award memory _award = awards[_id];
        require(_award.usr != address(0), "DssVest/invalid-award");
        require(_award.res == 0 || _award.usr == _msgSender(), "DssVest/only-user-can-claim");
        uint256 amt = unpaid(block.timestamp, _award.bgn, _award.clf, _award.fin, _award.tot, _award.rxd);
        amt = min(amt, _maxAmt);
        awards[_id].rxd = toUint128(add(_award.rxd, amt));
        pay(_award.usr, amt);
        emit Vest(_id, amt);
    }

    /**
        @dev claim and vest a commitment in one transaction
        @param _bch The hash of the commitment
        @param _usr The recipient of the reward
        @param _tot The total amount of the vest
        @param _bgn The starting timestamp of the vest
        @param _tau The duration of the vest (in seconds)
        @param _eta The cliff duration in seconds (i.e. 1 years)
        @param _mgr An optional manager for the contract. Can yank if vesting ends prematurely.
        @param _slt The salt of the commitment
    */
    function claimAndVest(bytes32 _bch, address _usr, uint256 _tot, uint256 _bgn, uint256 _tau, uint256 _eta, address _mgr, bytes32 _slt) external returns (uint256 id) {
        id = claim(_bch, _usr, _tot, _bgn, _tau, _eta, _mgr, _slt);
        _vest(id, type(uint256).max);
    }

    /**
        @dev amount of tokens accrued, not accounting for tokens paid
        @param _id  The id of the vesting contract
        @return amt The accrued amount
    */
    function accrued(uint256 _id) external view returns (uint256 amt) {
        Award memory _award = awards[_id];
        require(_award.usr != address(0), "DssVest/invalid-award");
        amt = accrued(block.timestamp, _award.bgn, _award.fin, _award.tot);
    }

    /**
        @dev amount of tokens accrued, not accounting for tokens paid
        @param _time The timestamp to perform the calculation
        @param _bgn  The start time of the contract
        @param _fin  The end time of the contract
        @param _tot  The total amount of the contract
        @return amt  The accrued amount
    */
    function accrued(uint256 _time, uint48 _bgn, uint48 _fin, uint128 _tot) internal pure returns (uint256 amt) {
        if (_time < _bgn) {
            amt = 0;
        } else if (_time >= _fin) {
            amt = _tot;
        } else {
            amt = mul(_tot, sub(_time, _bgn)) / sub(_fin, _bgn); // 0 <= amt < _award.tot
        }
    }

    /**
        @dev return the amount of vested, claimable GEM for a given ID
        @param _id  The id of the vesting contract
        @return amt The claimable amount
    */
    function unpaid(uint256 _id) external view returns (uint256 amt) {
        Award memory _award = awards[_id];
        require(_award.usr != address(0), "DssVest/invalid-award");
        amt = unpaid(block.timestamp, _award.bgn, _award.clf, _award.fin, _award.tot, _award.rxd);
    }

    /**
        @dev amount of tokens accrued, but not paid yet
        @param _time The timestamp to perform the calculation
        @param _bgn  The start time of the contract
        @param _clf  The timestamp of the cliff
        @param _fin  The end time of the contract
        @param _tot  The total amount of the contract
        @param _rxd  The number of gems received
        @return amt  The claimable amount
    */
    function unpaid(uint256 _time, uint48 _bgn, uint48 _clf, uint48 _fin, uint128 _tot, uint128 _rxd) internal pure returns (uint256 amt) {
        amt = _time < _clf ? 0 : sub(accrued(_time, _bgn, _fin, _tot), _rxd);
    }

    /**
        @dev Allows governance or the owner to restrict vesting to the owner only
        @param _id The id of the vesting contract
    */
    function restrict(uint256 _id) external lock {
        address usr_ = awards[_id].usr;
        require(usr_ != address(0), "DssVest/invalid-award");
        require(wards[_msgSender()] == 1 || usr_ == _msgSender(), "DssVest/not-authorized");
        awards[_id].res = 1;
        emit Restrict(_id);
    }

    /**
        @dev Allows governance or the owner to enable permissionless vesting
        @param _id The id of the vesting contract
    */
    function unrestrict(uint256 _id) external lock {
        address usr_ = awards[_id].usr;
        require(usr_ != address(0), "DssVest/invalid-award");
        require(wards[_msgSender()] == 1 || usr_ == _msgSender(), "DssVest/not-authorized");
        awards[_id].res = 0;
        emit Unrestrict(_id);
    }

    /**
        @dev Allows governance or the manager to remove a vesting contract immediately
        @param _id The id of the vesting contract
    */
    function yank(uint256 _id) external {
        _yank(_id, block.timestamp);
    }

    /**
        @dev Allows governance or the manager to remove a vesting contract at a future time
        @param _id  The id of the vesting contract
        @param _end A scheduled time to end the vest
    */
    function yank(uint256 _id, uint256 _end) external {
        _yank(_id, _end);
    }

    /**
        @dev Allows governance or the manager to end pre-maturely a vesting contract
        @param _id  The id of the vesting contract
        @param _end A scheduled time to end the vest
    */
    function _yank(uint256 _id, uint256 _end) internal lock {
        require(wards[_msgSender()] == 1 || awards[_id].mgr == _msgSender(), "DssVest/not-authorized");
        Award memory _award = awards[_id];
        require(_award.usr != address(0), "DssVest/invalid-award");
        if (_end < block.timestamp) {
            _end = block.timestamp;
        }
        if (_end < _award.fin) {
            uint48 end = toUint48(_end);
            awards[_id].fin = end;
            if (end < _award.bgn) {
                awards[_id].bgn = end;
                awards[_id].clf = end;
                awards[_id].tot = 0;
            } else if (end < _award.clf) {
                awards[_id].clf = end;
                awards[_id].tot = 0;
            } else {
                awards[_id].tot = toUint128(
                                    add(
                                        unpaid(_end, _award.bgn, _award.clf, _award.fin, _award.tot, _award.rxd),
                                        _award.rxd
                                    )
                                );
            }
        }

        emit Yank(_id, _end);
    }

    /**
        @dev Allows owner to move a contract to a different address
        @param _id  The id of the vesting contract
        @param _dst The address to send ownership of the contract to
    */
    function move(uint256 _id, address _dst) external lock {
        require(awards[_id].usr == _msgSender(), "DssVest/only-user-can-move");
        require(_dst != address(0), "DssVest/zero-address-invalid");
        awards[_id].usr = _dst;
        emit Move(_id, _dst);
    }

    /**
        @dev Return true if a contract is valid
        @param _id The id of the vesting contract
        @return isValid True for valid contract
    */
    function valid(uint256 _id) external view returns (bool isValid) {
        isValid = awards[_id].rxd < awards[_id].tot;
    }

    /**
        @dev Override this to implement payment logic.
        @param _guy The payment target.
        @param _amt The payment amount. [units are implementation-specific]
    */
    function pay(address _guy, uint256 _amt) virtual internal;
}

contract DssVestMintable is DssVest {

    MintLike public gem;

    /**
        @dev This contract must be authorized to 'mint' on the token
        @param _forwarder The address of the trusted forwarder for ERC2771
        @param _gem The contract address of the mintable token
        @param _cap The maximum amount of token bits that can be released in one plan each second
    */
    constructor(address _forwarder, address _gem, uint256 _cap) DssVest(_forwarder, _cap) {
        initialize(_gem, _msgSender(), _cap);   
    }

    function initialize(address _gem, address _ward, uint256 _cap) initializer public {
        super.initialize(_ward, _cap);
        require(_gem != address(0), "DssVestMintable/Invalid-token-address");
        gem = MintLike(_gem);
    }

    /**
        @dev Override pay to handle mint logic
        @param _guy The recipient of the minted token
        @param _amt The amount of token units to send to the _guy
    */
    function pay(address _guy, uint256 _amt) override internal {
        gem.mint(_guy, _amt);
    }
}

contract DssVestSuckable is DssVest {

    uint256 internal constant RAY = 10**27;

    ChainlogLike public chainlog;
    VatLike      public vat;
    DaiJoinLike  public daiJoin;

    /**
        @dev This contract must be authorized to 'suck' on the vat
        @param _forwarder The address of the trusted forwarder for ERC2771
        @param _chainlog The contract address of the MCD chainlog
        @param _cap The maximum amount of token bits that can be released in one plan each second
    */
    constructor(address _forwarder, address _chainlog, uint256 _cap) DssVest(_forwarder, _cap) {
        initialize(_chainlog, _msgSender(), _cap);
    }

    function initialize(address _chainlog, address _ward, uint256 _cap) initializer public {
        super.initialize(_ward, _cap);
        require(_chainlog != address(0), "DssVestSuckable/Invalid-chainlog-address");
        ChainlogLike chainlog_ = chainlog = ChainlogLike(_chainlog);
        VatLike vat_ = vat = VatLike(chainlog_.getAddress("MCD_VAT"));
        DaiJoinLike daiJoin_ = daiJoin = DaiJoinLike(chainlog_.getAddress("MCD_JOIN_DAI"));

        vat_.hope(address(daiJoin_));
    }

    /**
        @dev Override pay to handle suck logic
        @param _guy The recipient of the ERC-20 Dai
        @param _amt The amount of Dai to send to the _guy [WAD]
    */
    function pay(address _guy, uint256 _amt) override internal {
        require(vat.live() == 1, "DssVestSuckable/vat-not-live");
        vat.suck(chainlog.getAddress("MCD_VOW"), address(this), mul(_amt, RAY));
        daiJoin.exit(_guy, _amt);
    }
}

/*
    Transferrable token DssVest. Can be used to enable streaming payments of
     any arbitrary token from an address (i.e. CU multisig) to individual
     contributors.
*/
contract DssVestTransferrable is DssVest {

    address   public czar;
    TokenLike public gem;

    /**
        @dev This contract must be approved for transfer of the gem on the czar
        @param _forwarder The address of the trusted forwarder for ERC2771
        @param _czar The owner of the tokens to be distributed
        @param _gem  The token to be distributed
        @param _cap The maximum amount of token bits that can be released in one plan each second
    */
    constructor(address _forwarder, address _czar, address _gem, uint256 _cap) DssVest(_forwarder, _cap) {
        initialize(_czar, _gem, _msgSender(), _cap);    
    }

    function initialize(address _czar, address _gem, address _ward, uint256 _cap) initializer public {
        // call parent initializer
        super.initialize(_ward, _cap);
        require(_czar != address(0), "DssVestTransferrable/Invalid-distributor-address");
        require(_gem  != address(0), "DssVestTransferrable/Invalid-token-address");
        czar = _czar;
        gem = TokenLike(_gem);
    }

    /**
        @dev Override pay to handle transfer logic
        @param _guy The recipient of the ERC-20 Dai
        @param _amt The amount of gem to send to the _guy (in native token units)
    */
    function pay(address _guy, uint256 _amt) override internal {
        // if this contract is its own czar, call transfer directly 
        if (czar == address(this))
            require(gem.transfer(_guy, _amt), "DssVestTransferrable/failed-transfer"); 
        else
            require(gem.transferFrom(czar, _guy, _amt), "DssVestTransferrable/failed-transfer");
    }
}

