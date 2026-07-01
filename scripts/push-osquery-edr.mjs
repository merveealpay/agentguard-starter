// Bring-your-own-EDR with osquery (open-source, Linux Foundation).
// Reads the newest gateway tool_call (host + upstream_pid), captures the REAL OS process behind it
// with osquery, and pushes it to AgentGuard's /api/edr/ingest. The correlation engine then links the
// osquery event to the tool_call by pid_lineage — real EDR telemetry → real correlation.
//
// Usage: with your agent connected through the gateway, make a tool call, then (within ~60s):
//   BASE=http://localhost:3000 node scripts/push-osquery-edr.mjs
// Needs: NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, AGENTGUARD_INGEST_TOKEN exported
// (same values as your .env), and osqueryi on PATH.
import { execFileSync } from "node:child_process";

const base = process.env.BASE || "http://localhost:3000";
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const token = process.env.AGENTGUARD_INGEST_TOKEN;
if (!url || !key || !token) {
  throw new Error("set NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, AGENTGUARD_INGEST_TOKEN");
}

// Newest gateway tool call with a pid — host + upstream_pid are the correlation anchors.
const r = await fetch(
  `${url}/rest/v1/tool_calls?source=eq.gateway&upstream_pid=not.is.null&order=ts.desc&limit=1&select=host,upstream_pid,tool,ts`,
  { headers: { apikey: key, authorization: `Bearer ${key}` } },
);
const [call] = await r.json();
if (!call) throw new Error("no gateway tool_calls with an upstream_pid — make a tool call through the gateway first");

// Capture the REAL process by pid via osquery.
const osqueryi = process.env.OSQUERYI || "osqueryi";
const sql = `SELECT pid, parent, name, path, cmdline FROM processes WHERE pid = ${Number(call.upstream_pid)};`;
let proc;
try {
  proc = JSON.parse(execFileSync(osqueryi, ["--json", sql], { encoding: "utf8" }))[0];
} catch (e) {
  throw new Error(`osquery failed (${osqueryi}): ${e.message}`);
}
if (!proc) {
  throw new Error(`osquery found no live process with pid ${call.upstream_pid} — push while your agent session (and its MCP server process) is still alive`);
}

const event = {
  // Align to the call's moment: the process was spawned at the call; osquery polls the `processes`
  // table afterwards, so use the call ts as the OS-effect time (lands it in the 5s correlation window).
  ts: call.ts,
  source: "osquery",
  host: call.host,
  category: "process",
  pid: Number(proc.pid),
  ppid: Number(proc.parent),
  processName: proc.name,
  processPath: proc.path,
  cmdline: proc.cmdline,
  ruleDesc: "process observed by osquery",
  externalId: `osquery-${proc.pid}-${Date.now()}`,
};

const res = await fetch(`${base}/api/edr/ingest`, {
  method: "POST",
  headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
  body: JSON.stringify({ events: [event] }),
});
console.log(`anchor call: ${call.tool} host=${call.host} pid=${call.upstream_pid}`);
console.log(`osquery captured: pid=${proc.pid} name=${proc.name} cmd=${(proc.cmdline || "").slice(0, 60)}`);
console.log(`ingest ${res.status}: ${await res.text()}`);
