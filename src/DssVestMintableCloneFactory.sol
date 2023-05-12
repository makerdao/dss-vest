// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {DssVestMintable} from "./DssVest.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract DssVestMintableCloneFactory {
    /// The address of the implementation to clone
    DssVestMintable immutable vestingImplementation;

    constructor(DssVestMintable _implementation) {
        vestingImplementation = _implementation;
    }

    /**
    @notice Creates a new DssVestMintable contract and initializes it.
    @dev The trusted forwarder of the implementation is reused, it can not be updated.
    @param gem The address of the ERC-20 token to be vested
    @param ward The address that will be the first ward of the contract
     */
    function createMintableVestingClone(address gem, address ward) external returns (address) {
        address clone = Clones.clone(address(vestingImplementation));
        DssVestMintable(clone).initialize(gem, ward);
        return clone;
    }
}