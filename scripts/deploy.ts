import "@nomicfoundation/hardhat-verify";
import hre, { ethers, network } from "hardhat";

const WNATIVE_ADDR = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
const AGGREGATOR_ADDR = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";

async function main() {
  const [owner, liquidityAcc, taxAcc] = await ethers.getSigners();
  const liquidityAddr = await liquidityAcc.getAddress();
  const taxAddr = await taxAcc.getAddress();

  let wnativeAddr = WNATIVE_ADDR;
  let aggregatorAddr = AGGREGATOR_ADDR;

  if (wnativeAddr == "") {
    const wnativeFactory = await ethers.deployContract("WNATIVE");

    wnativeAddr = await wnativeFactory.getAddress();
    console.log("WNATIVE: ", wnativeAddr);
  }

  if (aggregatorAddr == "") {
    const aggrFactory = await ethers.deployContract("MockAggregator");

    aggregatorAddr = await aggrFactory.getAddress();
    console.log("AGGREGATOR: ", aggregatorAddr);
  }

  const dohl = await ethers.deployContract("DOHL");
  await dohl.deploymentTransaction();

  const dohlAddr = await dohl.getAddress();
  console.log("Address is ", dohlAddr, "on network", network.name);

  await dohl.initialize(liquidityAddr, aggregatorAddr, wnativeAddr, taxAddr);
  console.log("DOHL successfully init");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
