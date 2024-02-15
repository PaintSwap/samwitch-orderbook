import {run} from "hardhat";

// If there's an error with build-info not matching then delete cache/artifacts folder and try again
export const verifyContracts = async (addresses: string[], args: any[][] = []) => {
  for (const address of addresses) {
    const constructorArguments = args.length == addresses.length ? args[addresses.indexOf(address)] : [];
    await run("verify:verify", {
      address,
      constructorArguments,
    });
  }
  console.log("Verified all contracts");
};

export const swobAddress = "0x4E9cBCB9Ac26c80E55804535A5112aB54d77e75d";

export enum OrderSide {
  Buy,
  Sell,
}
