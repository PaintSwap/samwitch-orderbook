import {HardhatUserConfig} from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-abi-exporter";
import "hardhat-contract-sizer";
import "hardhat-storage-layout";
import "solidity-coverage";
import "@primitivefi/hardhat-dodoc";
import {SolcUserConfig} from "hardhat/types";
import "dotenv/config";

const defaultConfig: SolcUserConfig = {
  version: "0.8.26",
  settings: {
    evmVersion: "paris",
    optimizer: {
      enabled: true,
      runs: 9999999,
      details: {
        yul: true,
      },
    },
    viaIR: process.env.HARDHAT_VIAIR != "false", // This cannot be used with coverage for instance
    outputSelection: {
      "*": {
        "*": ["storageLayout"],
      },
    },
  },
};

const mediumRunsConfig: SolcUserConfig = {
  ...defaultConfig,
  settings: {
    ...defaultConfig.settings,
    optimizer: {
      ...defaultConfig.settings.optimizer,
      runs: 1000,
    },
  },
};

const config: HardhatUserConfig = {
  solidity: {
    compilers: [defaultConfig, mediumRunsConfig],
    overrides: {
      "contracts/SamWitchOrderBook.sol": mediumRunsConfig,
    },
  },
  gasReporter: {
    enabled: process.env.GAS_REPORTER != "false",
    token: "FTM",
    currency: "USD",
    gasPriceApi: "https://api.ftmscan.com/api?module=proxy&action=eth_gasPrice",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  dodoc: {
    include: ["IBurnableToken.sol", "ISamWitchOrderBook.sol", "SamWitchOrderBook.sol"],
  },
  networks: {
    hardhat: {
      gasPrice: 0,
      initialBaseFeePerGas: 0,
      blockGasLimit: 30000000,
      allowUnlimitedContractSize: true,
    },
    fantom: {
      url: process.env.FANTOM_RPC,
      accounts: [process.env.PRIVATE_KEY as string],
    },
    fantom_testnet: {
      url: process.env.FANTOM_TESTNET_RPC,
      accounts: [process.env.PRIVATE_KEY as string],
    },
    fantom_sonic_testnet: {
      url: process.env.FANTOM_SONIC_TESTNET_RPC,
      accounts: [process.env.PRIVATE_KEY as string],
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  abiExporter: {
    path: "./data/abi",
    clear: true,
    flat: false,
  },
};

export default config;
