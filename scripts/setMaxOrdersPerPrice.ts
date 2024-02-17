import {ethers} from "hardhat";
import {swobAddress} from "./helpers";

async function main() {
  const [owner] = await ethers.getSigners();
  console.log(
    `Setting setMaxOrdersPerPrice with the account: ${owner.address} on chain id: ${(await ethers.provider.getNetwork()).chainId}`,
  );

  const samWitchOrderBook = await ethers.getContractAt("SamWitchOrderBook", swobAddress);
  const tx = await samWitchOrderBook.setMaxOrdersPerPrice(12);
  await tx.wait();
  console.log("orderBook.setMaxOrdersPerPrice");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
