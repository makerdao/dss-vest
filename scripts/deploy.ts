// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const Token = await ethers.getContractFactory("Token");
  
  const signers = await ethers.getSigners();

  const admin = "0x6CcD9E07b035f9E6e7f086f3EaCf940187d03A29"; // testing founder
  const allowList = "0x274ca5f21Cdde06B6E4Fe063f5087EB6Cf3eAe55";
  const name = "MyTasticToken";
  const symbol = "MTT";
  const forwarder = "0x0445d09A1917196E1DC12EdB7334C70c1FfB1623";
  const feeSettings = "0x147addF9C8E4030F8104c713Dad2A1d76E6c85a1";
  const requirements = 0x0;


  const token = await Token.deploy(
    forwarder,
    feeSettings,
    admin,
    allowList,
    requirements,
    name,
    symbol
  );

  await token.deployed();

  console.log("Token deployed to:", token.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
