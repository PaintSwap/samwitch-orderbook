import {loadFixture} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import {ethers, upgrades} from "hardhat";
import {expect} from "chai";
import {ISamWitchOrderBook, SamWitchOrderBook} from "../typechain-types";

describe("SamWitchOrderBook", function () {
  enum OrderSide {
    Buy,
    Sell,
  }

  async function deployContractsFixture() {
    const [owner, alice, bob, charlie, dev, erin, frank, royaltyRecipient] = await ethers.getSigners();

    const brush = await ethers.deployContract("MockBrushToken");
    const erc1155 = await ethers.deployContract("MockERC1155", [royaltyRecipient.address]);

    const maxOrdersPerPrice = 100;
    const OrderBook = await ethers.getContractFactory("SamWitchOrderBook");
    const orderBook = (await upgrades.deployProxy(
      OrderBook,
      [await erc1155.getAddress(), await brush.getAddress(), dev.address, 30, 30, maxOrdersPerPrice],
      {
        kind: "uups",
      },
    )) as unknown as SamWitchOrderBook;

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

    const tick = 1;
    const minQuantity = 1;
    await orderBook.setTokenIdInfos([tokenId], [{tick, minQuantity}]);

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
      royaltyRecipient,
      initialBrush,
      tokenId,
      initialQuantity,
      maxOrdersPerPrice,
      tick,
      minQuantity,
    };
  }

  it("Add to order book", async function () {
    const {orderBook, tokenId} = await loadFixture(deployContractsFixture);

    const price = 100;
    const quantity = 10;

    await orderBook.limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 1,
        quantity,
      },
    ]);

    expect(await orderBook.getHighestBid(tokenId)).to.equal(price);
    expect(await orderBook.getLowestAsk(tokenId)).to.equal(price + 1);
  });

  it("Take from sell order book", async function () {
    const {orderBook, erc1155, initialQuantity, alice, tokenId} = await loadFixture(deployContractsFixture);

    // Set up order books
    const price = 100;
    const quantity = 10;
    await orderBook.limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 1,
        quantity,
      },
    ]);

    // Buy
    const numToBuy = 2;
    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price: price + 1,
        quantity: numToBuy,
      },
    ]);

    expect(await erc1155.balanceOf(alice.address, tokenId)).to.equal(initialQuantity + numToBuy);

    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price: price + 2,
        quantity: quantity - numToBuy,
      },
    ]); // Buy the rest
    expect(await erc1155.balanceOf(alice.address, tokenId)).to.equal(initialQuantity + quantity);

    // There's nothing left on the sell side, this adds to the buy order side
    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price: price + 2,
        quantity: 1,
      },
    ]);
    expect(await orderBook.getHighestBid(tokenId)).to.equal(price + 2);
  });

  it("Take from buy order book", async function () {
    const {orderBook, erc1155, initialQuantity, alice, tokenId} = await loadFixture(deployContractsFixture);

    // Set up order books
    const price = 100;
    const quantity = 10;
    await orderBook.limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 1,
        quantity,
      },
    ]);

    // Sell
    const numToSell = 2;
    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price: price,
        quantity: numToSell,
      },
    ]);

    expect(await erc1155.balanceOf(alice.address, tokenId)).to.equal(initialQuantity - numToSell);

    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price: price - 1,
        quantity: quantity - numToSell,
      },
    ]); // Buy the rest
    expect(await erc1155.balanceOf(alice.address, tokenId)).to.equal(initialQuantity - quantity);

    // There's nothing left on the sell side, this adds to the buy order side
    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price: price - 1,
        quantity: 1,
      },
    ]);
    expect(await orderBook.getLowestAsk(tokenId)).to.equal(price - 1);
  });

  it("Failed orders", async function () {
    const {orderBook, tokenId, tick} = await loadFixture(deployContractsFixture);

    // Set up order books
    const price = 100;
    const quantity = 10;

    await orderBook.limitOrders([
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
        price: price + 2 * tick,
        quantity,
      },
    ]);

    // Cancel buy
    const orderId = 1;
    await orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]);

    // Add a couple buy orders
    await orderBook.limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price: price - tick,
        quantity,
      },
      {
        side: OrderSide.Buy,
        tokenId,
        price: price - 3 * tick,
        quantity,
      },
    ]);

    // Remove a whole sell order and eat into the next
    await expect(
      orderBook.limitOrders([
        {
          side: OrderSide.Buy,
          tokenId,
          price: price + 2 * tick,
          quantity: quantity + quantity / 2,
        },
      ]),
    ).to.not.emit(orderBook, "FailedToAddToBook");

    const orders = await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + 2 * tick);
    expect(orders.length).to.eq(1);
    expect(orders[0].quantity).eq(quantity / 2);

    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price: price - tick,
        quantity: quantity - 3,
      },
    ]);
    await orderBook.setTokenIdInfos([tokenId], [{tick: 1, minQuantity: 20}]);
    await expect(
      orderBook.limitOrders([
        {
          side: OrderSide.Sell,
          tokenId,
          price: price - tick,
          quantity: quantity,
        },
      ]),
    ).to.emit(orderBook, "FailedToAddToBook");
  });

  describe("Make limit order", function () {
    it("Invalid limit orders", async function () {
      const {orderBook, tokenId} = await loadFixture(deployContractsFixture);

      // Set up order books
      const price = 100;
      const quantity = 10;
      await expect(
        orderBook.limitOrders([
          {
            side: OrderSide.Buy,
            tokenId,
            price,
            quantity: 0,
          },
        ]),
      ).to.be.revertedWithCustomError(orderBook, "NoQuantity");

      await expect(
        orderBook.limitOrders([
          {
            side: OrderSide.Buy,
            tokenId,
            price: 0,
            quantity,
          },
        ]),
      ).to.be.revertedWithCustomError(orderBook, "PriceZero");

      await expect(
        orderBook.limitOrders([
          {
            side: OrderSide.Buy,
            tokenId: tokenId + 1,
            price,
            quantity,
          },
        ]),
      )
        .to.be.revertedWithCustomError(orderBook, "TokenDoesntExist")
        .withArgs(tokenId + 1);
    });
  });

  describe("Cancelling orders", function () {
    it("Cancel a single order", async function () {
      const {orderBook, owner, tokenId, erc1155, brush, initialBrush, initialQuantity} =
        await loadFixture(deployContractsFixture);

      // Set up order books
      const price = 100;
      const quantity = 10;
      await orderBook.limitOrders([
        {
          side: OrderSide.Buy,
          tokenId,
          price,
          quantity,
        },
        {
          side: OrderSide.Sell,
          tokenId,
          price: price + 1,
          quantity,
        },
      ]);

      // Try cancel non-existent order
      await expect(orderBook.cancelOrders([3], [{side: OrderSide.Buy, tokenId, price}])).to.be.revertedWithCustomError(
        orderBook,
        "OrderNotFound",
      );

      // Cancel buy
      const orderId = 1;
      await orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]);

      // No longer exists
      await expect(
        orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]),
      ).to.be.revertedWithCustomError(orderBook, "OrderNotFoundInTree");

      // Cancel the sell
      await orderBook.cancelOrders([orderId + 1], [{side: OrderSide.Sell, tokenId, price: price + 1}]);

      // No longer exists
      await expect(
        orderBook.cancelOrders([orderId + 1], [{side: OrderSide.Sell, tokenId, price: price + 1}]),
      ).to.be.revertedWithCustomError(orderBook, "OrderNotFoundInTree");

      // Check you get the brush back
      expect(await brush.balanceOf(owner)).to.eq(initialBrush);
      expect(await brush.balanceOf(orderBook)).to.eq(0);
      expect(await erc1155.balanceOf(owner.address, tokenId)).to.eq(initialQuantity);

      expect(await orderBook.getHighestBid(tokenId)).to.equal(0);
      expect(await orderBook.getLowestAsk(tokenId)).to.equal(0);
    });

    it("Cancel an order at the beginning, middle and end of the same segment", async function () {
      const {orderBook, owner, tokenId, brush, initialBrush} = await loadFixture(deployContractsFixture);

      // Set up order books
      const price = 100;
      const quantity = 10;

      const limitOrder = {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      };

      const limitOrders = new Array<ISamWitchOrderBook.LimitOrderStruct>(4).fill(limitOrder);
      await orderBook.limitOrders(limitOrders);

      // Cancel a buy in the middle
      const orderId = 2;
      await orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]);
      // Cancel a buy at the start
      await orderBook.cancelOrders([orderId - 1], [{side: OrderSide.Buy, tokenId, price}]);

      // Cancel a buy at the end
      await orderBook.cancelOrders([orderId + 2], [{side: OrderSide.Buy, tokenId, price}]);

      // The only one left should be orderId 3
      const orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price);
      expect(orders.length).to.eq(1);
      expect(orders[0].id).to.eq(orderId + 1);
      // Check you get the brush back
      expect(await brush.balanceOf(owner)).to.eq(initialBrush - price * quantity);
      expect(await brush.balanceOf(orderBook)).to.eq(price * quantity);

      expect(await orderBook.getHighestBid(tokenId)).to.equal(price);
      expect(await orderBook.getLowestAsk(tokenId)).to.equal(0);
    });

    it("Inner segment offsets completing orders", async function () {
      const {orderBook, tokenId} = await loadFixture(deployContractsFixture);

      // Set up order books
      const price = 100;
      const quantity = 10;

      const limitOrders = new Array<ISamWitchOrderBook.LimitOrderStruct>(2).fill({
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      });
      await orderBook.limitOrders(limitOrders);

      // Consume 1 order, check there is only 1 remaining
      await orderBook.limitOrders([{side: OrderSide.Sell, tokenId, price, quantity}]);

      const orderId = 1;
      let orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price);
      expect(orders.length).to.eq(1);
      expect(orders[0].id).to.eq(orderId + 1);
    });

    it("Cancel an order at the beginning, middle and end of the same segment which has a tombstoneOffset", async function () {
      const {orderBook, owner, tokenId, brush, initialBrush} = await loadFixture(deployContractsFixture);

      // Set up order books
      const price = 100;
      const quantity = 10;

      const limitOrders = new Array<ISamWitchOrderBook.LimitOrderStruct>(8).fill({
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      });
      await orderBook.limitOrders(limitOrders);

      // Consume whole order to add a tombstone offset
      const sellLimitOrders = new Array<ISamWitchOrderBook.LimitOrderStruct>(4).fill({
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      });
      await orderBook.limitOrders(sellLimitOrders);

      expect((await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price)).length).to.eq(4);

      // Cancel a buy in the middle
      const orderId = 6;
      await orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]);

      // Cancel a buy at the start
      await orderBook.cancelOrders([orderId - 1], [{side: OrderSide.Buy, tokenId, price}]);

      // Cancel a buy at the end
      await orderBook.cancelOrders([orderId + 2], [{side: OrderSide.Buy, tokenId, price}]);

      const node = await orderBook.getNode(OrderSide.Buy, tokenId, price);
      expect(node.tombstoneOffset).to.eq(1);

      // The only one left should be orderId 3
      let orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price);
      expect(orders.length).to.eq(1);
      expect(orders[0].id).to.eq(orderId + 1);

      // Check you get the brush back
      expect(await brush.balanceOf(owner)).to.eq(
        initialBrush - price * quantity - calcFees(price * quantity * 4, true),
      );
      expect(await brush.balanceOf(orderBook)).to.eq(price * quantity);

      expect(await orderBook.getHighestBid(tokenId)).to.equal(price);
      expect(await orderBook.getLowestAsk(tokenId)).to.equal(0);

      // Now kill this one
      await orderBook.cancelOrders([orderId + 1], [{side: OrderSide.Buy, tokenId, price}]);
      orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price);
      expect(orders.length).to.eq(0);
    });

    it("Cancel an order which deletes a segment at the beginning, middle and end", async function () {
      const {orderBook, owner, tokenId, brush, initialBrush} = await loadFixture(deployContractsFixture);

      // Set up order books
      const price = 100;
      const quantity = 10;

      const limitOrder = {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      };

      // 4 segments
      const limitOrders = new Array<ISamWitchOrderBook.LimitOrderStruct>(16).fill(limitOrder);
      await orderBook.limitOrders(limitOrders);

      // order ids for the limit orders: [1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16]

      // Cancel a buy in the middle
      let orderIds = [9, 10, 11, 12];
      let orderInfos = orderIds.map(() => ({side: OrderSide.Buy, tokenId, price}));
      await orderBook.cancelOrders(orderIds, orderInfos);
      // Cancel a buy at the start
      orderIds = [1, 2, 3, 4];
      orderInfos = orderIds.map(() => ({side: OrderSide.Buy, tokenId, price}));
      await orderBook.cancelOrders(orderIds, orderInfos);

      // Cancel a buy at the end
      orderIds = [13, 14, 15, 16];
      orderInfos = orderIds.map(() => ({side: OrderSide.Buy, tokenId, price}));
      await orderBook.cancelOrders(orderIds, orderInfos);

      // The only one left should be orderIds
      orderIds = [5, 6, 7, 8];
      const orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price);
      expect(orders.length).to.eq(4);
      expect(orders.map((order) => order.id)).to.deep.eq(orderIds);
      expect(orders[0].id).to.eq(orderIds[0]);

      // Check you get the brush back
      expect(await brush.balanceOf(owner)).to.eq(initialBrush - price * quantity * 4);
      expect(await brush.balanceOf(orderBook)).to.eq(price * quantity * 4);

      expect(await orderBook.getHighestBid(tokenId)).to.equal(price);
      expect(await orderBook.getLowestAsk(tokenId)).to.equal(0);
    });

    it("Bulk cancel orders", async function () {
      const {orderBook, owner, tokenId, erc1155, brush, initialBrush, initialQuantity} =
        await loadFixture(deployContractsFixture);

      // Set up order books
      const price = 100;
      const quantity = 10;
      await orderBook.limitOrders([
        {
          side: OrderSide.Buy,
          tokenId,
          price,
          quantity,
        },
        {
          side: OrderSide.Sell,
          tokenId,
          price: price + 1,
          quantity,
        },
      ]);

      // Cancel buy
      const orderId = 1;
      await orderBook.cancelOrders(
        [orderId, orderId + 1],
        [
          {side: OrderSide.Buy, tokenId, price},
          {side: OrderSide.Sell, tokenId, price: price + 1},
        ],
      );

      // Check both no longer exist
      await expect(
        orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]),
      ).to.be.revertedWithCustomError(orderBook, "OrderNotFoundInTree");
      await expect(
        orderBook.cancelOrders([orderId + 1], [{side: OrderSide.Sell, tokenId, price: price + 1}]),
      ).to.be.revertedWithCustomError(orderBook, "OrderNotFoundInTree");

      expect(await brush.balanceOf(owner)).to.eq(initialBrush);
      expect(await erc1155.balanceOf(owner.address, tokenId)).to.eq(initialQuantity);

      expect(await orderBook.getHighestBid(tokenId)).to.equal(0);
      expect(await orderBook.getLowestAsk(tokenId)).to.equal(0);
    });

    it("Cancelling a non-existent order should revert", async function () {
      const {orderBook, tokenId} = await loadFixture(deployContractsFixture);

      const price = 100;
      const quantity = 10;
      await orderBook.limitOrders([
        {
          side: OrderSide.Buy,
          tokenId,
          price,
          quantity,
        },
      ]);

      const orderId = 2;
      await expect(orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]))
        .to.be.revertedWithCustomError(orderBook, "OrderNotFound")
        .withArgs(orderId, price);
    });

    it("Cancelling an order with the wrong maker should revert", async function () {
      const {orderBook, tokenId, alice} = await loadFixture(deployContractsFixture);

      const price = 100;
      const quantity = 10;
      await orderBook.limitOrders([
        {
          side: OrderSide.Buy,
          tokenId,
          price,
          quantity,
        },
      ]);

      const orderId = 1;
      await expect(
        orderBook.connect(alice).cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]),
      ).to.be.revertedWithCustomError(orderBook, "NotMaker");
    });

    it("Cancelling an order twice should revert", async function () {
      const {orderBook, tokenId} = await loadFixture(deployContractsFixture);

      const price = 100;
      const quantity = 10;
      await orderBook.limitOrders([
        {
          side: OrderSide.Buy,
          tokenId,
          price,
          quantity,
        },
        {
          side: OrderSide.Buy,
          tokenId,
          price,
          quantity,
        },
      ]);

      const orderId = 2;
      await orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]);
      await expect(
        orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]),
      ).to.be.revertedWithCustomError(orderBook, "OrderNotFound");
    });

    it("Cancelling an order that has been consumed should revert", async function () {
      const {orderBook, tokenId} = await loadFixture(deployContractsFixture);

      const price = 100;
      const quantity = 10;
      await orderBook.limitOrders([
        {
          side: OrderSide.Buy,
          tokenId,
          price,
          quantity,
        },
        {
          side: OrderSide.Buy,
          tokenId,
          price,
          quantity,
        },
      ]);

      await orderBook.limitOrders([
        {
          side: OrderSide.Sell,
          tokenId,
          price,
          quantity,
        },
      ]);

      const orderId = 1;
      await expect(
        orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]),
      ).to.be.revertedWithCustomError(orderBook, "OrderNotFound");
    });

    it("Cancelling an order after some orders in a segment are consumed", async function () {
      const {orderBook, tokenId, alice} = await loadFixture(deployContractsFixture);

      // Set up order books
      const price = 100;
      const quantity = 10;
      await orderBook.limitOrders([
        {
          side: OrderSide.Buy,
          tokenId,
          price,
          quantity,
        },
        {
          side: OrderSide.Buy,
          tokenId,
          price,
          quantity,
        },
        {
          side: OrderSide.Buy,
          tokenId,
          price,
          quantity,
        },
      ]);

      await orderBook.limitOrders([
        {
          side: OrderSide.Sell,
          tokenId,
          price,
          quantity,
        },
      ]);

      const orderId = 1;
      await expect(
        orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]),
      ).to.be.revertedWithCustomError(orderBook, "OrderNotFound");
    });
  });

  it("Consume a segment and whole price level with a tombstone offset, and check it works as expected when re-added to the tree", async function () {
    const {orderBook, tokenId} = await loadFixture(deployContractsFixture);

    // Set up order books
    const price = 100;
    const quantity = 10;

    const limitOrder = {
      side: OrderSide.Buy,
      tokenId,
      price,
      quantity,
    };

    // 2 segment
    const limitOrders = new Array<ISamWitchOrderBook.LimitOrderStruct>(4).fill(limitOrder);
    await orderBook.limitOrders(limitOrders);

    expect(await orderBook.nextOrderId()).to.eq(5);

    // Consume 1 segment
    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price: price,
        quantity: quantity * 4,
      },
    ]);
    expect(await orderBook.nextOrderId()).to.eq(5);
    expect(await orderBook.nodeExists(OrderSide.Buy, tokenId, price)).to.be.false;

    // Re-add it, should start in the next segment
    await orderBook.limitOrders([limitOrder]);
    const node = await orderBook.getNode(OrderSide.Buy, tokenId, price);
    expect(node.tombstoneOffset).to.eq(1);

    let orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price);
    const orderId = 5;
    expect(orders.length).to.eq(1);
    expect(orders[0].id).to.eq(orderId);

    // Consume it

    // order ids for the limit orders: [1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16]
  });

  it("Partial segment consumption, sell side", async function () {
    const {orderBook, alice, tokenId} = await loadFixture(deployContractsFixture);

    // Set up order book
    const price = 100;
    const quantity = 10;
    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
    ]);

    // Buy
    const numToBuy = 14; // Finish one and eat into the next
    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity: numToBuy,
      },
    ]);

    let orders = await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price);
    const orderId = 1;
    expect(orders.length).to.eq(2);
    expect(orders[0].id).to.eq(orderId + 1);
    expect(orders[1].id).to.eq(orderId + 2);

    const node = await orderBook.getNode(OrderSide.Sell, tokenId, price);
    expect(node.tombstoneOffset).to.eq(0);

    const remainderQuantity = quantity * 3 - numToBuy;
    // Try to buy too many
    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity: remainderQuantity + 1,
      },
    ]);

    orders = await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price);
    expect(orders.length).to.eq(0);
  });

  it("Full segment consumption, sell side", async function () {
    const {orderBook, owner, alice, erc1155, brush, tokenId, initialQuantity, initialBrush} =
      await loadFixture(deployContractsFixture);

    // Set up order book
    const price = 100;
    const quantity = 10;
    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
    ]);

    // Buy
    const numToBuy = 40; // Finish one and eat into the next
    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity: numToBuy,
      },
    ]);

    let orders = await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price);
    expect(orders.length).to.eq(0);
    expect(await orderBook.nodeExists(OrderSide.Sell, tokenId, price)).to.be.false;

    // Check erc1155/brush balances
    expect(await erc1155.balanceOf(orderBook, tokenId)).to.eq(0);
    expect(await erc1155.balanceOf(owner, tokenId)).to.eq(initialQuantity - quantity * 4);
    expect(await erc1155.balanceOf(alice, tokenId)).to.eq(initialQuantity + quantity * 4);

    const orderId = 1;
    await orderBook.claimTokens([orderId, orderId + 1, orderId + 2, orderId + 3]);
    expect(await brush.balanceOf(owner)).to.eq(
      initialBrush + price * quantity * 4 - calcFees(price * quantity * 4, true),
    );
    expect(await brush.balanceOf(alice)).to.eq(initialBrush - price * quantity * 4);
  });

  it("Full segment & partial segment consumption, sell side", async function () {
    const {orderBook, owner, alice, erc1155, brush, tokenId, initialQuantity, initialBrush} =
      await loadFixture(deployContractsFixture);

    // Set up order book
    const price = 100;
    const quantity = 10;
    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
    ]);

    // Buy
    const numToBuy = 44; // Finish one and eat into the next
    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity: numToBuy,
      },
    ]);

    let orders = await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price);
    expect(orders.length).to.eq(1);

    const node = await orderBook.getNode(OrderSide.Sell, tokenId, price);
    expect(node.tombstoneOffset).to.eq(1);

    // Check erc1155/brush balances
    expect(await erc1155.balanceOf(orderBook, tokenId)).to.eq(quantity * 5 - numToBuy);
    expect(await erc1155.balanceOf(owner, tokenId)).to.eq(initialQuantity - quantity * 5);
    expect(await erc1155.balanceOf(alice, tokenId)).to.eq(initialQuantity + numToBuy);

    const orderId = 1;
    await orderBook.claimTokens([orderId, orderId + 1, orderId + 2, orderId + 3, orderId + 4]);
    expect(await brush.balanceOf(owner)).to.eq(initialBrush + price * numToBuy - calcFees(price * numToBuy, true));
    expect(await brush.balanceOf(alice)).to.eq(initialBrush - price * numToBuy);
  });

  it("Partial segment consumption, buy side", async function () {
    const {orderBook, alice, tokenId} = await loadFixture(deployContractsFixture);

    // Set up order book
    const price = 100;
    const quantity = 10;
    await orderBook.limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      },
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      },
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      },
    ]);

    // Sell
    const numToSell = 14; // Finish one and eat into the next
    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity: numToSell,
      },
    ]);

    let orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price);
    const orderId = 1;
    expect(orders.length).to.eq(2);
    expect(orders[0].id).to.eq(orderId + 1);
    expect(orders[1].id).to.eq(orderId + 2);

    const node = await orderBook.getNode(OrderSide.Buy, tokenId, price);
    expect(node.tombstoneOffset).to.eq(0);

    const remainderQuantity = quantity * 3 - numToSell;
    // Try to sell too many
    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity: remainderQuantity + 1,
      },
    ]);

    orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price);
    expect(orders.length).to.eq(0);
  });

  it("Partial order consumption", async function () {});

  it("Max number of orders for a price should increment it by the tick, sell orders", async function () {
    const {orderBook, alice, tokenId, maxOrdersPerPrice, tick} = await loadFixture(deployContractsFixture);

    // Set up order book
    const price = 100;
    const quantity = 1;

    const limitOrder: ISamWitchOrderBook.LimitOrderStruct = {
      side: OrderSide.Sell,
      tokenId,
      price,
      quantity,
    };

    const limitOrders = new Array<ISamWitchOrderBook.LimitOrderStruct>(maxOrdersPerPrice).fill(limitOrder);
    await orderBook.limitOrders(limitOrders);

    // Try to add one more and it will be added to the next tick price
    await orderBook.connect(alice).limitOrders([limitOrder]);

    let orders = await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price);
    expect(orders.length).to.eq(maxOrdersPerPrice);

    orders = await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + tick);
    expect(orders.length).to.eq(1);
  });

  it("Max number of orders for a price should increment it by the tick, buy orders", async function () {
    const {orderBook, alice, tokenId, maxOrdersPerPrice, tick} = await loadFixture(deployContractsFixture);

    // Set up order book
    const price = 100;
    const quantity = 1;

    const limitOrder: ISamWitchOrderBook.LimitOrderStruct = {
      side: OrderSide.Buy,
      tokenId,
      price,
      quantity,
    };

    const limitOrders = new Array<ISamWitchOrderBook.LimitOrderStruct>(maxOrdersPerPrice).fill(limitOrder);
    await orderBook.limitOrders(limitOrders);

    // Try to add one more and it will be added to the next tick price
    await orderBook.connect(alice).limitOrders([limitOrder]);

    let orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price);
    expect(orders.length).to.eq(maxOrdersPerPrice);

    orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price - tick);
    expect(orders.length).to.eq(1);
  });

  it("Max number of orders for a price should increment it by the tick, where the price level exists already and has spare segments", async function () {
    const {orderBook, alice, tokenId, maxOrdersPerPrice, tick} = await loadFixture(deployContractsFixture);

    // Set up order book
    const price = 100;
    const quantity = 1;

    const limitOrder: ISamWitchOrderBook.LimitOrderStruct = {
      side: OrderSide.Buy,
      tokenId,
      price,
      quantity,
    };

    const limitOrders = new Array<ISamWitchOrderBook.LimitOrderStruct>(maxOrdersPerPrice).fill(limitOrder);
    await orderBook.limitOrders(limitOrders);

    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price: price - tick,
        quantity,
      },
    ]);

    // Try to add one more and it will be added to the next tick price
    await orderBook.connect(alice).limitOrders([limitOrder]);

    let orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price);
    expect(orders.length).to.eq(maxOrdersPerPrice);

    orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price - tick);
    expect(orders.length).to.eq(2);
  });

  it("Multiple ticks iterated when there are the max number of orders and no spare orders in the last segment", async function () {
    const {orderBook, alice, tokenId, maxOrdersPerPrice, erc1155, tick} = await loadFixture(deployContractsFixture);

    // Set up order book
    const price = 100;
    const quantity = 1;
    await erc1155.mintSpecificId(tokenId, 10000);

    const limitOrder: ISamWitchOrderBook.LimitOrderStruct = {
      side: OrderSide.Sell,
      tokenId,
      price,
      quantity,
    };

    let limitOrders = new Array<ISamWitchOrderBook.LimitOrderStruct>(maxOrdersPerPrice).fill(limitOrder);
    await orderBook.limitOrders(limitOrders);

    const limitOrderNextTick: ISamWitchOrderBook.LimitOrderStruct = {
      side: OrderSide.Sell,
      tokenId,
      price: price + tick,
      quantity,
    };

    let limitOrdersNextTick = new Array<ISamWitchOrderBook.LimitOrderStruct>(maxOrdersPerPrice).fill(
      limitOrderNextTick,
    );
    await orderBook.limitOrders(limitOrdersNextTick);

    // Try to add one more and it will be added to the tick * 2 price
    await orderBook.connect(alice).limitOrders([limitOrder]);

    let orders = await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + 2 * tick);
    expect(orders.length).to.eq(1);
  });

  it("Multiple ticks iterated, space at the end of the segment for it", async function () {
    const {orderBook, alice, tokenId, maxOrdersPerPrice, erc1155, tick} = await loadFixture(deployContractsFixture);

    // Set up order book
    const price = 100;
    const quantity = 1;
    await erc1155.mintSpecificId(tokenId, 10000);

    const limitOrder: ISamWitchOrderBook.LimitOrderStruct = {
      side: OrderSide.Sell,
      tokenId,
      price,
      quantity,
    };

    let limitOrders = new Array<ISamWitchOrderBook.LimitOrderStruct>(maxOrdersPerPrice).fill(limitOrder);
    await orderBook.limitOrders(limitOrders);

    const limitOrderNextTick: ISamWitchOrderBook.LimitOrderStruct = {
      side: OrderSide.Sell,
      tokenId,
      price: price + tick,
      quantity,
    };

    let limitOrdersNextTick = new Array<ISamWitchOrderBook.LimitOrderStruct>(maxOrdersPerPrice).fill(
      limitOrderNextTick,
    );
    await orderBook.limitOrders(limitOrdersNextTick);

    await orderBook.cancelOrders([maxOrdersPerPrice * 2 - 2], [{side: OrderSide.Sell, tokenId, price: price + tick}]);

    // Try to add one more and it will be added to the tick * 2 price
    await orderBook.connect(alice).limitOrders([limitOrder]);

    let orders = await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + tick);
    expect(orders.length).to.eq(100);

    orders = await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + 2 * tick);
    expect(orders.length).to.eq(0);
  });

  it("Price must be modulus of tick quantity must be > min quantity, sell", async function () {
    const {orderBook, erc1155, tokenId} = await loadFixture(deployContractsFixture);

    await orderBook.setTokenIdInfos([tokenId], [{tick: 10, minQuantity: 20}]);

    let price = 101;
    let quantity = 20;
    await expect(
      orderBook.limitOrders([
        {
          side: OrderSide.Sell,
          tokenId,
          price,
          quantity,
        },
      ]),
    )
      .to.be.revertedWithCustomError(orderBook, "PriceNotMultipleOfTick")
      .withArgs(10);

    // Doesn't take any because quantity is lower than the minimum
    price = 100;
    quantity = 19;
    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
    ]);
    expect(await erc1155.balanceOf(orderBook, tokenId)).to.eq(0);

    quantity = 20;
    await expect(
      orderBook.limitOrders([
        {
          side: OrderSide.Sell,
          tokenId,
          price,
          quantity,
        },
      ]),
    ).to.not.be.reverted;
    expect(await erc1155.balanceOf(orderBook, tokenId)).to.eq(20);
  });

  it("Price must be modulus of tick quantity must be > min quantity, buy", async function () {
    const {orderBook, brush, tokenId} = await loadFixture(deployContractsFixture);

    await orderBook.setTokenIdInfos([tokenId], [{tick: 10, minQuantity: 20}]);

    let price = 101;
    let quantity = 20;
    await expect(
      orderBook.limitOrders([
        {
          side: OrderSide.Buy,
          tokenId,
          price,
          quantity,
        },
      ]),
    )
      .to.be.revertedWithCustomError(orderBook, "PriceNotMultipleOfTick")
      .withArgs(10);

    // Doesn't take any because quantity is lower than the minimum
    price = 100;
    quantity = 19;
    await orderBook.limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      },
    ]);
    expect(await brush.balanceOf(orderBook)).to.eq(0);

    quantity = 20;
    await expect(
      orderBook.limitOrders([
        {
          side: OrderSide.Buy,
          tokenId,
          price,
          quantity,
        },
      ]),
    ).to.not.be.reverted;
    expect(await brush.balanceOf(orderBook)).to.eq(quantity * price);
  });

  it("Test gas costs", async function () {
    const {orderBook, erc1155, alice, tokenId, maxOrdersPerPrice} = await loadFixture(deployContractsFixture);

    // Create a bunch of orders at 5 different prices each with the maximum number of orders, so 500 in total
    const price = 100;
    const quantity = 1;

    const prices = [price, price + 1, price + 2, price + 3, price + 4];
    for (const price of prices) {
      const limitOrder: ISamWitchOrderBook.LimitOrderStruct = {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      };

      const limitOrders = new Array<ISamWitchOrderBook.LimitOrderStruct>(maxOrdersPerPrice).fill(limitOrder);
      await orderBook.connect(alice).limitOrders(limitOrders);
    }

    // Cancelling an order at the start will be very expensive
    const orderId = 1;
    await orderBook.connect(alice).cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]);

    await erc1155.mintSpecificId(tokenId, 10000);
    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity: quantity * maxOrdersPerPrice * prices.length,
      },
    ]);
  });

  it("Check all fees (buying into order book)", async function () {
    const {orderBook, erc1155, brush, owner, alice, dev, royaltyRecipient, tokenId, initialBrush} =
      await loadFixture(deployContractsFixture);

    await erc1155.setRoyaltyFee(1000); // 10%
    await orderBook.updateRoyaltyFee();

    // Set up order book
    const price = 100;
    const quantity = 100;
    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
    ]);
    const cost = price * 10;
    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity: 10,
      },
    ]);

    // Check fees
    expect(await brush.balanceOf(alice)).to.eq(initialBrush - price * 10);
    const royalty = cost / 10;
    const burnt = (cost * 3) / 1000; // 0.3%
    const devAmount = (cost * 3) / 1000; // 0.3%
    const fees = royalty + burnt + devAmount;
    expect(await brush.balanceOf(orderBook)).to.eq(cost - fees);
    expect(await brush.balanceOf(dev)).to.eq(devAmount);
    expect(await brush.balanceOf(owner)).to.eq(initialBrush);
    expect(await brush.balanceOf(royaltyRecipient)).to.eq(royalty);
    expect(await brush.amountBurnt()).to.eq(burnt);
  });

  it("Check all fees (selling into order book)", async function () {
    const {orderBook, erc1155, brush, owner, alice, dev, royaltyRecipient, tokenId, initialBrush} =
      await loadFixture(deployContractsFixture);

    await erc1155.setRoyaltyFee(1000); // 10%
    await orderBook.updateRoyaltyFee();

    // Set up order book
    const price = 100;
    const quantity = 100;
    await orderBook.limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      },
    ]);
    const buyingCost = price * quantity;
    const cost = price * 10;
    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity: 10,
      },
    ]);

    // Check fees
    const royalty = cost / 10;
    const burnt = (cost * 3) / 1000; // 0.3%
    const devAmount = (cost * 3) / 1000; // 0.3%
    const fees = royalty + burnt + devAmount;

    expect(await brush.balanceOf(alice)).to.eq(initialBrush + cost - fees);
    expect(await brush.balanceOf(orderBook)).to.eq(buyingCost - cost);
    expect(await brush.balanceOf(dev)).to.eq(devAmount);
    expect(await brush.balanceOf(owner)).to.eq(initialBrush - buyingCost);
    expect(await brush.balanceOf(royaltyRecipient)).to.eq(royalty);
    expect(await brush.amountBurnt()).to.eq(burnt);
  });

  it("Claim tokens", async function () {
    const {orderBook, erc1155, brush, owner, alice, tokenId, initialBrush} = await loadFixture(deployContractsFixture);

    await erc1155.setRoyaltyFee(1000); // 10%
    await orderBook.updateRoyaltyFee();

    // Set up order book
    const price = 100;
    const quantity = 100;
    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity,
      },
    ]);
    const cost = price * 10;
    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity: 10,
      },
    ]);

    // Check fees
    const royalty = cost / 10;
    const burnt = (cost * 3) / 1000; // 0.3%
    const devAmount = (cost * 3) / 1000; // 0.3%
    const fees = royalty + burnt + devAmount;

    const orderId = 1;
    expect(await orderBook.tokensClaimable([orderId], false)).to.eq(cost);
    expect(await orderBook.tokensClaimable([orderId], true)).to.eq(cost - fees);
    expect(await orderBook.tokensClaimable([orderId + 1], false)).to.eq(0);
    expect((await orderBook.nftsClaimable([orderId], [tokenId]))[0]).to.eq(0);
    expect((await orderBook.nftsClaimable([orderId + 1], [tokenId]))[0]).to.eq(0);

    expect(await brush.balanceOf(owner)).to.eq(initialBrush);
    await expect(orderBook.claimTokens([orderId]))
      .to.emit(orderBook, "ClaimedTokens")
      .withArgs(owner.address, [orderId], cost, fees);
    expect(await brush.balanceOf(owner)).to.eq(initialBrush + cost - fees);
    expect(await orderBook.tokensClaimable([orderId], false)).to.eq(0);

    // Try to claim twice
    await expect(orderBook.claimTokens([orderId])).to.be.revertedWithCustomError(orderBook, "NothingToClaim");
  });

  it("Claim NFTs", async function () {
    const {orderBook, owner, alice, tokenId} = await loadFixture(deployContractsFixture);

    // Set up order book
    const price = 100;
    const quantity = 100;
    await orderBook.limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      },
    ]);
    await orderBook.connect(alice).limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price,
        quantity: 10,
      },
    ]);

    const orderId = 1;
    expect(await orderBook.tokensClaimable([orderId], false)).to.eq(0);
    expect(await orderBook.tokensClaimable([orderId + 1], false)).to.eq(0);
    expect((await orderBook.nftsClaimable([orderId], [tokenId]))[0]).to.eq(10);
    expect((await orderBook.nftsClaimable([orderId + 1], [tokenId]))[0]).to.eq(0);

    await expect(orderBook.claimNFTs([orderId], [tokenId]))
      .to.emit(orderBook, "ClaimedNFTs")
      .withArgs(owner.address, [orderId], [tokenId], [10]);
    expect((await orderBook.nftsClaimable([orderId], [tokenId]))[0]).to.eq(0);

    // Try to claim twice
    await expect(orderBook.claimNFTs([orderId], [tokenId])).to.be.revertedWithCustomError(orderBook, "NothingToClaim");
  });

  it("Max brush price", async function () {
    const {orderBook, tokenId} = await loadFixture(deployContractsFixture);

    const quantity = 100;
    await expect(
      orderBook.limitOrders([
        {
          side: OrderSide.Sell,
          tokenId,
          price: ethers.parseEther("4800"),
          quantity,
        },
      ]),
    ).to.throw;

    await expect(
      orderBook.limitOrders([
        {
          side: OrderSide.Sell,
          tokenId,
          price: ethers.parseEther("4700"),
          quantity,
        },
      ]),
    ).to.throw;
  });

  it("System test (many orders)", async function () {
    const {orderBook, owner, tokenId, brush, erc1155, tick} = await loadFixture(deployContractsFixture);

    const initialBrush = 1000000;
    await brush.mint(owner.address, initialBrush * 30);
    await brush.approve(orderBook, initialBrush * 30);

    const price = 100;
    const quantity = 10;

    await erc1155.mintSpecificId(tokenId, quantity * 40);

    // Set up buy order book
    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 2 * tick,
        quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 2 * tick,
        quantity: quantity + 1,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 4 * tick,
        quantity: quantity + 2,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 8 * tick,
        quantity: quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 8 * tick,
        quantity: quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 8 * tick,
        quantity: quantity + 1,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 2 * tick,
        quantity: quantity + 2,
      },
      {
        // order id 8
        side: OrderSide.Sell,
        tokenId,
        price: price + 2 * tick,
        quantity: quantity + 3,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 5 * tick,
        quantity: quantity + 2,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 4 * tick,
        quantity: quantity - 1,
      },
      {
        // 11
        side: OrderSide.Sell,
        tokenId,
        price: price + 4 * tick,
        quantity: quantity,
      },
      {
        // 12
        side: OrderSide.Sell,
        tokenId,
        price: price + 4 * tick,
        quantity: quantity,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 4 * tick,
        quantity: quantity + 4,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 8 * tick,
        quantity: quantity - 1,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 8 * tick,
        quantity: quantity + 4,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 8 * tick,
        quantity: quantity + 4,
      },

      {
        side: OrderSide.Buy,
        tokenId,
        price: price,
        quantity: quantity,
      },
      {
        side: OrderSide.Buy,
        tokenId,
        price: price - 2,
        quantity: quantity + 2,
      },
      {
        side: OrderSide.Buy,
        tokenId,
        price: price,
        quantity: quantity + 1,
      },
      {
        // 20
        side: OrderSide.Buy,
        tokenId,
        price: price - 1,
        quantity: quantity + 4,
      },

      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 4 * tick,
        quantity: quantity + 4,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 4 * tick,
        quantity: quantity + 4,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 4 * tick,
        quantity: quantity,
      },

      {
        side: OrderSide.Buy,
        tokenId,
        price: price,
        quantity: quantity + 2,
      },
      {
        // 25
        side: OrderSide.Buy,
        tokenId,
        price: price,
        quantity: quantity + 3,
      },

      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 8 * tick,
        quantity: quantity + 4,
      },
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 8 * tick,
        quantity: quantity,
      },

      {
        side: OrderSide.Buy,
        tokenId,
        price: price,
        quantity: quantity + 4,
      },
      {
        // 29
        side: OrderSide.Sell,
        tokenId,
        price: price + 8 * tick,
        quantity: quantity,
      },
      {
        // 30
        side: OrderSide.Sell,
        tokenId,
        price: price + 2 * tick,
        quantity: quantity + 4,
      },
    ]);

    // Use this to output all orders
    /* outputAllOrders(await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + 8 * tick));
    outputAllOrders(await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + 5 * tick));
    outputAllOrders(await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + 4 * tick));
    outputAllOrders(await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + 2 * tick));

    outputAllOrders(await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price));
    outputAllOrders(await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price - tick));
    outputAllOrders(await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price - 2 * tick));
    */

    // Price - [orders (orderId)]
    // Sell
    // 108 - [quantity (4), quantity (5), quantity + 1 (6), quantity - 1 (14)], [quantity + 4 (15), quantity + 4 (16), quantity + 4 (26), quantity (27)], [quantity (29)]
    // 105 - [quantity + 2 (9)]
    // 104 - [quantity + 2 (3), quantity - 1 (10), quantity (11), quantity (12)], [quantity + 4 (13), quantity + 4 (21), quantity + 4 (22), quantity (23)]
    // 102 - [quantity (1), quantity + 1 (2), quantity + 2 (7), quantity + 3 (8)], [quantity + 4 (30)]

    // Buy
    // Price - orders
    // 100 - [quantity (17), quantity + 1 (19), quantity + 2 (24), quantity + 3 (25)], [quantity + 4 (28)]
    // 99 - [quantity + 4 (20)]
    // 98 - [quantity + 2 (18)]

    await orderBook.cancelOrders([5], [{side: OrderSide.Sell, tokenId, price: price + 8 * tick}]);
    expect((await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + 8 * tick)).length).to.eq(8);

    // Price - [orders (orderId)]
    // Sell
    // 108 - [quantity (4), quantity + 1 (6), quantity - 1 (14), quantity + 4 (15)], [quantity + 4 (16), quantity + 4 (26), quantity (27), quantity (29)], []
    // 105 - [quantity + 2 (9)]
    // 104 - [quantity + 2 (3), quantity - 1 (10), quantity (11), quantity (12)], [quantity + 4 (13), quantity + 4 (21), quantity + 4 (22), quantity (23)]
    // 102 - [quantity (1), quantity + 1 (2), quantity + 2 (7), quantity + 3 (8)], [quantity + 4 (11)]

    // Buy
    // Price - orders
    // 100 - [quantity (17), quantity + 1 (19), quantity + 2 (24), quantity + 3 (25)], [quantity + 4 (28)]
    // 99 - [quantity + 4 (20)]
    // 98 - [quantity + 2 (18)]
    await orderBook.limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price: price + 3 * tick,
        quantity: quantity + quantity + 1 + quantity + 2 + quantity + 3 + quantity + 4 + quantity,
      },
    ]);
    expect(await orderBook.nextOrderId()).to.eq(32);

    // (Remove whole 102 price level, add 103 price level)
    // Sell
    // Price - [orders (orderId)]
    // 108 - [quantity (4), quantity + 1 (6), quantity - 1 (14), quantity + 4 (15)], [quantity + 4 (16), quantity + 4 (26), quantity (27), quantity (29)], []
    // 105 - [quantity + 2 (9)]
    // 104 - [quantity + 2 (3), quantity - 1 (10), quantity (11), quantity (12)], [quantity + 4 (13), quantity + 4 (21), quantity + 4 (22), quantity (23)]

    // Buy
    // Price - orders
    // 103 - [quantity (31)]
    // 100 - [quantity (17), quantity + 1 (19), quantity + 2 (24), quantity + 3 (25)], [quantity + 4 (28)]
    // 99 - [quantity + 4 (20)]
    // 98 - [quantity + 2 (18)]

    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price: price,
        quantity: quantity + quantity + 1 + 2,
      },
    ]);

    // (Consume 103 level, 2 orders at 100 and eat into another)
    // Sell
    // Price - [orders (orderId)]
    // 108 - [quantity (4), quantity + 1 (6), quantity - 1 (14), quantity + 4 (15)], [quantity + 4 (16), quantity + 4 (26), quantity (27), quantity (29)], []
    // 105 - [quantity + 2 (9)]
    // 104 - [quantity + 2 (3), quantity - 1 (10), quantity (11), quantity (12)], [quantity + 4 (13), quantity + 4 (21), quantity + 4 (22), quantity (23)]

    // Buy
    // Price - orders
    // 100 - [0, 0, quantity (24), quantity + 3 (25)], [quantity + 4 (28)]
    // 99 - [quantity + 4 (20)]
    // 98 - [quantity + 2 (18)]

    // (Consume 103 order 2 orders and eat into another)
    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price: price,
        quantity: quantity + quantity + quantity + 3,
      },
    ]);

    let node = await orderBook.getNode(OrderSide.Buy, tokenId, price);
    expect(node.tombstoneOffset).to.eq(1);

    // Sell
    // Price - [orders (orderId)]
    // 108 - [quantity (4), quantity + 1 (6), quantity - 1 (14), quantity + 4 (15)], [quantity + 4 (16), quantity + 4 (26), quantity (27), quantity (29)], []
    // 105 - [quantity + 2 (9)]
    // 104 - [quantity + 2 (3), quantity - 1 (10), quantity (11), quantity (12)], [quantity + 4 (13), quantity + 4 (21), quantity + 4 (22), quantity (23)]

    // Buy
    // Price - orders
    // 100 - [0, 0, 0, 0], [quantity + 4 (28)]
    // 99 - [quantity + 4 (20)]
    // 98 - [quantity + 2 (18)]

    // Add a buy above the one with a tomstone offset on a price level which was removed (103)
    await orderBook.limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price: price + 3 * tick,
        quantity: quantity - 6,
      },
    ]);

    // Sell
    // Price - [orders (orderId)]
    // 108 - [quantity (4), quantity + 1 (6), quantity - 1 (14), quantity + 4 (15)], [quantity + 4 (16), quantity + 4 (26), quantity (27), quantity (29)], []
    // 105 - [quantity + 2 (9)]
    // 104 - [quantity + 2 (3), quantity - 1 (10), quantity (11), quantity (12)], [quantity + 4 (13), quantity + 4 (21), quantity + 4 (22), quantity (23)]

    // Buy
    // Price - orders
    // 103 - [quantity - 6 (32)]
    // 100 - [0, 0, 0, 0], [quantity + 4 (28)]
    // 99 - [quantity + 4 (20)]
    // 98 - [quantity + 2 (18)]

    // Take out 103, 100, and a bit of 99
    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price: price - 1,
        quantity: quantity + 4 + quantity - 6 + 3,
      },
    ]);

    // Sell
    // Price - [orders (orderId)]
    // 108 - [quantity (4), quantity + 1 (6), quantity - 1 (14), quantity + 4 (15)], [quantity + 4 (16), quantity + 4 (26), quantity (27), quantity (29)], []
    // 105 - [quantity + 2 (9)]
    // 104 - [quantity + 2 (3), quantity - 1 (10), quantity (11), quantity (12)], [quantity + 4 (13), quantity + 4 (21), quantity + 4 (22), quantity (23)]

    // Buy
    // Price - orders
    // 99 - [quantity + 1 (20)]
    // 98 - [quantity + 2 (18)]

    // Add a buy with a previous tomstone offset on a price level which was removed (100)
    await orderBook.limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price: price,
        quantity: quantity,
      },
    ]);

    expect(await orderBook.getHighestBid(tokenId)).to.eq(price);
    node = await orderBook.getNode(OrderSide.Buy, tokenId, price);
    expect(node.tombstoneOffset).to.eq(1);
    expect((await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price)).length).to.eq(1);
    expect((await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price))[0]).to.deep.eq([
      owner.address,
      quantity,
      33n,
    ]);

    // Sell
    // Price - [orders (orderId)]
    // 108 - [quantity (4), quantity + 1 (6), quantity - 1 (14), quantity + 4 (15)], [quantity + 4 (16), quantity + 4 (26), quantity (27), quantity (29)], []
    // 105 - [quantity + 2 (9)]
    // 104 - [quantity + 2 (3), quantity - 1 (10), quantity (11), quantity (12)], [quantity + 4 (13), quantity + 4 (21), quantity + 4 (22), quantity (23)]

    // Buy
    // Price - orders
    // 100 - [0, 0, 0, 0], [quantity (33)]
    // 99 - [quantity + 1 (20)]
    // 98 - [quantity + 2 (18)]

    // Consume all of 104, 105, and one segment of 108, 1 order and eat into another of another segment
    await orderBook.limitOrders([
      {
        side: OrderSide.Buy,
        tokenId,
        price: price + 8 * tick,
        quantity:
          quantity +
          2 +
          quantity -
          1 +
          quantity +
          quantity +
          quantity +
          4 +
          quantity +
          4 +
          quantity +
          4 +
          quantity +
          quantity +
          2 +
          quantity +
          quantity +
          1 +
          quantity -
          1 +
          quantity +
          4 +
          quantity +
          4 +
          quantity,
      },
    ]);

    expect((await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + 8 * tick)).length).to.eq(3);
    expect((await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + 5 * tick)).length).to.eq(0);
    expect((await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + 4 * tick)).length).to.eq(0);

    // Sell
    // Price - [orders (orderId)]
    // 108 - [0, 0, 0, 0], [0, 4 (26), quantity (27), quantity (29)], []

    // Buy
    // Price - orders
    // 100 - [0, 0, 0, 0], [quantity (33)]
    // 99 - [quantity + 1 (20)]
    // 98 - [quantity + 2 (18)]

    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 4 * tick,
        quantity: quantity,
      },
    ]);

    node = await orderBook.getNode(OrderSide.Sell, tokenId, price + 4 * tick);
    expect(node.tombstoneOffset).to.eq(2);
    expect((await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + 4 * tick)).length).to.eq(1);

    // Sell
    // Price - [orders (orderId)]
    // 108 - [0, 0, 0, 0], [0, 4 (26), quantity (27), quantity (29)], []
    // 104 - [0, 0, 0, 0], [0, 0, 0, 0], [quantity (34)]

    // Buy
    // Price - orders
    // 100 - [0, 0, 0, 0], [quantity (33)]
    // 99 - [quantity + 1 (20)]
    // 98 - [quantity + 2 (18)]

    // Cancel the order should remove this order from the tree
    await orderBook.cancelOrders([34], [{side: OrderSide.Sell, tokenId, price: price + 4 * tick}]);

    await expect(orderBook.getNode(OrderSide.Sell, tokenId, price + 4 * tick)).to.be.reverted;

    // Sell
    // Price - [orders (orderId)]
    // 108 - [0, 0, 0, 0], [0, 4 (26), quantity (27), quantity (29)], []

    // Buy
    // Price - orders
    // 100 - [0, 0, 0, 0], [quantity (33)]
    // 99 - [quantity + 1 (20)]
    // 98 - [quantity + 2 (18)]

    // Re add the order to check tombstone offset again
    await orderBook.limitOrders([
      {
        side: OrderSide.Sell,
        tokenId,
        price: price + 4 * tick,
        quantity: quantity + 1,
      },
    ]);

    node = await orderBook.getNode(OrderSide.Sell, tokenId, price + 4 * tick);
    expect(node.tombstoneOffset).to.eq(2);
    expect((await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + 4 * tick)).length).to.eq(1);
    expect((await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + 4 * tick))[0]).to.deep.eq([
      owner.address,
      quantity + 1,
      35n,
    ]);

    // Sell
    // Price - [orders (orderId)]
    // 108 - [0, 0, 0, 0], [0, 4 (26), quantity (27), quantity (29)], []
    // 104 - [0, 0, 0, 0], [0, 0, 0, 0], [quantity + 1 (35)]

    // Buy
    // Price - orders
    // 100 - [0, 0, 0, 0], [quantity (33)]
    // 99 - [quantity + 1 (20)]
    // 98 - [quantity + 2 (18)]
  });

  // Assuming royalty fee is 10%, burnt fee is 0.3% and dev fee is 0.3%
  const calcFees = (cost: number, ignoreRoyalty: boolean) => {
    let royalty = ignoreRoyalty ? 0 : cost / 10;
    const burnt = (cost * 3) / 1000; // 0.3%
    const devAmount = (cost * 3) / 1000; // 0.3%
    return Math.floor(royalty + burnt + devAmount);
  };

  const outputAllOrders = (orders: ISamWitchOrderBook.OrderBookEntryHelperStruct[]) => {
    for (const order of orders) {
      console.log(`${order.id} | ${order.quantity}`);
    }
  };
});
