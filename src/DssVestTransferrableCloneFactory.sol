// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {DssVestTransferrable} from "./DssVest.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract DssVestTransferrableCloneFactory {
    address immutable vestingImplementation;

    constructor(address _implementation) {
        vestingImplementation = _implementation;
    }

    function createTransferrableVestingClone(address czar, address gem, address ward) external returns (address) {
        address clone = Clones.clone(vestingImplementation);
        DssVestTransferrable(clone).initialize(czar, gem, ward);
        return clone;
    }
}