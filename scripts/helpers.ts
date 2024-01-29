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

export const swobAddress = "0x2d9D54b4FBa73777c9BE43916089202c74B2c8d8";
