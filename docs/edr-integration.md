# Connect your EDR to AgentGuard

AgentGuard sees what your agent *asked* to do at the MCP layer; your EDR sees what the OS
*actually did*. This guide connects the two so every tool call gets its OS-level ground truth —
and OS activity with **no** matching tool call surfaces as a possible gateway bypass.

Prerequisites: the control plane and gateway from the [starter README](../README.md) (steps 1–2)
are running, and your gateway sets `AGENTGUARD_HOST` to the hostname your EDR reports.

## How correlation works

Per OS event, against tool calls on the **same host** within `call.ts − 1s … + 5s`:

1. **`pid_lineage`** (confidence 0.9) — the event's `pid` is the tool call's upstream-server pid
   or a descendant.
2. **`host_net`** (0.7) — the event's `dstIp` appears in the call's arguments.
3. **`time_window`** (0.6 → 0.3, decaying) — fallback when no pid/IP evidence exists.

Unmatched events are stored as **orphans** and rendered in the UNCORRELATED EDR panel.

## Path A — osquery (fastest; ~10 min; no EDR product required)

[osquery](https://osquery.io) exposes the OS as SQL tables; the kit's script captures the *real*
process behind a gateway call and pushes it through the same endpoint a commercial EDR would use.

```bash
# 0. Install osquery (macOS: brew install --cask osquery ; Linux: distro package)
# 1. Env (same values as your .env)
export NEXT_PUBLIC_SUPABASE_URL=https://<project>.supabase.co
export SUPABASE_SERVICE_ROLE_KEY=<service-role key>
export AGENTGUARD_INGEST_TOKEN=<your token>

# 2. With your agent connected through the gateway, make any tool call
#    (the wrapped MCP server stays alive at its pid for the whole session).

# 3. Within ~60s, capture that pid with osquery and push it:
BASE=http://localhost:3000 node scripts/push-osquery-edr.mjs
```

Expected response: `{"ingested":1,"correlated":1,"orphans":0,...}` — refresh the console and the
call shows an **EDR · 1 correlated OS effect** chip with the process path/cmdline osquery saw,
linked by `pid_lineage`. For continuous monitoring, scale the same idea with `osqueryd` scheduled
queries shipped to `/api/edr/ingest` by any log forwarder.

## Path B — CrowdStrike Falcon

Falcon detections reach AgentGuard through the push endpoint. Two common mechanisms:

1. **Falcon Fusion SOAR workflow** — trigger: *New detection*; action: *HTTP request* to
   `https://<your-instance>/api/edr/ingest` with the `Authorization: Bearer <token>` header and a
   body template mapping the fields below.
2. **A small poller** — [FalconPy](https://falconpy.io) or the Event Streams API pulling new
   detections every 15–30 s and POSTing the transform.

Field mapping (Falcon detection → AgentGuard event):

| AgentGuard field | Falcon source |
| --- | --- |
| `ts` | `behaviors[].timestamp` (the behavior time, **not** delivery time) |
| `host` | `device.hostname` — must match the gateway's `AGENTGUARD_HOST` |
| `category` | `"process"` (or `"network"` for network behaviors) |
| `pid` / `ppid` | `behaviors[].process_id_local` / parent process id |
| `processName` / `processPath` / `cmdline` | `behaviors[].filename` / `filepath` / `cmdline` |
| `ruleId` / `ruleDesc` / `ruleLevel` | `behaviors[].behavior_id` / `description` / severity |
| `mitre` | `behaviors[].tactic_id` + `technique_id` (e.g. `["TA0006","T1552"]`) |
| `externalId` | `detection_id` (dedupe key — safe to re-send) |
| `source` | `"crowdstrike"` |

Example POST body:

```json
{
  "events": [{
    "ts": "2026-07-01T12:00:03Z",
    "host": "build-01",
    "category": "process",
    "pid": 4242, "ppid": 4100,
    "processName": "curl",
    "cmdline": "curl http://169.254.169.254/latest/meta-data/iam/",
    "ruleDesc": "Credential access via cloud instance metadata",
    "mitre": ["T1552.005"],
    "source": "crowdstrike",
    "externalId": "ldt:abc123:456"
  }]
}
```

Forward in near-real-time: the endpoint correlates an event against tool calls from the **last
60 seconds** only (older events are stored and shown, but land as orphans).

## Path C — Wazuh (pull, no webhook needed)

If you already run Wazuh, the bridge worker polls your indexer directly — read-only credentials,
nothing new on your endpoints:

```bash
AGENTGUARD_WAZUH_INDEXER_URL=https://<indexer>:9200 \
AGENTGUARD_WAZUH_INDEXER_USERNAME=<read-only user> \
AGENTGUARD_WAZUH_INDEXER_PASSWORD=<password> \
NEXT_PUBLIC_SUPABASE_URL=https://<project>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=<service-role key> \
npx agentguard-edr-bridge
```

It normalizes auditd/syscheck/network alerts from `wazuh-alerts-*` and runs the same correlation
engine. Set the gateway's `AGENTGUARD_HOST` to the Wazuh **agent name** so hosts align.

## Path D — Microsoft Defender, SentinelOne, Elastic, Splunk, anything else

Same recipe as CrowdStrike: transform the vendor alert to the event schema below and POST it.
Put the transform wherever alerts already flow — a SOAR/workflow HTTP action, a
Logstash/Cribl/Vector pipeline stage, or a ~50-line serverless function on the vendor's webhook.

## Ingest API reference

`POST /api/edr/ingest` — `Authorization: Bearer <AGENTGUARD_INGEST_TOKEN>`,
`Content-Type: application/json`.

- Token unset on the server → `404` (endpoint disabled). Bad token → `401`. Per-token rate limit
  ~60 req/min → `429`. Max **500 events per request**.
- Body: `{ "events": [ … ] }`. Per event: **`ts` (ISO-8601) and `host` are required**; optional:
  `category` (`process` | `file` | `network` | `other`), `source`, `externalId` (dedupe key),
  `pid`, `ppid`, `processName`, `processPath`, `cmdline`, `filePath`, `fileOp`, `dstIp`,
  `dstPort`, `direction`, `ruleId`, `ruleLevel`, `ruleDesc`, `mitre[]`, `sessionId`, `raw{}`.
- Response: `{ "ingested": n, "correlated": n, "orphans": n, "skipped": n }` — `skipped` counts
  events that failed validation; duplicates of an already-stored `(source, externalId)` are
  dropped silently (they lower `ingested`), so re-sending a batch is always safe.

## Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| `correlated: 0`, event visible as orphan | `host` mismatch — set `AGENTGUARD_HOST` on the gateway to the EDR's hostname |
| Same, hosts match | Pushed too late — ingest only correlates against tool calls from the last 60 s |
| Same, pushed promptly | Event `ts` outside the ±5 s window — send the *behavior* timestamp, not delivery time |
| Links only at 0.3–0.6 confidence | Events carry no `pid`/`ppid` — enable process telemetry in the EDR policy |
| `404` from ingest | `AGENTGUARD_INGEST_TOKEN` not set on the dashboard |

## Security notes

- The gateway **fails safe** (deny/hold on errors); enforcement is deterministic and local.
- EDR integration is **read-only** toward your EDR and runs off the blocking path.
- Ingest payloads are treated as untrusted input; rotate the token by changing `.env` and
  `docker compose up -d`.

Stuck, or want a guided pilot? → [github.com/merveealpay](https://github.com/merveealpay)
