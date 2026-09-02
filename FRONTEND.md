# Frontend (Opus 4.8 / Claude Code)

This repo ships **production Solidity**. Do not add a mock UI. Build a Uniswap v4 SDK
console (`@uniswap/v4-sdk`, `Pool.getOutputAmount`, `V4PositionManager.addCallParameters`,
StateView reads) the way Fair Flow did.

## Must prove on-chain

1. Public swap (`hookData` empty, no TEE heartbeat) — public tax ticker.
2. Private receipt: EIP-712 `PrivateReceipt(deadline, nonce, poolId)` signed by `relayer`.
3. TEE path: owner-set builder calls `UnichainFairOracle.incrementFlashblock`, then a
   cheap swap with empty `hookData`.
4. Relayer `creditSurplus` after `approve` — `totalSurplusDonated` ticks. Not a simulated refund.

## Stack

- Vite + React + wagmi + viem
- `@uniswap/v4-sdk` `@uniswap/sdk-core` `@uniswap/universal-router-sdk`
- Addresses from `deployments/unichain.json`
- Chain Unichain Sepolia 1301
- No AI voice in the demo video
