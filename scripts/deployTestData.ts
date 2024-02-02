import {ethers} from "hardhat";
import {IERC20, MockERC1155, SamWitchOrderBook} from "../typechain-types";
import {swobAddress} from "./helpers";

enum OrderSide {
  Buy,
  Sell,
}

async function main() {
  const [owner] = await ethers.getSigners();
  console.log(
    `Deploying test data with the account: ${owner.address} on chain id: ${(await ethers.provider.getNetwork()).chainId}`,
  );

  const orderBook = (await ethers.getContractAt("SamWitchOrderBook", swobAddress)) as SamWitchOrderBook;

  const tokenId = 2816; // Estfor bronze axe
  const tick = ethers.parseEther("0.00001");
  // Set up order books
  const price = tick * 10n;
  const quantity = 10;

  const brush = (await ethers.getContractAt("IERC20", "0x85dec8c4B2680793661bCA91a8F129607571863d")) as IERC20;
  let tx = await brush.approve(orderBook, ethers.parseEther("10"));
  await tx.wait();
  console.log("brush.approve");

  const erc1155 = (await ethers.getContractAt(
    "MockERC1155",
    "0x1dae89b469d15b0ded980007dfdc8e68c363203d",
  )) as MockERC1155;
  tx = await erc1155.setApprovalForAll(orderBook, true);
  await tx.wait();
  console.log("erc1155.setApprovalForAll");

  tx = await orderBook.setTokenInfos(
    [tokenId, tokenId + 1, tokenId + 2],
    [
      {tick, minQuantity: 3},
      {tick, minQuantity: 4},
      {tick, minQuantity: 5},
    ],
  );
  await tx.wait();
  console.log("orderBook.setTokenInfos");

  tx = await orderBook.limitOrders([
    {
      side: OrderSide.Buy,
      tokenId,
      price,
      quantity,
    },
    {
      side: OrderSide.Sell,
      tokenId,
      price: price + tick,
      quantity,
    },
    {
      side: OrderSide.Sell,
      tokenId,
      price: price + 2n * tick,
      quantity,
    },
  ]);
  await tx.wait();
  console.log("orderBook.limitOrders - initial orders");

  // Cancel buy
  const orderId = 1;
  tx = await orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]);
  await tx.wait();
  console.log("orderBook.cancelOrders");

  // Add a couple buys
  tx = await orderBook.limitOrders([
    {
      side: OrderSide.Buy,
      tokenId,
      price: price - tick,
      quantity,
    },
    {
      side: OrderSide.Buy,
      tokenId,
      price: price - 3n * tick,
      quantity,
    },
  ]);
  await tx.wait();
  console.log("orderBook.limitOrders");

  // Remove a whole sell order and eat into the next
  tx = await orderBook.limitOrders([
    {
      side: OrderSide.Buy,
      tokenId,
      price: price + 2n * tick,
      quantity: quantity + quantity / 2,
    },
  ]);
  await tx.wait();
  console.log("orderBook.limitOrders - Buy and consume a whole order and a bit");

  tx = await orderBook.limitOrders([
    {
      side: OrderSide.Sell,
      tokenId,
      price: price - tick,
      quantity: quantity - 3,
    },
  ]);
  await tx.wait();
  console.log("orderBook.limitOrders - Sell and consume a bit");

  // Failed to order book
  tx = await orderBook.limitOrders([
    {
      side: OrderSide.Sell,
      tokenId,
      price: price - tick,
      quantity: 4,
    },
  ]);
  await tx.wait();
  console.log("orderBook.limitOrders - Some failed to sell");

  // Claim nft
  tx = await orderBook.claimNFTs([4], [tokenId]);
  await tx.wait();
  console.log("claimNFTs");
  // Claim token
  tx = await orderBook.claimTokens([2, 3]);
  await tx.wait();
  console.log("claimTokens");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
