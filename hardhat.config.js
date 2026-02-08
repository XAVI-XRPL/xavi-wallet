require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      viaIR: true
    }
  },
  networks: {
    xrplevm: {
      url: "https://rpc.xrplevm.org",
      chainId: 1440000,
      accounts: process.env.XAVI_PRIVATE_KEY ? [process.env.XAVI_PRIVATE_KEY] : []
    }
  }
};
