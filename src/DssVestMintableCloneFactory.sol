// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {DssVestMintable} from "./DssVest.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract DssVestMintableCloneFactory {
    address immutable vestingImplementation;

    constructor(address _implementation) {
        vestingImplementation = _implementation;
    }

    function createMintableVestingClone(address companyToken, address companyAdminAddress) external returns (address) {
        address clone = Clones.clone(vestingImplementation);
        DssVestMintable(clone).initialize(companyToken, companyAdminAddress);
        return clone;
    }
}