# Security notes

- Hook callbacks are PoolManager-only (`BaseHook`).
- Private path: TEE heartbeat (`UnichainFairOracle.isFair`) **or** EIP-712 receipt signed by an owner-set relayer, bound to `poolId`, burned after use.
- Public path: recapture tax via take → donate → settle.
- `creditSurplus` is relayer-only, `nonReentrant`, `safeTransferFrom`, then donate → settle inside `unlock`.
- `.env` is gitignored. Never commit keys.
