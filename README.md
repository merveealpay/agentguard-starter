# AgentGuard Starter

**Run [AgentGuard](https://dashboard-steel-two-88.vercel.app/demo) — a self-hosted firewall for AI
agents — in your own environment in ~20 minutes.** This kit is everything you need, no source
access required:

- the **dashboard** as a Docker image (`ghcr.io/merveealpay/agentguard-dashboard`)
- the **gateway** on npm (`npx agentguard`)
- the **Wazuh correlation worker** on npm (`npx agentguard-edr-bridge`)
- database **migrations**, a **sample policy**, the **osquery demo script**, and the
  step-by-step **EDR integration guide**

```
Your agent (Claude Desktop / Cursor)  ⇄  npx agentguard  ⇄  your MCP servers
                                             │  allow / deny / ask + audit
                                             ▼
Your EDR (osquery / CrowdStrike / Wazuh) ─▶ dashboard (this compose) ─▶ your Supabase
```

**See it first (nothing to install):** https://dashboard-steel-two-88.vercel.app/demo

## 1. Control plane (~10 min)

1. Create a free [Supabase](https://supabase.com) project and run each file in
   `supabase/migrations/` (in order, `0001` → `0007`) in the SQL editor.
2. Configure and start the dashboard:

   ```bash
   cp .env.example .env    # fill in the Supabase keys + a random AGENTGUARD_INGEST_TOKEN
   docker compose up -d
   ```

3. Open http://localhost:3000, create your account at `/signup`, sign in. You should see an
   empty live console. (Lock signups afterwards with `AGENTGUARD_DISABLE_SIGNUP=true`.)

## 2. Gateway in front of your agent (~5 min)

Wrap any MCP server with the gateway in your client's config. Claude Desktop
(`claude_desktop_config.json`):

```jsonc
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y", "agentguard",
        "--policy", "/path/to/starter/policies/filesystem-agent.json",
        "--name", "filesystem",
        "--", "npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"
      ],
      "env": {
        "NEXT_PUBLIC_SUPABASE_URL": "https://<project>.supabase.co",
        "SUPABASE_SERVICE_ROLE_KEY": "<service-role key>",
        "AGENTGUARD_HOST": "my-workstation"
      }
    }
  }
}
```

Restart the client and make any tool call — it appears in the live feed with a **GATEWAY** badge;
calls matching an `ask` rule wait in the approval queue until you click Approve/Deny. Without
`--policy`, a conservative built-in applies (deny destructive shell + credential leaks).

## 3. Connect your EDR (~10–30 min)

Follow **[docs/edr-integration.md](docs/edr-integration.md)** and pick your path:

| Path | For | Mechanism |
| --- | --- | --- |
| **osquery** | fastest PoC, no EDR product | `scripts/push-osquery-edr.mjs` → push endpoint |
| **CrowdStrike Falcon** | Falcon shops | Fusion SOAR webhook or FalconPy poller → push endpoint |
| **Wazuh** | Wazuh shops | `npx agentguard-edr-bridge` polls your indexer (read-only) |
| **Anything else** | Defender, SentinelOne, Elastic, Splunk… | transform + POST to `/api/edr/ingest` |

Correlated OS events appear as **EDR chips** under the tool calls that caused them; OS activity
with no matching call lands in the **UNCORRELATED EDR** panel — possible gateway bypass.

## Security model (short version)

- Enforcement is **deterministic and local** in the gateway; fail-safe to deny/hold. No LLM on the
  blocking path (the AI risk panel is advisory).
- The EDR integration is **read-only** toward your EDR and off the blocking path.
- Everything runs on **your** infrastructure: your Supabase, your Docker host, your keys. On-prem
  AI (Ollama) keeps tool args entirely on your machines.

## Getting help

Questions, or want a guided pilot? → [github.com/merveealpay](https://github.com/merveealpay)

## License

Free to run to evaluate AgentGuard and govern your own agents — see [LICENSE](LICENSE).
The AgentGuard source code is not publicly available; this kit ships configuration, SQL, and
prebuilt artifacts only.
