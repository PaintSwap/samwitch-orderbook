import hre, {ethers, upgrades} from "hardhat";
import {networkConstants} from "../constants/network_constants";
import {verifyContracts} from "./helpers";

// Deploy everything
async function main() {
  const [owner] = await ethers.getSigners();
  console.log(`Deploying contracts with the account: ${owner.address} on chain id: ${await owner.getChainId()}`);

  const {shouldVerify} = await networkConstants(hre);

  if (shouldVerify) {
    try {
      const addresses: string[] = [];
      console.log("Verifying contracts...");
      await verifyContracts(addresses);
    } catch (e) {
      console.log(e);
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
