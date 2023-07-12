// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

import "../../lib/forge-std/src/Test.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../src/DssVest.sol";


/**
   @dev TestHelperct is used to test the DssVest contract. It is a ERC20 token that can be minted by anyone.
 */
contract TestHelper is Test {
    uint256 public constant  TWENTY_YEARS = 20 * 365 days;


    function checkBounds(address _usr, uint128 _tot, uint48 _bgn, uint48 _tau, uint48 _eta, uint256 _timestamp, address forwarder) public pure returns (bool) {
        return _usr != address(0) 
            && _usr != address(forwarder)
            && _tot != 0 
            && _bgn > _timestamp - TWENTY_YEARS + 1 days 
            && _bgn < _timestamp + TWENTY_YEARS - 1 days
            && _tau < TWENTY_YEARS
            && _eta < _tau;
    }
} 