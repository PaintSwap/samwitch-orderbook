import hre, {ethers, upgrades} from "hardhat";
import {swobAddress, verifyContracts} from "./helpers";
import {SamWitchOrderBook} from "../typechain-types";
import {networkConstants} from "../constants/network_constants";

// Upgrade order book
async function main() {
  const [owner] = await ethers.getSigners();
  console.log(
    `Upgrading contracts with the account: ${owner.address} on chain id: ${(await ethers.provider.getNetwork()).chainId}`,
  );

  const timeout = 600 * 1000; // 10 minutes

  const SamWitchOrderBook = await ethers.getContractFactory("SamWitchOrderBook");
  const swob = (await upgrades.upgradeProxy(swobAddress, SamWitchOrderBook, {
    kind: "uups",
    timeout,
  })) as unknown as SamWitchOrderBook;
  await swob.waitForDeployment();

  const {shouldVerify} = await networkConstants(hre);
  if (shouldVerify) {
    try {
      const addresses: string[] = [await swob.getAddress()];
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
