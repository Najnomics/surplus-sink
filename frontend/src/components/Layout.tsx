import { Suspense, useState } from "react";
import { NavLink, Outlet } from "react-router-dom";
import { addresses, chain, explorerTx, isDevKey, isLocal } from "../lib/clients";
import { useAppData } from "../context/AppData";
import { useToast } from "../context/Toast";
import { faucet } from "../lib/actions";
import { fmt, short } from "../lib/format";

const NAV = [
  { to: "/", label: "Pool", end: true },
  { to: "/swap", label: "Route" },
  { to: "/liquidity", label: "Depth" },
  { to: "/analytics", label: "Inflow" },
  { to: "/attestation", label: "Relayer" },
  { to: "/about", label: "Why" },
];

export function Layout() {
  return (
    <div className="lagoon-app">
      <div className="lagoon-wash" />
      <header className="lagoon-bar">
        <div className="lagoon-pill">
          <a className="lagoon-mark" href="/">
            Surplus Sink
          </a>
          <nav className="lagoon-nav">
            {NAV.map(({ to, label, end }) => (
              <NavLink key={to} to={to} end={end} className={({ isActive }) => (isActive ? "on" : "")}>
                {label}
              </NavLink>
            ))}
          </nav>
          <div className="lagoon-tools">
            <FaucetButton />
            <NetworkChip />
            <WalletChip />
          </div>
        </div>
      </header>
      <main className="content">
        <Suspense fallback={<div className="skel" style={{ height: 240 }} />}>
          <Outlet />
        </Suspense>
      </main>
      <footer className="lagoon-foot">
        Private path is cheap. Public path pays the pool.{" "}
        <a href={`https://sepolia.uniscan.xyz/address/${addresses.hook}`} target="_blank" rel="noreferrer">
          Uniscan
        </a>
      </footer>
    </div>
  );
}

function FaucetButton() {
  const { signer, refresh } = useAppData();
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  if (isLocal || !signer) return null;
  return (
    <button
      className="btn btn-ghost"
      disabled={busy}
      onClick={async () => {
        if (!signer) return;
        setBusy(true);
        try {
          const hash = await faucet(signer.owner, signer.wc);
          toast.ok("Minted 10,000 of each test token", explorerTx(hash));
          await refresh();
        } catch (e) {
          toast.err((e as Error).message.slice(0, 100));
        } finally {
          setBusy(false);
        }
      }}
    >
      {busy ? "Minting…" : "Faucet"}
    </button>
  );
}

function NetworkChip() {
  return (
    <span className="chip">
      <span className={`net-dot ${isLocal ? "local" : ""}`} />
      {isLocal ? "Anvil" : chain.name}
    </span>
  );
}

function WalletChip() {
  const { signer, balances, connect, disconnect, needsConnect } = useAppData();
  if (needsConnect) {
    return (
      <button className="btn btn-primary" onClick={connect}>
        Connect wallet
      </button>
    );
  }
  return (
    <span className="chip wallet-chip" onClick={isLocal || isDevKey ? undefined : disconnect}>
      {short(signer?.owner)}
      {balances && (
        <span className="bals">
          {fmt(balances.token0, 2)} {String(addresses.token0Symbol)}
        </span>
      )}
    </span>
  );
}
