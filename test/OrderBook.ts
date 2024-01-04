import {loadFixture} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import {ethers, upgrades} from "hardhat";
import {expect} from "chai";
import {OrderBook} from "../typechain-types";

describe("OrderBook", function () {
  enum OrderSide {
    Buy,
    Sell,
  }

  async function deployContractsFixture() {
    const [owner, alice, bob, charlie, dev, erin, frank] = await ethers.getSigners();

    const brush = await ethers.deployContract("MockBrushToken");
    const erc1155 = await ethers.deployContract("MockERC1155");

    const OrderBook = await ethers.getContractFactory("OrderBook");
    const orderBook = (await upgrades.deployProxy(
      OrderBook,
      [await erc1155.getAddress(), await brush.getAddress(), dev.address],
      {
        kind: "uups",
      }
    )) as OrderBook;

    const initialBrush = 1000000;
    await brush.mint(owner.address, initialBrush);
    await brush.approve(orderBook, initialBrush);

    await brush.connect(alice).mint(alice.address, initialBrush);
    await brush.connect(alice).approve(orderBook, initialBrush);

    const initialQuantity = 100;
    await erc1155.mint(initialQuantity * 2);
    await erc1155.setApprovalForAll(orderBook, true);

    const tokenId = 1;
    await erc1155.safeTransferFrom(owner, alice, tokenId, initialQuantity, "0x");
    await erc1155.connect(alice).setApprovalForAll(orderBook, true);

    return {
      orderBook,
      erc1155,
      brush,
      owner,
      alice,
      bob,
      charlie,
      dev,
      erin,
      frank,
      initialBrush,
      tokenId,
      initialQuantity,
    };
  }

  it("Add to order book", async function () {
    const {orderBook, tokenId} = await loadFixture(deployContractsFixture);

    const price = 100;
    const quantity = 10;

    await orderBook.limitOrder(OrderSide.Buy, tokenId, price, quantity);
    expect(await orderBook.getHighestBid(tokenId)).to.equal(price);

    await orderBook.limitOrder(OrderSide.Sell, tokenId, price + 1, quantity);
    expect(await orderBook.getLowestAsk(tokenId)).to.equal(price + 1);
  });

  it("Take from order book", async function () {
    const {orderBook, erc1155, brush, initialQuantity, alice, tokenId} = await loadFixture(deployContractsFixture);

    // Set up order books
    const price = 100;
    const quantity = 10;
    await orderBook.limitOrder(OrderSide.Buy, tokenId, price, quantity);
    await orderBook.limitOrder(OrderSide.Sell, tokenId, price + 1, quantity);

    // Buy
    await brush.mint(alice, 1000000);
    await brush.connect(alice).approve(orderBook, 1000000);
    const numToBuy = 2;
    await orderBook.connect(alice).limitOrder(OrderSide.Buy, tokenId, price + 1, numToBuy);
    expect(await erc1155.balanceOf(alice.address, tokenId)).to.equal(initialQuantity + numToBuy);

    await orderBook.connect(alice).limitOrder(OrderSide.Buy, tokenId, price + 2, quantity - numToBuy); // Buy the rest
    expect(await erc1155.balanceOf(alice.address, tokenId)).to.equal(initialQuantity + quantity);

    // There's nothing left, this adds to the buy order side
    await orderBook.connect(alice).limitOrder(OrderSide.Buy, tokenId, price + 2, 1);
    expect(await orderBook.getHighestBid(tokenId)).to.equal(price + 2);
  });

  it("Cancel an order", async function () {
    const {orderBook, tokenId} = await loadFixture(deployContractsFixture);

    // Set up order books
    const price = 100;
    const quantity = 10;
    await orderBook.limitOrder(OrderSide.Buy, tokenId, price, quantity);
    await orderBook.limitOrder(OrderSide.Sell, tokenId, price + 1, quantity);

    // Cancel buy
    const orderId = 1;
    await orderBook.cancelOrder(OrderSide.Buy, orderId, tokenId, price);

    // No longer exists
    await expect(orderBook.cancelOrder(OrderSide.Buy, orderId, tokenId, price)).to.be.revertedWithCustomError(
      orderBook,
      "OrderNotFound"
    );

    // Cancel the sell
    await orderBook.cancelOrder(OrderSide.Sell, orderId + 1, tokenId, price + 1);

    // No longer exists
    await expect(orderBook.cancelOrder(OrderSide.Sell, orderId + 1, tokenId, price + 1)).to.be.revertedWithCustomError(
      orderBook,
      "OrderNotFound"
    );
  });

  it("Cancel an order at the beginning, middle and end", async function () {
    const {orderBook, tokenId} = await loadFixture(deployContractsFixture);

    // Set up order books
    const price = 100;
    const quantity = 10;
    await orderBook.limitOrder(OrderSide.Buy, tokenId, price, quantity);
    await orderBook.limitOrder(OrderSide.Buy, tokenId, price, quantity);
    await orderBook.limitOrder(OrderSide.Buy, tokenId, price, quantity);
    await orderBook.limitOrder(OrderSide.Buy, tokenId, price, quantity);

    // Cancel a buy in the middle
    const orderId = 2;
    await orderBook.cancelOrder(OrderSide.Buy, orderId, tokenId, price);
    // Cancel a buy at the start
    await orderBook.cancelOrder(OrderSide.Buy, orderId - 1, tokenId, price);

    // Cancel a buy at the end
    await orderBook.cancelOrder(OrderSide.Buy, orderId + 2, tokenId, price);

    // The only one left should be orderId 3
    const orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price);
    expect(orders.length).to.eq(1);
    expect(orders[0].id).to.eq(orderId + 1);
  });

  it("Full order consumption, sell side", async function () {
    const {orderBook, alice, tokenId} = await loadFixture(deployContractsFixture);

    // Set up order book
    const price = 100;
    const quantity = 10;
    await orderBook.limitOrder(OrderSide.Sell, tokenId, price, quantity);
    await orderBook.limitOrder(OrderSide.Sell, tokenId, price, quantity);
    await orderBook.limitOrder(OrderSide.Sell, tokenId, price, quantity);

    // Buy
    const numToBuy = 14; // Finish one and eat into the next

    await orderBook.connect(alice).limitOrder(OrderSide.Buy, tokenId, price, numToBuy);

    let orders = await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price);
    const orderId = 1;
    expect(orders.length).to.eq(2);
    expect(orders[0].id).to.eq(orderId + 1);
    expect(orders[1].id).to.eq(orderId + 2);

    const node = await orderBook.getNode(OrderSide.Sell, tokenId, price);
    expect(node.tombstoneOffset).to.eq(1);

    const remainderQuantity = quantity * 3 - numToBuy;
    // Try to buy too many
    await orderBook.connect(alice).limitOrder(OrderSide.Buy, tokenId, price, remainderQuantity + 1);

    orders = await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price);
    expect(orders.length).to.eq(0);
  });

  it("Full order consumption, buy side", async function () {
    const {orderBook, alice, tokenId} = await loadFixture(deployContractsFixture);

    // Set up order book
    const price = 100;
    const quantity = 10;
    await orderBook.limitOrder(OrderSide.Buy, tokenId, price, quantity);
    await orderBook.limitOrder(OrderSide.Buy, tokenId, price, quantity);
    await orderBook.limitOrder(OrderSide.Buy, tokenId, price, quantity);

    // Sell
    const numToSell = 14; // Finish one and eat into the next
    await orderBook.connect(alice).limitOrder(OrderSide.Sell, tokenId, price, numToSell);

    let orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price);
    const orderId = 1;
    expect(orders.length).to.eq(2);
    expect(orders[0].id).to.eq(orderId + 1);
    expect(orders[1].id).to.eq(orderId + 2);

    const node = await orderBook.getNode(OrderSide.Buy, tokenId, price);
    expect(node.tombstoneOffset).to.eq(1);

    const remainderQuantity = quantity * 3 - numToSell;
    // Try to sell too many
    await orderBook.connect(alice).limitOrder(OrderSide.Sell, tokenId, price, remainderQuantity + 1);

    orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price);
    expect(orders.length).to.eq(0);
  });

  it("Partial order consumption", async function () {});

  it("Edit order", async function () {});

  // Test dev fee
  // Test royalty is paid
  // Test multiple tokenIds
  // Test claiming nfts/brush (is gas more efficient by just sending the nft/brush directly?)
  // Test max number of prices in the order book entry
  // Test cancelling order
  // Test editing order (once implemented)
  // Test bulk insert/cancel/edit
  // Remove id and only allow 1 order per address?
  // Test gas with a large amount of orders
  // Fuzz test of many orders
  // Can take from yourself?
});
