// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/proxy/Clones.sol";

abstract contract  DssVestCloneFactory {
    event NewClone(address clone);

    /// The address of the implementation to clone
    address immutable implementation;

    constructor(address _implementation) {
        require(_implementation != address(0), "DssVestCloneFactory/null-implementation");
        implementation = _implementation;

    }

    /**
     * @notice Predicts the address of a clone that will be created
     * @param salt The salt used to deterministically generate the clone address
     * @return The address of the clone that will be created
     * @dev This function does not check if the clone has already been created
     */
    function predictCloneAddress(bytes32 salt)
        public
        view
        returns (address)
    {
        return
            Clones.predictDeterministicAddress(
                implementation,
                salt
            );
    }
}