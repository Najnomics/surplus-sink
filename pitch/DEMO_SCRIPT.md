# Surplus Sink — 5-Minute Demo Video Guide

A shot-by-shot script for a UHI10 submission video that combines the **pitch deck** and the **live web app**. Total runtime: **~5:00**.

- **Deck:** https://uhi10-surplus-sink-pitch.vercel.app — `F` fullscreen, `→` advance, `S` speaker notes
- **App:** https://uhi10-surplus-sink.vercel.app
- **Contracts (Unichain Sepolia, 1301):** SurplusSinkHook `0xc3EE…50c4`

---

## 0. Before you hit record (15 min of prep)

**Recording setup**
- **OBS Studio**, **QuickTime**, or **Loom**. **1920×1080**, 30fps.
- Scene A = deck. Scene B = app. Or whole-screen + `Cmd-Tab`.

**Browser / wallet prep**
1. Connect on **Unichain Sepolia**. Faucet **ssVOL / ssUSD** now.
2. Pre-check tape for tax / receipt / `creditSurplus` events.
3. Hero path:
   - **Public swap** — tax `donate()` immediately.
   - **Private / relayer path** — mint `SurplusReceipt`.
   - **creditSurplus** — leftover donates into LPs.
4. Zoom ~110–125%. Do Not Disturb.

**Timing tip:** pre-run one public + one credited private fill so the tape is rich, then do one live `creditSurplus` on camera.

---

## 1. The 5-minute script

> Cut points ✂️. Quotes are voiceover — adapt.

### 0:00 – 0:20 · Title ✂️ deck
> "This is **Surplus Sink** — a Uniswap v4 hook that treats the pool as the refund address for private orderflow leftover. Live on Unichain Sepolia."

### 0:20 – 0:50 · Problem → Insight
> "RFQ and solver flow often improves on quote. That surplus sits in the relayer wallet. Public toxic flow still hits LPs with no extra bill."

> "Our insight: tax the public lane. Mint a receipt on private fills. `creditSurplus` donates it home. Two lanes, one sink."

### 0:50 – 1:20 · How → Trust → Fees
> "`afterSwap` splits public versus private. Relayers prove improvement with TEE or EIP-712. Bad or expired receipts revert — we don't invent surplus, we settle it."

### 1:20 – 3:40 · LIVE APP ✂️ browser

**(1:20) Trade**
> "Live console, v4 SDK, ssVOL / ssUSD."

**(1:45) Public tax**
> "Untagged swap. The hook skims a tax and `donate`s to in-range LPs. Watch the tape."

**(2:30) Private receipt**
> "Now a private fill. Instead of keeping leftover off-chain, the hook mints a SurplusReceipt."

**(3:00) creditSurplus**
> "Relayer credits the receipt. Surplus `donate`s into the same pool. That's the refund address."

**(3:20) Tape**
> "Tax, receipt, credit — all events the contract can prove. `BadReceipt` would revert, not fake a donate."

### 3:40 – 4:20 · Flywheel + UHI10 ✂️ deck
> "Public tax and private surplus both sink to LPs. Yield rises, better quotes, more RFQ routed here."

> "Sustainable liquidity and MEV protection: bill the public lane, receipt the private leftover."

### 4:20 – 4:50 · Deployed
> "Hook, oracle, and relayer live on Unichain Sepolia. Repo open. Try the desk."

### 4:50 – 5:00 · Closing
> "Leftover had a wallet. It should have been the pool. Thanks for watching."

---

## 2. Quick shot list

| Time | Source | Content |
|------|--------|---------|
| 0:00 | Deck | Title |
| 0:20 | Deck | Problem + Insight |
| 0:50 | Deck | How + receipt + fees |
| 1:20 | App | Trade |
| 1:45 | App | Public swap → tax donate |
| 2:30 | App | Private → SurplusReceipt |
| 3:00 | App | creditSurplus |
| 3:20 | App | Tape |
| 3:40 | Deck | Flywheel + Why UHI10 |
| 4:20 | Deck | Deployed |
| 4:50 | Deck | Closing |

---

## 3. Pro tips

- Rehearse **creditSurplus** once off-camera.
- Show **Unichain Sepolia** in the wallet.
- Lower-third: `uhi10-surplus-sink.vercel.app`
- Your voice only — no AI voice.
- Export 1080p H.264, under ~200 MB.
