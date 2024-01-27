import hre, {ethers, upgrades} from "hardhat";
import {networkConstants} from "../constants/network_constants";
import {verifyContracts} from "./helpers";
import {SamWitchOrderBook} from "../typechain-types";

// Deploy everything
async function main() {
  const [owner] = await ethers.getSigners();
  console.log(
    `Deploying contracts with the account: ${owner.address} on chain id: ${(await ethers.provider.getNetwork()).chainId}`,
  );

  const brush = "0x85dec8c4B2680793661bCA91a8F129607571863d";
  const dev = "0x045eF160107eD663D10c5a31c7D2EC5527eea1D0";
  // estforItemsLive = 0x4b9c90ebb1fa98d9724db46c4689994b46706f5a
  let estforItems = "0x1dae89b469d15b0ded980007dfdc8e68c363203d";
  if ((await ethers.provider.getNetwork()).chainId == 31337n) {
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
  console.log("Deployed SamWitchOrderBook to:", await swob.getAddress());

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
