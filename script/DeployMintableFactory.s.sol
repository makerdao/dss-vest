// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../lib/forge-std/src/Script.sol";
import "../src/DssVest.sol";
import "../src/DssVestMintableCloneFactory.sol";

contract DeployMintableCloneFactory is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deploying from: ", deployerAddress );

        address forwarder = vm.envAddress("FORWARDER_MAINNET");
        address gem = address(0xdeadbeef);
        uint256 cap = 42 * 10 ** 18;
        
        vm.startBroadcast(deployerPrivateKey);
        DssVestMintable mintable = new DssVestMintable(forwarder, gem, cap);
        console.log("DssVestMintable logic contract deployed at: ", address(mintable));

        console.log("Removing ward from logic contract. Deployer is ward: ", mintable.wards(deployerAddress));
        mintable.deny(deployerAddress);
        console.log("Logic contract still has ward: ", mintable.wards(deployerAddress));

        
        DssVestMintableCloneFactory factory = new DssVestMintableCloneFactory(address(mintable));
        console.log("DssVestMintableCloneFactory deployed at: ", address(factory));

        vm.stopBroadcast();
    }
}
