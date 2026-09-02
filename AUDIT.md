# Product + security audit (UHI10)

See Fair Path `AUDIT.md` for the shared v4 rules. This repo’s extra fixes:

- Private path: TEE `isFair` or EIP-712 `PrivateReceipt` bound to `poolId`, burned after use.
- Expired receipts revert `Expired`.
- `creditSurplus` is relayer-only, `safeTransferFrom`, donate → settle in `unlock`.
- Relayer is owner-set; not a permissionless mock refund.

Tests: public tax, private receipt, replay, TEE heartbeat, surplus credit, fork smoke.

## Residual (accepted)

- `creditSurplus` trusts the owner-set relayer (Protect / MEV-Share role).
- Empty `hookData` is private only while `policy.isFair` is true for the current block.
