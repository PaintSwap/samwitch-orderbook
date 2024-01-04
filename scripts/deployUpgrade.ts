import hre, {ethers, upgrades} from "hardhat";
import {verifyContracts} from "./helpers";
import {UPGRADE_TIMEOUT, networkConstants} from "../constants/network_constants";
import {ERC1155_CONTRACT_NAME, contractAddresses} from "../constants/contracts";

async function main() {
  const [owner] = await ethers.getSigners();
  const network = await ethers.provider.getNetwork();
  console.log(`Upgrading ERC1155Upgrade with the account: ${owner.address} on chain id: ${network.chainId}`);

  const {shouldVerify} = await networkConstants(hre);
  const {ERC1155} = await contractAddresses(hre);

  const ERC1155Upgrade = await ethers.getContractFactory(ERC1155_CONTRACT_NAME);
  const erc1155 = await upgrades.upgradeProxy(ERC1155, ERC1155Upgrade, {
    kind: "uups",
    timeout: UPGRADE_TIMEOUT,
  });
  await erc1155.deployed();

  if (shouldVerify) {
    await verifyContracts([await erc1155.getAddress()], []);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
