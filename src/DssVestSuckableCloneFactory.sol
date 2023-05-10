// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {DssVestSuckable} from "./DssVest.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract DssVestSuckableCloneFactory {
    address immutable vestingImplementation;

    constructor(address _implementation) {
        vestingImplementation = _implementation;
    }

    function createSuckableVestingClone(address chainlog, address ward) external returns (address) {
        address clone = Clones.clone(vestingImplementation);
        DssVestSuckable(clone).initialize(chainlog, ward);
        return clone;
    }
}