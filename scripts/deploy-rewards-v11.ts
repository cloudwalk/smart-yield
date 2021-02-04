import { ethers } from "hardhat";

async function main() {    
  const Rewards = await ethers.getContractFactory("RewardsV1_1");
  const rewards = await Rewards.deploy();
  await rewards.deployed();
  console.log("RewardsV1_1 deployed to:", rewards.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });