# SWOB (SamWitchOrderBook) for ERC1155 NFTs

[![Continuous integration](https://github.com/PaintSwap/samwitch-orderbook/actions/workflows/main.yml/badge.svg)](https://github.com/PaintSwap/samwitch-orderbook/actions/workflows/main.yml)

![swob](https://github.com/PaintSwap/samwitch-orderbook/assets/84033732/977c060f-e6e7-418f-9d44-1012599f41c6)

This efficient order book utilises the `BokkyPooBahsRedBlackTreeLibrary` library for sorting prices allowing `O(log n)` for tree segment insertion, traversal, and deletion. It supports batch orders and batch cancelling, `ERC2981` royalties, and a dev and burn fee on each trade.

It is kept gas efficient by packing data in many areas:

- Four orders (`uint24` quantity + `uint40` order id) into a 256bit word giving a 4x improvement compared to using 1 storage slot per order
- When taking from the order book no tokens/nfts are transferred. Instead the orderId is stored in a claimable array
- The tokens claimable are packed with 3 orders per storage slot

The order book is kept healthy by requiring a minimum quantity that can be added - partial quantities can still be taken from the order book. Cancelling orders shifts all entries at that price level to remove gaps.

Constraints:

- The order quantity is limited to ~16mil
- The maximum number of orders in the book that can ever be added is limited to 1 trillion
- The maximum number of orders that can be added to a specific price level is between 4.2 - 16 billion

While this order book was created for `ERC1155` NFTs it could be adapted for `ERC20` tokens.

> _Note: Not suitable for production until more tests are added with more code coverage._

Potential improvements:

- Use an `orderId` per price level insted of global, so that they are always sequential
- Range delete of the red-black tree using split/join
- The tree, either pack `red` & `numDeletedInSegment` or reduce number of decimals for the `price` and use `uint64` instead

To start copy the `.env.sample` file to `.env` and fill in `PRIVATE_KEY` at a minimum (starts with `0x`).

```shell
yarn install

# To compile the contracts
yarn compile

# To run the tests
yarn test

# To get code coverage
yarn coverage

# To deploy all contracts
yarn deploy --network <network>
yarn deploy --network fantom_testnet

# Export abi
yarn abi

# To fork or open a node connection
yarn fork
yarn fork --fork <rpc_url>
yarn fork --fork https://rpc.ftm.tools

# To impersonate an account on a forked or local blockchain for debugging
yarn impersonate
```
