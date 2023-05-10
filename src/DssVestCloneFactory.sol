// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {DssVestMintable} from "./DssVest.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract DssVestCloneFactory {
    address immutable vestingImplementation;

    constructor(address _implementation) {
        vestingImplementation = _implementation;
    }

    function createVestingClone(address companyToken, address companyAdminAddress) external returns (address) {
        address clone = Clones.clone(vestingImplementation);
        DssVestMintable(clone).initialize(companyToken, companyAdminAddress);
        return clone;
    }
}