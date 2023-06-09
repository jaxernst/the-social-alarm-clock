import { parseEther } from "ethers/lib/utils";
import hre, { ethers } from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();

const VAL = parseEther("1");

async function main() {
  if (hre.network.name !== "localhost") throw Error(`Localhost not selected`);

  if (!process.env.TEST_WALLET) {
    throw Error(".env must have TEST_WALLET to send funds to");
  }
  const [signer] = await ethers.getSigners();
  signer.sendTransaction({
    to: process.env.TEST_WALLET,
    value: VAL,
  });

  signer.sendTransaction({
    to: "0x9B8DB9bffcCd1F2Cc5044d67a1b9C68dD6Deff6a",
    value: VAL,
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
