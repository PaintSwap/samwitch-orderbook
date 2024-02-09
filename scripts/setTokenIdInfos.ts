import {ethers} from "hardhat";
import {swobAddress} from "./helpers";

async function main() {
  const [owner] = await ethers.getSigners();
  console.log(
    `Setting token id infos with the account: ${owner.address} on chain id: ${(await ethers.provider.getNetwork()).chainId}`,
  );

  const samWitchOrderBook = await ethers.getContractAt("SamWitchOrderBook", swobAddress);
  const tokenId = 2816;
  const tick = ethers.parseEther("0.00001");
  const tx = await samWitchOrderBook.setTokenIdInfos(
    [tokenId, tokenId + 1, tokenId + 2],
    [
      {tick, minQuantity: 3},
      {tick, minQuantity: 4},
      {tick, minQuantity: 5},
    ],
    {gasLimit: 1000000},
  );
  await tx.wait();
  console.log("orderBook.setTokenIdInfos");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
