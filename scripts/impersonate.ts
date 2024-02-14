import {ethers, upgrades} from "hardhat";
import {OrderSide, swobAddress} from "./helpers";
import {SamWitchOrderBook} from "../typechain-types";
import {EventLog} from "ethers";

async function main() {
  const network = await ethers.provider.getNetwork();
  console.log(`ChainId: ${network.chainId}`);

  const owner = await ethers.getImpersonatedSigner("0x316342122A9ae36de41B231260579b92F4C8Be7f");
  const user = await ethers.getImpersonatedSigner("0xEC08Fa2f34dD9ab9A53b956ddDAA17e9972Ee006");
  const timeout = 600 * 1000; // 10 minutes

  const SamWitchOrderBook = (await ethers.getContractFactory("SamWitchOrderBook")).connect(owner);
  const swob = (await upgrades.upgradeProxy(swobAddress, SamWitchOrderBook, {
    kind: "uups",
    timeout,
  })) as unknown as SamWitchOrderBook;
  await swob.waitForDeployment();

  const tx = await swob
    .connect(user)
    .limitOrders([{side: OrderSide.Sell, tokenId: 2816, price: 70000000000000, quantity: 3}]);
  const receipt = await tx.wait();
  console.log((receipt?.logs[0] as EventLog).args);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
