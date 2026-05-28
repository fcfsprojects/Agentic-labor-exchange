import { ethers } from "hardhat";

async function main() {
  console.log("🚀 Deploying ALX Protocol to Base...");

  const [deployer] = await ethers.getSigners();
  console.log(`Deploying with account: ${deployer.address}`);

  // Get network info
  const network = await ethers.provider.getNetwork();
  console.log(`Network: ${network.name} (Chain ID: ${network.chainId})`);

  // 1. Deploy AgentRegistry
  console.log("\n📍 Deploying AgentRegistry...");
  const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
  const agentRegistry = await AgentRegistry.deploy();
  await agentRegistry.waitForDeployment();
  const agentRegistryAddr = await agentRegistry.getAddress();
  console.log(`✅ AgentRegistry deployed to: ${agentRegistryAddr}`);

  // 2. Deploy BiddingEngine
  console.log("\n📍 Deploying BiddingEngine...");
  const BiddingEngine = await ethers.getContractFactory("BiddingEngine");
  const biddingEngine = await BiddingEngine.deploy();
  await biddingEngine.waitForDeployment();
  const biddingEngineAddr = await biddingEngine.getAddress();
  console.log(`✅ BiddingEngine deployed to: ${biddingEngineAddr}`);

  // 3. Deploy AlxEscrow
  console.log("\n📍 Deploying AlxEscrow...");
  const AlxEscrow = await ethers.getContractFactory("AlxEscrow");
  const alxEscrow = await AlxEscrow.deploy();
  await alxEscrow.waitForDeployment();
  const alxEscrowAddr = await alxEscrow.getAddress();
  console.log(`✅ AlxEscrow deployed to: ${alxEscrowAddr}`);

  // 4. Deploy VerificationPool
  console.log("\n📍 Deploying VerificationPool...");
  const VerificationPool = await ethers.getContractFactory("VerificationPool");
  const verificationPool = await VerificationPool.deploy();
  await verificationPool.waitForDeployment();
  const verificationPoolAddr = await verificationPool.getAddress();
  console.log(`✅ VerificationPool deployed to: ${verificationPoolAddr}`);

  // 5. Deploy ReputationOracle
  console.log("\n📍 Deploying ReputationOracle...");
  const ReputationOracle = await ethers.getContractFactory("ReputationOracle");
  const reputationOracle = await ReputationOracle.deploy();
  await reputationOracle.waitForDeployment();
  const reputationOracleAddr = await reputationOracle.getAddress();
  console.log(`✅ ReputationOracle deployed to: ${reputationOracleAddr}`);

  // Set treasury addresses in AlxEscrow
  console.log("\n⚙️ Configuring AlxEscrow treasuries...");
  const protocolTreasury = deployer.address;
  const oracleTreasury = deployer.address;
  
  await alxEscrow.setTreasuries(protocolTreasury, oracleTreasury);
  console.log(`✅ Treasuries configured`);

  // Print deployment summary
  console.log("\n" + "=".repeat(60));
  console.log("🎉 ALX PROTOCOL DEPLOYED TO BASE");
  console.log("=".repeat(60));
  console.log("\nContract Addresses:");
  console.log(`
  AgentRegistry:      ${agentRegistryAddr}
  BiddingEngine:      ${biddingEngineAddr}
  AlxEscrow:          ${alxEscrowAddr}
  VerificationPool:   ${verificationPoolAddr}
  ReputationOracle:   ${reputationOracleAddr}
  `);

  console.log("\nDeployer Address:", deployer.address);
  console.log("Protocol Treasury:", protocolTreasury);
  console.log("Oracle Treasury:", oracleTreasury);

  // Save deployment info
  const deploymentInfo = {
    network: network.name,
    chainId: network.chainId,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      AgentRegistry: agentRegistryAddr,
      BiddingEngine: biddingEngineAddr,
      AlxEscrow: alxEscrowAddr,
      VerificationPool: verificationPoolAddr,
      ReputationOracle: reputationOracleAddr,
    },
    treasuries: {
      protocol: protocolTreasury,
      oracle: oracleTreasury,
    },
  };

  const fs = await import("fs");
  const deploymentPath = `./deployments/${network.name}-${Date.now()}.json`;
  
  if (!fs.existsSync("./deployments")) {
    fs.mkdirSync("./deployments", { recursive: true });
  }

  fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
  console.log(`\n📄 Deployment info saved to: ${deploymentPath}`);

  console.log("\n✨ Ready to bootstrap the agentic economy!");
  console.log("Next steps:");
  console.log("1. Register test agents on AgentRegistry");
  console.log("2. Create sample tasks and run auctions");
  console.log("3. Monitor reputation accumulation");
  console.log("4. Deploy to Base mainnet when ready\n");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});