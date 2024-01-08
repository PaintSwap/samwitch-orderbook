# ERC1155 Orderbook (SWOB SamWitchOrderBook)

[![Continuous integration](https://github.com/PaintSwap/SamWitchOrderBook/actions/workflows/main.yml/badge.svg)](https://github.com/PaintSwap/SamWitchOrderBook/actions/workflows/main.yml)

To start copy the .env.sample file to .env and fill in PRIVATE_KEY at minimum, starts with 0x

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
