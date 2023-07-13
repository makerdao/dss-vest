// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {DssVestCloneFactory} from "./DssVestCloneFactory.sol";
import {DssVestMintable} from "./DssVest.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract DssVestMintableCloneFactory is DssVestCloneFactory {

    constructor(address _implementation) DssVestCloneFactory(_implementation) {}

    /**
     * @notice Creates a new DssVestMintable contract and initializes it.
     * @dev The trusted forwarder of the implementation is reused, it can not be updated.
     * @param salt The salt used to deterministically generate the clone address
     * @param gem The address of the ERC-20 token to be vested
     * @param ward The address that will be the first ward of the contract
     * @return The address of the newly created clone
     */
    function createMintableVestingClone(bytes32 salt, address gem, address ward, uint256 cap) external returns (address) {
        address clone = Clones.cloneDeterministic(implementation, salt);
        DssVestMintable(clone).initialize(gem, ward, cap);
        emit NewClone(clone);
        return clone;
    }
}