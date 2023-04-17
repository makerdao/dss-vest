// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import {DssVestMintable} from "./DssVest.sol";

contract DssVestNaiveFactory {

    event DssVestMintableCreated(address dssVestMintable, address indexed companyAdminAddress);

    /**
    @dev Creates a new DssVestMintable contract and transfers the ownership to the companyAdminAddress
    @param forwarder The address of the TRUSTED forwarder contract for ERC-2771
    @param companyToken The address of the ERC-20 token to be vested
    @param companyAdminAddress The address of the company admin that will be the first ward of the contract
     */
    function createDssVestMintable(address forwarder, address companyToken, address companyAdminAddress) external returns (address) {
        DssVestMintable myContract = new DssVestMintable(forwarder, companyToken);
        myContract.rely(companyAdminAddress);
        myContract.deny(address(this));
        emit DssVestMintableCreated(address(myContract), companyAdminAddress);
        return address(myContract);
    }
}