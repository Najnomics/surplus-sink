import { useState } from "react";
import { useAppData } from "../context/AppData";
import { useToast } from "../context/Toast";
import { addresses, explorerTx, isLocal, isZero } from "../lib/clients";
import { incrementFlashblock, mine, creditSurplus } from "../lib/actions";
import { short } from "../lib/format";

export function AttestationPage() {
  const { policy, signer, needsConnect, connect, refresh } = useAppData();
  const toast = useToast();
  const [busy, setBusy] = useState<string | null>(null);

  const fair = policy?.fairNow ?? false;
  const oracle = !isZero(addresses.oracle) ? addresses.oracle : addresses.policy;
  const configured = !isZero(oracle);

  async function pulse() {
    if (!signer) return;
    setBusy("incrementFlashblock…");
    try {
      const hash = await incrementFlashblock(signer.owner, signer.wc);
      if (isLocal) await mine(1);
      toast.ok("TEE builder heartbeat — flashblock incremented", explorerTx(hash));
      await refresh();
    } catch (e) {
      toast.err((e as Error).message.slice(0, 120));
    } finally {
      setBusy(null);
    }
  }

  async function advance(n: number) {
    setBusy(`Mining ${n} blocks…`);
    try {
      await mine(n);
      toast.info(`Mined ${n} blocks`);
      await refresh();
    } catch (e) {
      toast.err((e as Error).message.slice(0, 120));
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="grid cols-2" style={{ alignItems: "start" }}>
      <section className="card card-lg">
        <div className="card-head">
          <div>
            <h2>Attestation oracle</h2>
            <span className="muted">{configured ? short(oracle) : "not configured"}</span>
          </div>
        </div>

        <div className={`status-big ${fair ? "fair" : "toxic"}`}>
          <span className="sd" />
          <div>
            <strong>{fair ? "PRIVATE PATH (TEE)" : "PUBLIC PATH"}</strong>
            <small>
              {policy
                ? `current block ${policy.block.toString()} · fair until ${policy.fairUntilBlock.toString()}`
                : "reading oracle…"}
            </small>
          </div>
        </div>

        <p className="lead" style={{ fontSize: "0.9rem" }}>
          Owner-gated TEE builder heartbeat — not a mock window.{" "}
          <code style={{ fontFamily: "var(--font-mono)" }}>incrementFlashblock()</code>{" "}
          takes no duration. When fair, empty hookData is the private 5 bps path.
          Protect surplus is credited by the relayer via{" "}
          <code style={{ fontFamily: "var(--font-mono)" }}>creditSurplus</code>.
        </p>

        {needsConnect ? (
          <button className="btn btn-primary btn-lg" style={{ marginTop: 8 }} onClick={connect}>
            Connect wallet
          </button>
        ) : (
          <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginTop: 8 }}>
            <button className="btn btn-primary" disabled={!!busy || !configured} onClick={pulse}>
              {busy ?? "incrementFlashblock"}
            </button>
            {!isZero(addresses.agent) && (
              <button
                className="btn btn-outline"
                disabled={!!busy}
                onClick={async () => {
                  if (!signer) return;
                  setBusy("creditSurplus…");
                  try {
                    const hash = await creditSurplus(signer.owner, signer.wc);
                    toast.ok("Relayer credited surplus to LPs", explorerTx(hash));
                    await refresh();
                  } catch (e) {
                    toast.err((e as Error).message.slice(0, 160));
                  } finally {
                    setBusy(null);
                  }
                }}
              >
                {busy === "creditSurplus…" ? busy : "creditSurplus"}
              </button>
            )}
            {isLocal && (
              <button className="btn btn-outline" disabled={!!busy} onClick={() => advance(1)}>
                Mine 1 block
              </button>
            )}
          </div>
        )}
      </section>

      <section className="card card-lg">
        <div className="card-head">
          <h2>Lifecycle</h2>
        </div>
        <ol className="steps">
          <li>
            TEE heartbeat or EIP-712 Protect receipt marks the swap private.
          </li>
          <li>
            Private: 5 bps. Public: 1% + tax donated to LPs (
            <code style={{ fontFamily: "var(--font-mono)" }}>totalPublicTaxDonated</code>).
          </li>
          <li>
            Relayer <b>creditSurplus</b> donates Protect surplus into the pool.
          </li>
          <li>
            <code style={{ fontFamily: "var(--font-mono)" }}>SwapClassified</code>{" "}
            sets <code style={{ fontFamily: "var(--font-mono)" }}>attested = privatePath</code>{" "}
            on the tape.
          </li>
        </ol>
      </section>
    </div>
  );
}
