import { addresses, chain, isZero } from "../lib/clients";
import { short } from "../lib/format";

export function AboutPage() {
  return (
    <div className="grid cols-2" style={{ alignItems: "start" }}>
      <section className="card card-lg">
        <div className="prose">
          <h2 style={{ marginTop: 0 }}>The idea</h2>
          <p>
            Private flow should be cheap. Public flow should pay for the damage
            it does. <b>Surplus Sink</b> is a Uniswap v4 hook with two private
            ingresses and one LP sink: TEE / Flashtestation heartbeat (
            <code>policy.isFair</code>) and an <b>EIP-712 receipt</b> from an
            owner-set Protect / MEV-Share relayer. The relayer{" "}
            <code>creditSurplus</code> donates real tokens to LPs.
          </p>
          <p>
            <b>PRIVATE</b> path: <b>5 bps</b>, no public tax. <b>PUBLIC</b>{" "}
            path: <b>1% + 50 bps</b> recapture. Recapture charts read{" "}
            <code>totalPublicTaxDonated</code>; surplus is a separate donate.
          </p>
          <p>
            The live pool is Unichain Sepolia{" "}
            <b>
              {addresses.token0Symbol} / {addresses.token1Symbol}
            </b>{" "}
            (18-decimal mocks for this hook only).
          </p>

          <h3>Mechanism</h3>
          <ul>
            <li>
              Empty <code>hookData</code> is private when the oracle says the
              block is fair.
            </li>
            <li>
              Otherwise <code>hookData</code> is an EIP-712 Protect receipt
              bound to this pool.
            </li>
            <li>
              Public swaps emit <code>SwapClassified</code> with{" "}
              <code>privatePath=false</code> and the tax amount.
            </li>
            <li>
              Relayer <code>creditSurplus</code> unlocks and donates into the
              pool.
            </li>
          </ul>
          <h3>Agents</h3>
          <p>
            The Protect / MEV-Share relayer is the agent. It signs EIP-712
            receipts and calls <code>creditSurplus</code>. TEE-attested private
            flow also has to pulse and swap in the same block —{" "}
            <code>SinkAgent</code> does both on Unichain Sepolia.
          </p>
        </div>
      </section>

      <section className="grid" style={{ gap: 18 }}>
        <div className="card">
          <div className="card-head">
            <h3>Deployment</h3>
            <span className="muted">{chain.name}</span>
          </div>
          <table className="maptable">
            <tbody>
              <tr>
                <td>Hook</td>
                <td className="mono">{short(addresses.hook)}</td>
              </tr>
              <tr>
                <td>Oracle / policy</td>
                <td className="mono">{short(addresses.policy)}</td>
              </tr>
              <tr>
                <td>Relayer</td>
                <td className="mono">
                  {isZero(addresses.relayer) ? "—" : short(addresses.relayer)}
                </td>
              </tr>
              <tr>
                <td>Swap router</td>
                <td className="mono">{short(addresses.swapRouter)}</td>
              </tr>
              <tr>
                <td>StateView</td>
                <td className="mono">{short(addresses.stateView)}</td>
              </tr>
              <tr>
                <td>PositionManager</td>
                <td className="mono">{short(addresses.positionManager)}</td>
              </tr>
              <tr>
                <td>
                  {addresses.token0Symbol} / {addresses.token1Symbol}
                </td>
                <td className="mono">
                  {short(addresses.token0)} · {short(addresses.token1)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div className="card">
          <div className="card-head">
            <h3>Fee schedule</h3>
          </div>
          <table className="maptable">
            <tbody>
              <tr>
                <td>Private (TEE / receipt)</td>
                <td>
                  <b>0.05%</b> · no public tax
                </td>
              </tr>
              <tr>
                <td>Public mempool</td>
                <td>
                  <b>1.00%</b> + <b>0.50%</b> tax → LPs
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
