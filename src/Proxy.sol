// // SPDX-License-Identifier: MIT
// //
// // Copyright (C) 2023 malteish
// //


// pragma solidity 0.8.17;

// import "@openzeppelin/contracts/proxy/Proxy.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "./DssVest.sol";

// contract DssVestMintableProxy is TransparentUpgradeableProxy {
//     constructor(address implementation, address trustedForwarder, address ward, IERC20 token) {
//         //_setImplementation(implementation);
//         DssVestMintable(implementation).initialize(trustedForwarder, ward, token);
//     }

//     function _implementation() internal view virtual override returns (address) {
//         return address(this);
//     }

//     function _beforeFallback() internal virtual override {
//         // This is a no-op function that is meant to be overridden by the user
//         // to add custom logic before the fallback function is executed.
//     }
// }
