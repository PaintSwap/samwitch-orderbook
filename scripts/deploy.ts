import hre, {ethers, upgrades} from "hardhat";
import {networkConstants} from "../constants/network_constants";
import {verifyContracts} from "./helpers";
import {SamWitchOrderBook} from "../typechain-types";

// Deploy everything
async function main() {
  const [owner] = await ethers.getSigners();
  console.log(`Deploying contracts with the account: ${owner.address} on chain id: ${hre.network.config.chainId}`);

  const {shouldVerify} = await networkConstants(hre);

  const brush = "0x85dec8c4B2680793661bCA91a8F129607571863d";
  const dev = "0x3b99636439FBA6314C0F52D35FEd2fF442191407";
  let estforItems = "0x4b9c90ebb1fa98d9724db46c4689994b46706f5a";
  if (hre.network.config.chainId == 31337) {
    const erc1155 = await ethers.deployContract("MockERC1155", [dev]);
    estforItems = await erc1155.getAddress();
  }

  // Deploy SamWitchOrderBook
  const maxOrdersPerPrice = 100;
  const SamWitchOrderBook = await ethers.getContractFactory("SamWitchOrderBook");
  const swob = (await upgrades.deployProxy(SamWitchOrderBook, [estforItems, brush, dev, 30, 30, maxOrdersPerPrice], {
    kind: "uups",
  })) as unknown as SamWitchOrderBook;
  await swob.waitForDeployment();

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
