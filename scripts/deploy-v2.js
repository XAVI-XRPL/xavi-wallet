const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Redeploying XaviWallet v1.1.0 (Security Hardened)");
  console.log("Deployer:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Balance:", hre.ethers.formatEther(balance), "XRP\n");

  // 1. Deploy Registry
  console.log("1. Deploying XaviWalletRegistry v1.1.0...");
  const Registry = await hre.ethers.getContractFactory("XaviWalletRegistry");
  const registry = await Registry.deploy();
  await registry.waitForDeployment();
  const registryAddress = await registry.getAddress();
  console.log("   Registry:", registryAddress);

  // 2. Deploy Factory
  console.log("\n2. Deploying XaviWalletFactory v1.1.0...");
  const Factory = await hre.ethers.getContractFactory("XaviWalletFactory");
  const factory = await Factory.deploy();
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  console.log("   Factory:", factoryAddress);

  // 3. Create Agent Xavi's wallet
  console.log("\n3. Creating Agent Xavi's secure wallet...");
  const dailyLimit = hre.ethers.parseEther("50");
  const perTxLimit = hre.ethers.parseEther("10");
  
  const createTx = await factory.createWallet(
    deployer.address,
    "Agent Xavi",
    dailyLimit,
    perTxLimit
  );
  const receipt = await createTx.wait();
  
  const event = receipt.logs.find(log => {
    try { return factory.interface.parseLog(log)?.name === "WalletCreated"; }
    catch { return false; }
  });
  const parsedEvent = factory.interface.parseLog(event);
  const xaviWalletAddress = parsedEvent.args.wallet;
  console.log("   Xavi Wallet:", xaviWalletAddress);

  // 4. Create Sentinel's wallet
  console.log("\n4. Creating Agent Sentinel's secure wallet...");
  const sentinelCreateTx = await factory.createWallet(
    deployer.address,
    "Agent Sentinel",
    hre.ethers.parseEther("5"),
    hre.ethers.parseEther("1")
  );
  const sentinelReceipt = await sentinelCreateTx.wait();
  const sentinelEvent = sentinelReceipt.logs.find(log => {
    try { return factory.interface.parseLog(log)?.name === "WalletCreated"; }
    catch { return false; }
  });
  const sentinelWalletAddress = factory.interface.parseLog(sentinelEvent).args.wallet;
  console.log("   Sentinel Wallet:", sentinelWalletAddress);

  console.log("\n" + "=".repeat(60));
  console.log("XaviWallet v1.1.0 Deployment Complete!");
  console.log("=".repeat(60));
  console.log("XaviWalletRegistry: ", registryAddress);
  console.log("XaviWalletFactory:  ", factoryAddress);
  console.log("Agent Xavi Wallet:  ", xaviWalletAddress);
  console.log("Agent Sentinel Wallet:", sentinelWalletAddress);
  console.log("Guardian:           ", deployer.address);
  console.log("=".repeat(60));
  console.log("\nSecurity Features (v1.1.0):");
  console.log("  ✓ 48-hour guardian transfer delay");
  console.log("  ✓ Max 30-day session duration");
  console.log("  ✓ Max 5 sessions per 24 hours");
  console.log("  ✓ Nonce for replay protection");
  console.log("  ✓ Max batch size of 10");
  console.log("  ✓ Emergency revokeAllSessions()");
  console.log("  ✓ ActionFailed event logging");
  console.log("  ✓ Overflow checks");
  console.log("  ✓ Target validation (no self/guardian calls)");
  console.log("  ✓ Registry: 1 XRP min balance to register");
  console.log("=".repeat(60));

  const finalBalance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("\nGas used:", hre.ethers.formatEther(balance - finalBalance), "XRP");
  console.log("Remaining:", hre.ethers.formatEther(finalBalance), "XRP");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
