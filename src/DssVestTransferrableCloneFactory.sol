// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {DssVestTransferrable} from "./DssVest.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract DssVestTransferrableCloneFactory {
    DssVestTransferrable immutable vestingImplementation;

    constructor(DssVestTransferrable _implementation) {
        vestingImplementation = _implementation;
    }
    /**
    @notice Creates a new DssVestMintable contract and initializes it.
    @dev The trusted forwarder of the implementation is reused, it can not be updated.
    @param czar The address where the gem is held
    @param gem The address of the ERC-20 token to be vested
    @param ward The address that will be the first ward of the contract
     */
    function createTransferrableVestingClone(address czar, address gem, address ward) external returns (address) {
        address clone = Clones.clone(address(vestingImplementation));
        DssVestTransferrable(clone).initialize(czar, gem, ward);
        return clone;
    }
}