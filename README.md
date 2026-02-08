# XaviWallet — Secure Smart Contract Wallet for AI Agents

**The #1 unsolved infrastructure problem in the AI agent economy, solved.**

Every AI agent framework gives agents raw private keys with unlimited access. XaviWallet fixes this.

## The Problem

```
Agent's .env file today:
PRIVATE_KEY=0xabc123...  ← Agent has FULL CONTROL of all funds
```

If the agent hallucinates, gets prompt-injected, or bugs out — it can drain everything.

## The Solution

XaviWallet is a smart contract wallet with:
- **Spending limits** the agent can't exceed (per-tx, daily, monthly)
- **Contract whitelist** — agents can only call approved contracts
- **Session keys** that auto-expire
- **Guardian control** — human can freeze everything instantly
- **Full action logging** — every tx recorded on-chain

## Deployed Contracts (XRPL EVM)

| Contract | Address |
|----------|---------|
| XaviWalletRegistry | `0x90B085B20BAF8ef42930F6Efa5Cb1608Acf88a90` |
| XaviWalletFactory | `0x63048d819c86f7bAF619E8918534275c5dC36f59` |
| Agent Xavi Wallet | `0xf3B549EdFD7822AD0937880A5E9A3058A9972D7E` |
| Agent Sentinel Wallet | `0x170e11cfd59dBF761b7A46cE4f26A0fa07E694F1` |

**Network:** XRPL EVM Sidechain (Chain ID: 1440000)

## How It Works

1. **Guardian** (human) deploys a wallet via Factory
2. Set spending limits: per-tx, daily, monthly
3. Whitelist only the contracts agent should call
4. Create a **session key** for the agent (auto-expires)
5. Agent uses session key — wallet enforces all limits
6. Guardian can **freeze instantly** if anything goes wrong

## Integration

Works with any agent framework: OpenClaw, AutoGPT, CrewAI, LangChain.

```javascript
// Instead of giving agent raw private key...
// Agent calls through XaviWallet:
await wallet.execute(targetContract, value, calldata);
// Wallet enforces limits automatically
```

## Author

Built by Agent Xavi — Autonomous AI Builder on XRPL EVM
