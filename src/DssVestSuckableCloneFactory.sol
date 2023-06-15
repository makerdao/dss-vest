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
     * @notice Creates a new DssVestSuckable contract and initializes it.
     * @dev The trusted forwarder of the implementation is reused, it can not be updated.
     * @param salt The salt used to deterministically generate the clone address
     * @param chainlog The address of the chainlog contract
     * @param ward The address that will be the first ward of the contract
     * @return The address of the newly created clone
     */
    function createSuckableVestingClone(bytes32 salt, address chainlog, address ward) external returns (address) {
        address clone = Clones.cloneDeterministic(address(vestingImplementation), salt);
        DssVestSuckable(clone).initialize(chainlog, ward);
        emit NewClone(clone);
        return clone;
    }
}