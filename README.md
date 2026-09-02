# Surplus Sink

[![License: MIT](https://img.shields.io/badge/License-MIT-informational.svg)](./LICENSE)
[![Uniswap v4](https://img.shields.io/badge/Uniswap-v4%20hook-7c8bff.svg)](https://docs.uniswap.org/contracts/v4/overview)

UHI10 — *Sustainable Liquidity & MEV Protection*

> **Private orderflow sits beside Uniswap. This hook is the first pool that is the refund address.**

---

## The idea

**Surplus Sink is a Uniswap v4 hook that makes a Uniswap pool the settlement destination for Flashbots Protect / MEV-Share surplus.**

Private order-flow systems already exist. They sit **off to the side** of Uniswap (UHI10 theme problem #5). Refunds and backrun shares go to the user, the builder, or an off-chain accounting pipe. The pool that created the MEV — the LPs who took the other side — gets nothing.

Surplus Sink closes that gap:

- **Private path** (Protect / MEV-Share): the swap still lands in the v4 pool. Inclusion proofs or refund callbacks **credit the hook**. The hook **`donate`s that surplus to in-range LPs**.
- **Public path**: no proof, no refund. The swap is priced as **unattested toxic flow** (premium fee + recapture tax), so public mempool flow cannot free-ride the private lane.

Same pool. Two ingresses. One LP sink.

This is the official UHI10 **hybrid-routing** prompt with a partner **none of the 660 prior directory rows integrated**: Flashbots Protect / MEV-Share. Fourteen homegrown "CoW" matchers exist. Zero Protect.

## The problem it solves

- **Protect refunds the user, not the LP.** The inventory that was arb'd is still LP inventory. Surplus Sink pays the LP.
- **MEV-Share is a hint marketplace.** Without a pool-level sink, Uniswap is just another orderflow source. With a sink, **this pool is the venue that internalizes its own MEV**.
- **Fake hybrid routers** in past cohorts matched intents off-chain and called it CoW. They did not speak Protect. Unique execution for UHI10 is a **real interface**, even if the demo uses a recorded refund adapter.
- **Attestation-only hooks** (Fair Flow / Fair Path corridor 1) ask "was the *block* fair?" Surplus Sink asks "did *this swap* come in privately, and where did the refund go?" Both are fair-flow. They are not the same question.

## How it works

There are two honest layers. Do not pretend the hook can see Flashbots from inside `beforeSwap` without a proof.

**On-chain (the hook)**

1. **`beforeSwap`** — private if a registered TEE builder has heartbeated this block (`UnichainFairOracle.isFair`) **or** `hookData` is a valid EIP-712 `PrivateReceipt` signed by an owner-set relayer and bound to this `poolId`. Then `PRIVATE_FEE` (0.05%). Else `PUBLIC_FEE` (1.00%).
2. **`afterSwap`** — public path: skim `PUBLIC_TAX_BIPS` of the unspecified token and `donate` to LPs. Private path: no tax. Receipts are burned so they cannot be replayed.
3. **`creditSurplus(key, amountOn0, amount)`** — **relayer only**. `safeTransferFrom` real tokens, then `donate` → `settle` inside `PoolManager.unlock`.

**Off-chain (the relayer)**

The relayer is whoever Flashbots Protect / MEV-Share (or your TEE builder) pays. That address is `setRelayer`'d. It signs receipts and later `creditSurplus`s. There is no permissionless mock refund.

```mermaid
flowchart TD
    A[Swap submitted] --> B{private proof in hookData?}
    B -- "yes · Protect / MEV-Share" --> C["beforeSwap: PRIVATE_FEE 0.05%"]
    C --> D[afterSwap: record swapHash → poolId]
    D --> E[Adapter receives refund]
    E --> F["creditSurplus → donate to in-range LPs"]
    B -- "no · public mempool" --> G["beforeSwap: PUBLIC_FEE 1.00%"]
    G --> H["afterSwap: skim PUBLIC_TAX · donate"]
    F --> I[emit SurplusCredited]
    H --> I
```

```mermaid
flowchart LR
    U[User] -- "Protect RPC / MEV-Share" --> FB[Flashbots]
    FB -- "bundle lands on Unichain / ETH" --> PM[PoolManager]
    PM -- "hook callbacks" --> H[SurplusSinkHook]
    FB -- "refund / backrun share" --> AD[ProtectAdapter]
    AD -- "creditSurplus" --> H
    H -- "donate" --> LP[In-range LPs]
```

## Proof model — how the hook knows a path is private

The hook **does not** call Flashbots. It verifies a **seam**:

1. **TEE / Flashtestations** — `UnichainFairOracle` (live `FlashblockNumber` or owner-gated builder keys).
2. **Protect-shaped EIP-712** — `PrivateReceipt(deadline, nonce, poolId)` signed by `isRelayer[signer]`.

`creditSurplus` pulls ERC-20 from that same relayer. Do not claim in the video that a testnet relayer key *is* Flashbots mainnet. Claim the **signed receipt + real donate**.

## Complete user flow

```mermaid
sequenceDiagram
    actor User
    participant UI as Console
    participant Protect as Relayer / Protect

    participant PM as PoolManager
    participant Hook as SurplusSinkHook
    participant LPs as In-range LPs

    alt Send private
        User->>UI: Swap via private path
        UI->>Protect: submit + signed receipt

        Protect->>PM: swap(hookData = proof)
        PM->>Hook: beforeSwap → PRIVATE_FEE
        PM->>Hook: afterSwap → map swapHash
        Protect->>Hook: creditSurplus(poolId, refund)
        Hook->>PM: donate(refund) to LPs
    else Send public
        User->>UI: Swap via public mempool
        UI->>PM: swap(hookData empty)
        PM->>Hook: beforeSwap → PUBLIC_FEE
        PM->>Hook: afterSwap → take tax, donate
    end
    Hook-->>UI: emit SwapClassified / SurplusCredited
```

## Hook functions implemented

| Function | Permission | What it does |
|---|---|---|
| `getHookPermissions` | — | `afterInitialize`, `beforeSwap`, `afterSwap`, `afterSwapReturnDelta`. |
| `_afterInitialize` | `afterInitialize` | Require dynamic-fee flag. |
| `_beforeSwap` | `beforeSwap` | Verify private proof; override `PRIVATE_FEE` or `PUBLIC_FEE`. |
| `_afterSwap` | `afterSwap` + return delta | Public: recapture tax. Private: record `swapHash → poolId`. |
| `creditSurplus` | — | Adapter-only; `donate` surplus to the mapped pool. |

**On-chain parameters & state**

| Name | Value / type | Meaning |
|---|---|---|
| `PRIVATE_FEE` | `500` (0.05%) | Fee when the private-path proof verifies |
| `PUBLIC_FEE` | `10_000` (1.00%) | Fee when it does not |
| `PUBLIC_TAX_BIPS` | `50` (0.50%) | Output skim donated on the public path |
| `totalSurplusDonated[poolId]` | `uint256` | Protect / MEV-Share credits donated |
| `totalPublicTaxDonated[poolId]` | `uint256` | Public-path recapture |
| `swapPool[swapHash]` | `PoolId` | Routing key for the adapter |
| `SwapClassified` | `event` | Private vs public, fee, tax |
| `SurplusCredited` | `event` | Adapter, pool, amount |

## Integrations

| Layer | Integration | Used for |
|---|---|---|
| **Uniswap v4 core** | `PoolManager`, dynamic-fee override, `donate`, `CurrencySettler` | Path-priced fees + LP sink |
| **OpenZeppelin** | `uniswap-hooks` `BaseHook` | Hook base |
| **Flashbots** | Protect RPC, MEV-Share refunds (production); `IPrivatePathVerifier` + adapter (this repo) | Private ingress + surplus |
| **Frontend / SDK** | `viem`, React, `@uniswap/v4-sdk` | Send private vs Send public, LP pot, event tape |

**Partner integrations (hookathon README requirement)**

- **Flashbots Protect / MEV-Share** — partner. The hook verifies EIP-712 receipts from an owner-set relayer and donates `creditSurplus` tokens. TEE path uses Unichain Flashtestations / `FlashblockNumber`. No mock verifier in `src/`.

## Why it's profitable — as an idea and a business

```mermaid
flowchart LR
    A[Private flow earns a refund] --> B[Refund donated to this pool's LPs]
    B --> C[LPs prefer this venue]
    C --> D[Aggregators route private flow here]
    D --> E[More Protect volume]
    E --> A
    F[Public flow pays tax] --> B
```

**For LPs.** They finally get the MEV their inventory created when users routed privately *and* a tax when users did not.

**For private-path traders.** Cheap fee (0.05%) plus sandwich resistance from Protect. They do not lose the refund — the design can split user vs LP later; v1 can send 100% to LPs and still be the only pool that *can* receive it.

**For Flashbots.** A Uniswap-native sink is a reason for searchers and wallets to keep Protect pointed at **pools that speak the adapter**. That is a distribution story, not a fork.

**For the protocol.** Two fee lines: public tax, private surplus. Both MEV-native. Neither taxes attested/private retail as a penalty.

**Why it fits UHI10.** Official prompt: hybrid routing between private orderflow and Uniswap. Official cheat code: **0 / 660 Flashbots integrations**. Win condition: defense (private path) + recapture (donate).

## What this is not

- Not Fair Path (no flashblock slot schedule, no searcher slash).
- Not Sold Backrun (no on-pool backrun NFT / auction).
- Not a homegrown CoW matcher.
- Not a claim that the testnet relayer *is* Flashbots mainnet. The video must say **signed receipt + donate is real**.

## The console

Live: **https://uhi10-surplus-sink.vercel.app**

Private vs public swap on **ssVOL / ssUSD**. Relayer `creditSurplus` is live via `SinkAgent` on Sepolia.

## Testing

`forge test` — public tax, private receipt (no tax), receipt replay revert, TEE heartbeat private, relayer `creditSurplus`, unauthorized credit revert, garbage `hookData` revert.

## Repository layout

```
src/
  SurplusSinkHook.sol
  UnichainFairOracle.sol
  interfaces/
test/
  SurplusSinkHook.t.sol
script/
  DeployUnichain.s.sol
  PopulateTraffic.s.sol
frontend/
```

## Hookathon gates

- Public repo (this repository)
- Valid Uniswap v4 hook
- Functioning frontend: https://uhi10-surplus-sink.vercel.app
- README partner integrations: Flashbots Protect / MEV-Share + Unichain Flashtestations
- Video: Send private vs Send public, LP tickers, no AI voice
- Original work for UHI10; not a resubmission of Fair Flow
