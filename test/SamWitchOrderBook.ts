import {loadFixture} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import {ethers, upgrades} from "hardhat";
import {expect} from "chai";
import {SamWitchOrderBook} from "../typechain-types";

describe("SamWitchOrderBook", function () {
  enum OrderSide {
    Buy,
    Sell,
  }

  type CancelOrderInfo = {
    side: OrderSide;
    orderId: number;
    tokenId: number;
    price: number;
  };

  type LimitOrder = {
    side: OrderSide;
    tokenId: number;
    price: number;
    quantity: number;
  };

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
      }
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

    await orderBook.setTokenIdInfos([tokenId], [{tick: 1, minQuantity: 1}]);

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

  it("Take from order book", async function () {
    const {orderBook, erc1155, brush, initialQuantity, alice, tokenId} = await loadFixture(deployContractsFixture);

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
    await brush.mint(alice, 1000000);
    await brush.connect(alice).approve(orderBook, 1000000);
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

    // There's nothing left, this adds to the buy order side
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

  it("Cancel an order", async function () {
    const {orderBook, owner, tokenId, erc1155, brush, initialBrush, initialQuantity} = await loadFixture(
      deployContractsFixture
    );

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
    await orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}]);

    // No longer exists
    await expect(
      orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}])
    ).to.be.revertedWithCustomError(orderBook, "OrderNotFound");

    // Cancel the sell
    await orderBook.cancelOrders([orderId + 1], [{side: OrderSide.Sell, tokenId, price: price + 1}]);

    // No longer exists
    await expect(
      orderBook.cancelOrders([orderId + 1], [{side: OrderSide.Sell, tokenId, price: price + 1}])
    ).to.be.revertedWithCustomError(orderBook, "OrderNotFound");

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
      {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      },
    ]);

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

  it("Cancel an order at the beginning, middle and end", async function () {});

  it("Bulk cancel orders", async function () {
    const {orderBook, owner, tokenId, erc1155, brush, initialBrush, initialQuantity} = await loadFixture(
      deployContractsFixture
    );

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
      ]
    );

    // Check both no longer exist
    await expect(
      orderBook.cancelOrders([orderId], [{side: OrderSide.Buy, tokenId, price}])
    ).to.be.revertedWithCustomError(orderBook, "OrderNotFound");
    await expect(
      orderBook.cancelOrders([orderId + 1], [{side: OrderSide.Sell, tokenId, price: price + 1}])
    ).to.be.revertedWithCustomError(orderBook, "OrderNotFound");

    expect(await brush.balanceOf(owner)).to.eq(initialBrush);
    expect(await erc1155.balanceOf(owner.address, tokenId)).to.eq(initialQuantity);

    expect(await orderBook.getHighestBid(tokenId)).to.equal(0);
    expect(await orderBook.getLowestAsk(tokenId)).to.equal(0);
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
    const {orderBook, owner, alice, erc1155, brush, tokenId, initialQuantity, initialBrush} = await loadFixture(
      deployContractsFixture
    );

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
      initialBrush + price * quantity * 4 - calcFees(price * quantity * 4, true)
    );
    expect(await brush.balanceOf(alice)).to.eq(initialBrush - price * quantity * 4);
  });

  it("Full segment & partial segment consumption, sell side", async function () {
    const {orderBook, owner, alice, erc1155, brush, tokenId, initialQuantity, initialBrush} = await loadFixture(
      deployContractsFixture
    );

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
    const {orderBook, alice, tokenId, maxOrdersPerPrice} = await loadFixture(deployContractsFixture);

    // Set up order book
    const price = 100;
    const quantity = 1;

    const limitOrder: LimitOrder = {
      side: OrderSide.Sell,
      tokenId,
      price,
      quantity,
    };

    const limitOrders = new Array<LimitOrder>(maxOrdersPerPrice).fill(limitOrder);
    await orderBook.limitOrders(limitOrders);

    const tick = Number(await orderBook.getTick(tokenId));

    // Try to add one more and it will be added to the next tick price
    await orderBook.connect(alice).limitOrders([limitOrder]);

    let orders = await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price);
    expect(orders.length).to.eq(maxOrdersPerPrice);

    orders = await orderBook.allOrdersAtPrice(OrderSide.Sell, tokenId, price + tick);
    expect(orders.length).to.eq(1);
  });

  it("Max number of orders for a price should increment it by the tick, buy orders", async function () {
    const {orderBook, alice, tokenId, maxOrdersPerPrice} = await loadFixture(deployContractsFixture);

    // Set up order book
    const price = 100;
    const quantity = 1;

    const limitOrder: LimitOrder = {
      side: OrderSide.Buy,
      tokenId,
      price,
      quantity,
    };

    const limitOrders = new Array<LimitOrder>(maxOrdersPerPrice).fill(limitOrder);
    await orderBook.limitOrders(limitOrders);

    const tick = Number(await orderBook.getTick(tokenId));

    // Try to add one more and it will be added to the next tick price
    await orderBook.connect(alice).limitOrders([limitOrder]);

    let orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price);
    expect(orders.length).to.eq(maxOrdersPerPrice);

    orders = await orderBook.allOrdersAtPrice(OrderSide.Buy, tokenId, price - tick);
    expect(orders.length).to.eq(1);
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
      ])
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
      ])
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
      ])
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
      ])
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
      const limitOrder: LimitOrder = {
        side: OrderSide.Buy,
        tokenId,
        price,
        quantity,
      };

      const limitOrders = new Array<LimitOrder>(maxOrdersPerPrice).fill(limitOrder);
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
    const {orderBook, erc1155, brush, owner, alice, dev, royaltyRecipient, tokenId, initialBrush} = await loadFixture(
      deployContractsFixture
    );

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
    const {orderBook, erc1155, brush, owner, alice, dev, royaltyRecipient, tokenId, initialBrush} = await loadFixture(
      deployContractsFixture
    );

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
    expect(await orderBook.nftClaimable([orderId], [tokenId])).to.eq(0);
    expect(await orderBook.nftClaimable([orderId + 1], [tokenId])).to.eq(0);

    expect(await brush.balanceOf(owner)).to.eq(initialBrush);
    await expect(orderBook.claimTokens([orderId]))
      .to.emit(orderBook, "ClaimedTokens")
      .withArgs(owner.address, [orderId], cost - fees);
    expect(await brush.balanceOf(owner)).to.eq(initialBrush + cost - fees);
    expect(await orderBook.tokensClaimable([orderId], false)).to.eq(0);

    // Try to claim twice
    await expect(orderBook.claimTokens([orderId])).to.be.revertedWithCustomError(orderBook, "NothingToClaim");
  });

  it("Claim NFTs", async function () {
    const {orderBook, erc1155, owner, alice, tokenId} = await loadFixture(deployContractsFixture);

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
    expect(await orderBook.nftClaimable([orderId], [tokenId])).to.eq(10);
    expect(await orderBook.nftClaimable([orderId + 1], [tokenId])).to.eq(0);

    await expect(orderBook.claimNFTs([orderId], [tokenId]))
      .to.emit(orderBook, "ClaimedNFTs")
      .withArgs(owner.address, [orderId], [tokenId], [10]);
    expect(await orderBook.nftClaimable([orderId], [tokenId])).to.eq(0);

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
      ])
    ).to.throw;

    await expect(
      orderBook.limitOrders([
        {
          side: OrderSide.Sell,
          tokenId,
          price: ethers.parseEther("4700"),
          quantity,
        },
      ])
    ).to.throw;
  });

  // Assuming royalty fee is 10%, burnt fee is 0.3% and dev fee is 0.3%
  const calcFees = (cost: number, ignoreRoyalty: boolean) => {
    let royalty = ignoreRoyalty ? 0 : cost / 10;
    const burnt = (cost * 3) / 1000; // 0.3%
    const devAmount = (cost * 3) / 1000; // 0.3%
    return Math.floor(royalty + burnt + devAmount);
  };

  // it("TODO Edit order", async function () {});
  // Test multiple tokenIds
  // Test is gas more efficient by just sending the nft/brush directly instead of storing myself)
  // Test editing order (once implemented)
  // Test bulk edit
  // Remove id and only allow 1 order per address?
  // Fuzz test of many orders
  // Can take from yourself?
});