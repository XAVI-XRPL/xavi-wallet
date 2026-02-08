const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying XaviWallet System with account:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", hre.ethers.formatEther(balance), "XRP\n");

  // 1. Deploy Registry
  console.log("1. Deploying XaviWalletRegistry...");
  const Registry = await hre.ethers.getContractFactory("XaviWalletRegistry");
  const registry = await Registry.deploy();
  await registry.waitForDeployment();
  const registryAddress = await registry.getAddress();
  console.log("   XaviWalletRegistry deployed to:", registryAddress);

  // 2. Deploy Factory
  console.log("\n2. Deploying XaviWalletFactory...");
  const Factory = await hre.ethers.getContractFactory("XaviWalletFactory");
  const factory = await Factory.deploy();
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  console.log("   XaviWalletFactory deployed to:", factoryAddress);

  // 3. Link Factory to Registry
  console.log("\n3. Linking Factory to Registry...");
  const setRegTx = await factory.setRegistry(registryAddress);
  await setRegTx.wait();
  console.log("   Factory linked to Registry");

  // 4. Create Agent Xavi's wallet
  console.log("\n4. Creating Agent Xavi's secure wallet...");
  const dailyLimit = hre.ethers.parseEther("50");  // 50 XRP daily
  const perTxLimit = hre.ethers.parseEther("10");  // 10 XRP per tx
  
  const createTx = await factory.createWallet(
    deployer.address,  // Guardian is deployer (Marc)
    "Agent Xavi",
    dailyLimit,
    perTxLimit
  );
  const receipt = await createTx.wait();
  
  // Get wallet address from event
  const event = receipt.logs.find(log => {
    try {
      return factory.interface.parseLog(log)?.name === "WalletCreated";
    } catch { return false; }
  });
  const parsedEvent = factory.interface.parseLog(event);
  const xaviWalletAddress = parsedEvent.args.wallet;
  console.log("   Agent Xavi's Wallet deployed to:", xaviWalletAddress);

  // 5. Register wallet in registry
  console.log("\n5. Registering wallet in registry...");
  const regTx = await registry.registerWallet(xaviWalletAddress, "Agent Xavi", "openclaw");
  await regTx.wait();
  console.log("   Wallet registered as 'openclaw' platform");

  // 6. Verify wallet
  console.log("\n6. Verifying wallet...");
  const verifyTx = await registry.verifyWallet(xaviWalletAddress);
  await verifyTx.wait();
  console.log("   Wallet verified ✓");

  // 7. Create Sentinel's wallet
  console.log("\n7. Creating Agent Sentinel's secure wallet...");
  const sentinelDailyLimit = hre.ethers.parseEther("5");  // 5 XRP daily (auditor needs less)
  const sentinelPerTxLimit = hre.ethers.parseEther("1");  // 1 XRP per tx
  
  const sentinelCreateTx = await factory.createWallet(
    deployer.address,
    "Agent Sentinel",
    sentinelDailyLimit,
    sentinelPerTxLimit
  );
  const sentinelReceipt = await sentinelCreateTx.wait();
  
  const sentinelEvent = sentinelReceipt.logs.find(log => {
    try {
      return factory.interface.parseLog(log)?.name === "WalletCreated";
    } catch { return false; }
  });
  const sentinelParsedEvent = factory.interface.parseLog(sentinelEvent);
  const sentinelWalletAddress = sentinelParsedEvent.args.wallet;
  console.log("   Agent Sentinel's Wallet deployed to:", sentinelWalletAddress);

  // 8. Register Sentinel wallet
  console.log("\n8. Registering Sentinel wallet...");
  const sentinelRegTx = await registry.registerWallet(sentinelWalletAddress, "Agent Sentinel", "openclaw");
  await sentinelRegTx.wait();
  const sentinelVerifyTx = await registry.verifyWallet(sentinelWalletAddress);
  await sentinelVerifyTx.wait();
  console.log("   Sentinel wallet registered and verified ✓");

  console.log("\n" + "=".repeat(60));
  console.log("XaviWallet System Deployment Complete!");
  console.log("=".repeat(60));
  console.log("XaviWalletRegistry: ", registryAddress);
  console.log("XaviWalletFactory:  ", factoryAddress);
  console.log("Agent Xavi Wallet:  ", xaviWalletAddress);
  console.log("Agent Sentinel Wallet:", sentinelWalletAddress);
  console.log("Guardian:           ", deployer.address);
  console.log("=".repeat(60));
  console.log("\nAgent Xavi Limits:");
  console.log("  Per-TX:  10 XRP");
  console.log("  Daily:   50 XRP");
  console.log("\nAgent Sentinel Limits:");
  console.log("  Per-TX:  1 XRP");
  console.log("  Daily:   5 XRP");
  console.log("=".repeat(60));

  // Check remaining balance
  const finalBalance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("\nGas used:", hre.ethers.formatEther(balance - finalBalance), "XRP");
  console.log("Remaining balance:", hre.ethers.formatEther(finalBalance), "XRP");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
