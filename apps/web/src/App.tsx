import { useState } from "react";
import {
  BrowserProvider,
  Contract,
  formatEther,
  parseEther,
} from "ethers";
import "./App.css";

declare global {
  interface Window {
    ethereum?: {
      request: (args: {
        method: string;
        params?: unknown[];
      }) => Promise<unknown>;
      on?: (event: string, listener: (...args: unknown[]) => void) => void;
    };
  }
}

const CONTRACT_ADDRESS = import.meta.env.VITE_CONTRACT_ADDRESS as string;
const CHAIN_ID = "0x279f";
const RPC_URL = "https://testnet-rpc.monad.xyz";
const EXPLORER = "https://testnet.monadexplorer.com";

const ABI = [
  "function createStream(address employee,uint64 duration) payable returns (uint256)",
  "function claimable(uint256 streamId) view returns (uint256)",
  "function accrued(uint256 streamId) view returns (uint256)",
  "function nextStreamId() view returns (uint256)",
  "function streams(uint256) view returns (address employer,address employee,uint256 deposited,uint256 withdrawn,uint64 startTime,uint64 endTime,uint64 cancelledAt,bool cancelled)",
  "function withdraw(uint256 streamId)",
  "function cancel(uint256 streamId)",
  "event StreamCreated(uint256 indexed streamId,address indexed employer,address indexed employee,uint256 amount,uint64 startTime,uint64 endTime)",
];

type StreamInfo = {
  employer: string;
  employee: string;
  deposited: bigint;
  withdrawn: bigint;
  startTime: bigint;
  endTime: bigint;
  cancelledAt: bigint;
  cancelled: boolean;
};

function App() {
  const [account, setAccount] = useState("");
  const [role, setRole] = useState<"employer" | "employee">("employer");
  const [employee, setEmployee] = useState("");
  const [amount, setAmount] = useState("0.1");
  const [duration, setDuration] = useState("3600");
  const [streamId, setStreamId] = useState("1");
  const [stream, setStream] = useState<StreamInfo | null>(null);
  const [claimable, setClaimable] = useState("0");
  const [status, setStatus] = useState("Connect a wallet to begin.");
  const [busy, setBusy] = useState(false);
  const [txHash, setTxHash] = useState("");

  async function connect() {
    if (!window.ethereum) {
      setStatus("Install or open MetaMask first.");
      return;
    }

    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: CHAIN_ID }],
      });
    } catch (error) {
      const e = error as { code?: number };
      if (e.code !== 4902) {
        setStatus("Switch MetaMask to Monad Testnet and try again.");
        return;
      }

      try {
        await window.ethereum.request({
          method: "wallet_addEthereumChain",
          params: [{
            chainId: CHAIN_ID,
            chainName: "Monad Testnet",
            nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
            rpcUrls: [RPC_URL],
            blockExplorerUrls: [EXPLORER],
          }],
        });
      } catch {
        setStatus("Network addition was cancelled or failed.");
        return;
      }
    }

    try {
      const provider = new BrowserProvider(window.ethereum);
      const signer = await provider.getSigner();
      setAccount(await signer.getAddress());
      setStatus("Wallet connected. Verify the selected role and account.");
    } catch {
      setStatus("Wallet connection failed.");
    }
  }

  async function getContract(write = false) {
    if (!window.ethereum) throw new Error("MetaMask is not available.");
    if (!CONTRACT_ADDRESS) throw new Error("Contract address is not configured.");

    const provider = new BrowserProvider(window.ethereum);
    const network = await provider.getNetwork();

    if (network.chainId !== 10143n) {
      throw new Error("Switch MetaMask to Monad Testnet.");
    }

    const signer = write ? await provider.getSigner() : provider;
    return new Contract(CONTRACT_ADDRESS, ABI, signer);
  }

  async function createStream() {
    setBusy(true);
    setTxHash("");

    try {
      if (!employee.match(/^0x[a-fA-F0-9]{40}$/)) {
        throw new Error("Enter a valid employee wallet address.");
      }
      if (Number(amount) <= 0 || !Number.isFinite(Number(amount))) {
        throw new Error("Amount must be greater than zero.");
      }
      if (!Number.isSafeInteger(Number(duration)) || Number(duration) <= 0) {
        throw new Error("Duration must be a positive number of seconds.");
      }

      const contract = await getContract(true);
      setStatus("Confirm stream funding in MetaMask…");

      const tx = await contract.createStream(
        employee,
        Number(duration),
        { value: parseEther(amount) }
      );

      setTxHash(tx.hash);
      setStatus("Transaction submitted. Waiting for confirmation…");
      const receipt = await tx.wait();

      if (!receipt || receipt.status !== 1) {
        throw new Error("Stream transaction failed.");
      }

      const iface = contract.interface;
      let createdId = "";

      for (const log of receipt.logs) {
        try {
          const parsed = iface.parseLog(log);
          if (parsed?.name === "StreamCreated") {
            createdId = parsed.args.streamId.toString();
            break;
          }
        } catch {
          // Ignore logs emitted by other contracts.
        }
      }

      if (createdId) setStreamId(createdId);
      setStatus(
        `Stream created successfully${createdId ? ` — ID ${createdId}` : ""}.`
      );
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Transaction failed.");
    } finally {
      setBusy(false);
    }
  }

  async function loadStream() {
    setBusy(true);

    try {
      const contract = await getContract();
      const id = BigInt(streamId);

      if (id <= 0n || id >= BigInt(await contract.nextStreamId())) {
        throw new Error("That stream ID does not exist.");
      }

      const s = await contract.streams(id);
      const owed = await contract.claimable(id);

      setStream({
        employer: s.employer,
        employee: s.employee,
        deposited: s.deposited,
        withdrawn: s.withdrawn,
        startTime: s.startTime,
        endTime: s.endTime,
        cancelledAt: s.cancelledAt,
        cancelled: s.cancelled,
      });
      setClaimable(formatEther(owed));
      setStatus("Stream data loaded from Monad Testnet.");
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Could not load stream.");
    } finally {
      setBusy(false);
    }
  }

  async function withdraw() {
    setBusy(true);
    setTxHash("");

    try {
      const contract = await getContract(true);
      setStatus("Confirm withdrawal in MetaMask…");

      const tx = await contract.withdraw(BigInt(streamId));
      setTxHash(tx.hash);
      setStatus("Withdrawal submitted. Waiting for confirmation…");

      const receipt = await tx.wait();
      if (!receipt || receipt.status !== 1) {
        throw new Error("Withdrawal transaction failed.");
      }

      setStatus("Withdrawal confirmed on-chain.");
      await loadStream();
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Withdrawal failed.");
    } finally {
      setBusy(false);
    }
  }

  async function cancelStream() {
    setBusy(true);
    setTxHash("");

    try {
      const contract = await getContract(true);
      setStatus("Confirm cancellation in MetaMask…");

      const tx = await contract.cancel(BigInt(streamId));
      setTxHash(tx.hash);

      const receipt = await tx.wait();
      if (!receipt || receipt.status !== 1) {
        throw new Error("Cancellation transaction failed.");
      }

      setStatus("Stream cancelled. Accrued salary remains claimable.");
      await loadStream();
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Cancellation failed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="app">
      <header className="topbar">
        <div className="brand"><span className="pulse">P</span> PulsePay</div>
        <div className="network">● Monad Testnet</div>
      </header>

      <section className="hero">
        <p className="eyebrow">SALARY, IN REAL TIME</p>
        <h1>Work happens daily.<br />Why shouldn't pay?</h1>
        <p className="muted">
          Create transparent salary streams and claim earned MON whenever you need it.
        </p>
        <button onClick={connect} disabled={busy}>
          {account
            ? `${account.slice(0, 6)}…${account.slice(-4)}`
            : "Connect MetaMask"}
        </button>
      </section>

      <section className="role-switch">
        <button
          className={role === "employer" ? "selected" : "secondary"}
          onClick={() => setRole("employer")}
        >
          Employer
        </button>
        <button
          className={role === "employee" ? "selected" : "secondary"}
          onClick={() => setRole("employee")}
        >
          Employee
        </button>
      </section>

      {role === "employer" ? (
        <section className="panel">
          <p className="eyebrow">EMPLOYER WORKSPACE</p>
          <h2>Start a salary stream</h2>
          <label>Employee wallet address</label>
          <input value={employee} onChange={e => setEmployee(e.target.value)}
            placeholder="0x…" />
          <div className="fields">
            <div>
              <label>Funding amount (MON)</label>
              <input type="number" min="0" step="0.01" value={amount}
                onChange={e => setAmount(e.target.value)} />
            </div>
            <div>
              <label>Duration (seconds)</label>
              <input type="number" min="1" value={duration}
                onChange={e => setDuration(e.target.value)} />
            </div>
          </div>
          <p className="muted">
            Salary accrues on-chain over the selected duration. Funding is held
            by the contract until earned or refunded.
          </p>
          <button disabled={busy || !account || role !== "employer"}
            onClick={createStream}>
            {busy ? "Please wait…" : "Fund & create stream"}
          </button>
        </section>
      ) : (
        <section className="panel">
          <p className="eyebrow">EMPLOYEE WORKSPACE</p>
          <h2>Your earned salary</h2>
          <label>Stream ID</label>
          <div className="inline-fields">
            <input value={streamId} onChange={e => setStreamId(e.target.value)}
              type="number" min="1" />
            <button className="secondary" disabled={busy} onClick={loadStream}>
              Load
            </button>
          </div>

          {stream && (
            <>
              <div className="balance">
                <span>Currently claimable</span>
                <strong>{claimable} MON</strong>
              </div>
              <div className="details">
                <p><span>Employer</span><code>{stream.employer}</code></p>
                <p><span>Employee</span><code>{stream.employee}</code></p>
                <p><span>Originally funded</span><b>{formatEther(stream.deposited)} MON</b></p>
                <p><span>Already withdrawn</span><b>{formatEther(stream.withdrawn)} MON</b></p>
                <p><span>Stream status</span><b>{stream.cancelled ? "Cancelled" : "Active or completed"}</b></p>
              </div>
              <button disabled={busy || !account || Number(claimable) <= 0}
                onClick={withdraw}>
                {busy ? "Please wait…" : "Withdraw earned salary"}
              </button>
            </>
          )}
        </section>
      )}

      {role === "employer" && (
        <section className="panel">
          <h2>Manage an existing stream</h2>
          <label>Stream ID</label>
          <div className="inline-fields">
            <input type="number" min="1" value={streamId}
              onChange={e => setStreamId(e.target.value)} />
            <button className="danger" disabled={busy || !account}
              onClick={cancelStream}>Cancel stream</button>
          </div>
          <p className="muted">Only the employer who created the stream can cancel it.</p>
        </section>
      )}

      <section className="status">
        <strong>Activity status</strong>
        <p>{status}</p>
        {txHash && (
          <a href={`${EXPLORER}/tx/${txHash}`} target="_blank" rel="noreferrer">
            View transaction on explorer ↗
          </a>
        )}
      </section>

      <footer>
        <span>PulsePay · Experimental testnet application</span>
        <a href={`${EXPLORER}/address/${CONTRACT_ADDRESS}`}
          target="_blank" rel="noreferrer">Contract explorer ↗</a>
      </footer>
    </main>
  );
}

export default App;
