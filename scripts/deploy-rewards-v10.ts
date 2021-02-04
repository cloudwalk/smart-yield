import { ethers } from "hardhat";

async function main() {    
  const Rewards = await ethers.getContractFactory("RewardsV1_0");
  const rewards = await Rewards.deploy();
  await rewards.deployed();
  console.log("RewardsV1_0 deployed to:", rewards.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });