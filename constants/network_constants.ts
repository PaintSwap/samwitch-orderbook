import {HardhatRuntimeEnvironment} from "hardhat/types";

export const UPGRADE_TIMEOUT = 600 * 1000; // 10 minutes

export type NetworkConstants = {
  numBlocksWait: number;
  shouldVerify: boolean;
};

export const networkConstants = async (hre: HardhatRuntimeEnvironment): Promise<NetworkConstants> => {
  const network = await hre.ethers.provider.getNetwork();

  let numBlocksWait = 1;
  let shouldVerify = false;
  switch (network.chainId) {
    case 31337n: // hardhat
      break;
    case 4002n: // Fantom testnet
      numBlocksWait = 1;
      break;
    case 250n: // Fantom
      numBlocksWait = 1;
      shouldVerify = true;
      break;
    default:
      throw Error("Not a supported network");
  }

  return {
    numBlocksWait,
    shouldVerify,
  };
};
