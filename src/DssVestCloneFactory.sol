// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./DssVest.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract DssVestCloneFactory {
    address immutable vestingImplementation;

    constructor(address _implementation) {
        vestingImplementation = _implementation;
    }

    function createMintableVestingClone(address companyToken, address companyAdminAddress) external returns (address) {
        address clone = Clones.clone(vestingImplementation);
        DssVestMintable(clone).initialize(companyToken, companyAdminAddress);
        return clone;
    }

    function createTransferrableVestingClone(address czar, address gem, address ward) external returns (address) {
        address clone = Clones.clone(vestingImplementation);
        DssVestTransferrable(clone).initialize(czar, gem, ward);
        return clone;
    }

    function createSuckableVestingClone(address companyToken, address companyAdminAddress) external returns (address) {
        address clone = Clones.clone(vestingImplementation);
        DssVestMintable(clone).initialize(companyToken, companyAdminAddress);
        return clone;
    }
}