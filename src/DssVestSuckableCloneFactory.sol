// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {DssVestCloneFactory} from "./DssVestCloneFactory.sol";
import {DssVestSuckable} from "./DssVest.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract DssVestSuckableCloneFactory is DssVestCloneFactory {

    constructor(address _implementation) DssVestCloneFactory(_implementation) {}

    /**
     * @notice Creates a new DssVestSuckable contract and initializes it.
     * @dev The trusted forwarder of the implementation is reused, it can not be updated.
     * @param salt The salt used to deterministically generate the clone address
     * @param chainlog The address of the chainlog contract
     * @param ward The address that will be the first ward of the contract
     * @return The address of the newly created clone
     */
    function createSuckableVestingClone(bytes32 salt, address chainlog, address ward, uint256 cap) external returns (address) {
        address clone = Clones.cloneDeterministic(implementation, salt);
        DssVestSuckable(clone).initialize(chainlog, ward, cap);
        emit NewClone(clone);
        return clone;
    }
}