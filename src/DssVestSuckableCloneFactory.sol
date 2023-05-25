// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {DssVestSuckable} from "./DssVest.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract DssVestSuckableCloneFactory {
    event NewClone(address clone);

    DssVestSuckable immutable vestingImplementation;

    constructor(DssVestSuckable _implementation) {
        vestingImplementation = _implementation;
    }

    /**
        @notice Creates a new DssVestSuckable contract and initializes it.
        @dev The trusted forwarder of the implementation is reused, it can not be updated.
        @param chainlog The address of the chainlog contract
        @param ward The address that will be the first ward of the contract
     */
    function createSuckableVestingClone(address chainlog, address ward) external returns (address) {
        address clone = Clones.clone(address(vestingImplementation));
        DssVestSuckable(clone).initialize(chainlog, ward);
        emit NewClone(clone);
        return clone;
    }
}