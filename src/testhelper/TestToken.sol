pragma solidity 0.6.7;

import "ds-token/token.sol";

contract TestToken is DSToken {
    constructor(bytes32 symbol_, uint256 decimals_) public DSToken(symbol_) {decimals = decimals_;}
}