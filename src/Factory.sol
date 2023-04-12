// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {DssVestMintable} from "./DssVest.sol";

contract DssVestNaiveFactory {

    function createDssVestMintable(address forwarder, address companyToken, address companyAdminAddress) external returns (address) {
        DssVestMintable myContract = new DssVestMintable(forwarder, companyToken);
        myContract.rely(companyAdminAddress);
        myContract.deny(address(this));
        return address(myContract);
    }
}