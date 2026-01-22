import http from "http";
import { WebSocketServer } from "ws";
import { v4 as uuidv4 } from "uuid";

const PORT = Number(process.env.PORT || 45444);
const HOST = process.env.HOST || "127.0.0.1";
const WS_PATH = process.env.WS_PATH || "/ws/sendReq";

const ackTimeoutMs = Number(process.env.ACK_TIMEOUT_MS || 3000);
const serverRetryBackoffMs = (process.env.SERVER_RETRY_BACKOFF_MS || "250,500,1000,2000,4000")
  .split(",")
  .map((x) => Number(x.trim()))
  .filter((x) => Number.isFinite(x) && x > 0);

// connections
/** @type {Set<import('ws').WebSocket>} */
const allSockets = new Set();
/** eqid -> Set(ws) */
const appSocketsByEqid = new Map();
/** pcId -> ws */
const pcSocketById = new Map();
/** ws -> { clientType, eqid?, pcId? } */
const clientInfoByWs = new WeakMap();

// pairing
/** pairingCode -> pcId */
const pairingCodeToPcId = new Map();
/** eqid -> Map(pcId -> { enabled: boolean }) */
const pairingsByEqid = new Map();

// jobs
/** jobId -> { eqid, kind, barcode, createdAt, targets: Map<pcId, TargetState> } */
const jobs = new Map();
/** outstanding ack waits: key(jobId|pcId|attempt) -> timeoutId */
const pendingAcks = new Map();

function nowIso() {
  return new Date().toISOString();
}

function safeJsonParse(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function sendJson(ws, obj) {
  if (ws.readyState !== ws.OPEN) return false;
  try {
    ws.send(JSON.stringify(obj));
    return true;
  } catch {
    return false;
  }
}

function sendResponse(ws, requestId, ok, data, error) {
  return sendJson(ws, {
    type: "response",
    requestId: requestId || null,
    ok: !!ok,
    error: ok ? undefined : (error || { code: "ERR", message: "unknown" }),
    data: ok ? data : undefined,
    timestamp: nowIso()
  });
}

function broadcastToEqid(eqid, event, data) {
  const set = appSocketsByEqid.get(eqid);
  if (!set) return;
  for (const ws of set) {
    sendJson(ws, { type: "event", event, data, timestamp: nowIso() });
  }
}

function genPairingCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

function ensureEqidPairings(eqid) {
  let m = pairingsByEqid.get(eqid);
  if (!m) {
    m = new Map();
    pairingsByEqid.set(eqid, m);
  }
  return m;
}

function getBackoff(attemptIdx) {
  return serverRetryBackoffMs[Math.min(attemptIdx, serverRetryBackoffMs.length - 1)] || 1000;
}

function targetSnapshot(job) {
  const targets = [];
  for (const [pcId, t] of job.targets.entries()) {
    targets.push({
      pcId,
      status: t.status,
      attempt: t.attempt,
      updatedAt: t.updatedAt,
      error: t.error || undefined
    });
  }
  return targets;
}

function makeJob(eqid, barcode) {
  const jobId = uuidv4();
  const job = {
    jobId,
    eqid,
    kind: "barcode",
    barcode,
    createdAt: nowIso(),
    updatedAt: nowIso(),
    targets: new Map()
  };
  jobs.set(jobId, job);
  return job;
}

function scheduleDeliver(job, pcId, serverAttempt) {
  const ws = pcSocketById.get(pcId);
  const key = `${job.jobId}|${pcId}|${serverAttempt}`;

  // if already waiting for this attempt, skip
  if (pendingAcks.has(key)) return;

  // mark status
  const t = job.targets.get(pcId) || { status: "pending", attempt: 0, updatedAt: nowIso(), error: null };
  t.status = "sent";
  t.attempt = serverAttempt;
  t.updatedAt = nowIso();
  t.error = null;
  job.targets.set(pcId, t);
  job.updatedAt = nowIso();

  const sent = ws ? sendJson(ws, {
    type: "event",
    event: "deliverBarcode",
    data: {
      jobId: job.jobId,
      attempt: serverAttempt,
      createdAt: job.createdAt,
      eqid: job.eqid,
      barcode: job.barcode,
      suffixKey: "Enter"
    },
    timestamp: nowIso()
  }) : false;

  // notify app about status change
  broadcastToEqid(job.eqid, "scanJobUpdate", {
    jobId: job.jobId,
    eqid: job.eqid,
    kind: job.kind,
    targets: targetSnapshot(job)
  });

  // if not connected, treat as timeout and retry later
  const timeout = setTimeout(() => {
    pendingAcks.delete(key);
    const cur = job.targets.get(pcId);
    if (!cur || cur.status === "ack_ok") return;

    if (serverAttempt >= 5) {
      cur.status = "ack_fail";
      cur.updatedAt = nowIso();
      cur.error = "ACK_TIMEOUT";
      job.updatedAt = nowIso();
      broadcastToEqid(job.eqid, "scanJobUpdate", {
        jobId: job.jobId,
        eqid: job.eqid,
        kind: job.kind,
        targets: targetSnapshot(job)
      });
      return;
    }

    const nextDelay = getBackoff(serverAttempt); // attempt 1 -> backoff[1] style
    setTimeout(() => scheduleDeliver(job, pcId, serverAttempt + 1), nextDelay);
  }, ackTimeoutMs);

  pendingAcks.set(key, timeout);

  // if we couldn't send because offline, don't wait full timeout before retrying
  if (!sent) {
    // shorten: schedule retry at backoff without blocking ackTimeout
    clearTimeout(timeout);
    pendingAcks.delete(key);
    if (serverAttempt < 5) {
      setTimeout(() => scheduleDeliver(job, pcId, serverAttempt + 1), getBackoff(serverAttempt - 1));
    } else {
      const cur = job.targets.get(pcId) || t;
      cur.status = "ack_fail";
      cur.updatedAt = nowIso();
      cur.error = "PC_OFFLINE";
      job.targets.set(pcId, cur);
      job.updatedAt = nowIso();
      broadcastToEqid(job.eqid, "scanJobUpdate", {
        jobId: job.jobId,
        eqid: job.eqid,
        kind: job.kind,
        targets: targetSnapshot(job)
      });
    }
  }
}

function handleDeliverAck(ws, msg) {
  const info = clientInfoByWs.get(ws);
  if (!info || info.clientType !== "pcAgent" || !info.pcId) return;

  const data = msg.data || {};
  const jobId = String(data.jobId || "");
  const attempt = Number(data.attempt || 0);
  const ok = !!data.ok;
  const pcId = String(data.pcId || info.pcId);

  const job = jobs.get(jobId);
  if (!job) return;

  const key = `${jobId}|${pcId}|${attempt}`;
  const to = pendingAcks.get(key);
  if (to) {
    clearTimeout(to);
    pendingAcks.delete(key);
  }

  const t = job.targets.get(pcId) || { status: "pending", attempt: attempt, updatedAt: nowIso(), error: null };
  t.status = ok ? "ack_ok" : "ack_fail";
  t.attempt = attempt;
  t.updatedAt = nowIso();
  t.error = ok ? null : (String(data.error || "AGENT_FAIL"));
  job.targets.set(pcId, t);
  job.updatedAt = nowIso();

  broadcastToEqid(job.eqid, "scanJobUpdate", {
    jobId: job.jobId,
    eqid: job.eqid,
    kind: job.kind,
    targets: targetSnapshot(job)
  });
}

function handleMessage(ws, msg) {
  const requestId = msg.requestId || null;
  const clientType = msg.clientType || null;

  if (typeof clientType === "string") {
    const existing = clientInfoByWs.get(ws) || {};
    clientInfoByWs.set(ws, { ...existing, clientType });
  }

  // app init (simple; client supplies eqid or we issue one)
  if (msg.type === "appInit") {
    const eqid = (msg.data && String(msg.data.eqid || "").trim()) || `EQ${Math.floor(1000 + Math.random() * 9000)}`;
    const existing = clientInfoByWs.get(ws) || {};
    clientInfoByWs.set(ws, { ...existing, clientType: "app", eqid });

    let set = appSocketsByEqid.get(eqid);
    if (!set) {
      set = new Set();
      appSocketsByEqid.set(eqid, set);
    }
    set.add(ws);

    return sendResponse(ws, requestId, true, { eqid, alias: "SCANNER" });
  }

  // pc agent hello
  if (msg.type === "pcAgentHello") {
    const data = msg.data || {};
    const group = String(data.group || "default").trim();
    const deviceName = String(data.deviceName || "pc").trim();
    const machineId = String(data.machineId || "").trim();
    const pcId = String(data.pcId || `${group}:${deviceName}:${machineId || uuidv4().slice(0, 8)}`);

    clientInfoByWs.set(ws, { clientType: "pcAgent", pcId });
    pcSocketById.set(pcId, ws);

    // issue pairing code per connection (regenerated on reconnect)
    const code = genPairingCode();
    pairingCodeToPcId.set(code, pcId);

    // eslint-disable-next-line no-console
    console.log(`[pcAgentHello] pcId=${pcId} pairingCode=${code}`);

    sendJson(ws, { type: "event", event: "pairingCode", data: { code, pcId }, timestamp: nowIso() });
    return sendResponse(ws, requestId, true, { pcId, pairingCode: code });
  }

  // pairing request from app
  if (msg.type === "pairRequest") {
    const data = msg.data || {};
    const eqid = String(data.eqid || "").trim();
    const code = String(data.code || "").trim();
    if (!eqid || !code) return sendResponse(ws, requestId, false, null, { code: "INVALID", message: "eqid/code required" });
    const pcId = pairingCodeToPcId.get(code);
    if (!pcId) return sendResponse(ws, requestId, false, null, { code: "NOT_FOUND", message: "invalid pairing code" });

    ensureEqidPairings(eqid).set(pcId, { enabled: true });
    broadcastToEqid(eqid, "paired", { eqid, pcId });

    const pcWs = pcSocketById.get(pcId);
    if (pcWs) sendJson(pcWs, { type: "event", event: "paired", data: { eqid }, timestamp: nowIso() });

    // eslint-disable-next-line no-console
    console.log(`[pairRequest] eqid=${eqid} pcId=${pcId}`);

    return sendResponse(ws, requestId, true, { eqid, pcId, enabled: true });
  }

  // list pairings
  if (msg.type === "pairList") {
    const data = msg.data || {};
    const eqid = String(data.eqid || "").trim();
    const m = ensureEqidPairings(eqid);
    const list = [];
    for (const [pcId, v] of m.entries()) list.push({ pcId, enabled: !!v.enabled, online: pcSocketById.has(pcId) });
    return sendResponse(ws, requestId, true, { eqid, list });
  }

  // enable/disable
  if (msg.type === "pairSetEnabled") {
    const data = msg.data || {};
    const eqid = String(data.eqid || "").trim();
    const pcId = String(data.pcId || "").trim();
    const enabled = !!data.enabled;
    if (!eqid || !pcId) return sendResponse(ws, requestId, false, null, { code: "INVALID", message: "eqid/pcId required" });
    ensureEqidPairings(eqid).set(pcId, { enabled });
    return sendResponse(ws, requestId, true, { eqid, pcId, enabled });
  }

  // scan barcode
  if (msg.type === "scanBarcode") {
    const data = msg.data || {};
    const eqid = String(data.eqid || "").trim();
    const barcode = String(data.barcode || "").trim();
    if (!eqid || !barcode) return sendResponse(ws, requestId, false, null, { code: "INVALID", message: "eqid/barcode required" });

    // register this ws as app for events
    const existing = clientInfoByWs.get(ws) || {};
    clientInfoByWs.set(ws, { ...existing, clientType: "app", eqid });
    let set = appSocketsByEqid.get(eqid);
    if (!set) {
      set = new Set();
      appSocketsByEqid.set(eqid, set);
    }
    set.add(ws);

    const job = makeJob(eqid, barcode);
    const pairings = ensureEqidPairings(eqid);
    const targets = [];
    for (const [pcId, v] of pairings.entries()) {
      if (!v.enabled) continue;
      targets.push(pcId);
      job.targets.set(pcId, { status: "pending", attempt: 0, updatedAt: nowIso(), error: null });
    }

    sendResponse(ws, requestId, true, { jobId: job.jobId, targets });

    // eslint-disable-next-line no-console
    console.log(`[scanBarcode] eqid=${eqid} jobId=${job.jobId} targets=${targets.length}`);

    // async deliver
    setTimeout(() => {
      for (const pcId of targets) scheduleDeliver(job, pcId, 1);
    }, 0);
    return;
  }

  // deliver ack
  if (msg.type === "deliverAck") {
    handleDeliverAck(ws, msg);
    // eslint-disable-next-line no-console
    console.log(`[deliverAck] jobId=${msg?.data?.jobId} pcId=${msg?.data?.pcId} attempt=${msg?.data?.attempt} ok=${msg?.data?.ok}`);
    return sendResponse(ws, requestId, true, { received: true });
  }

  // ping/pong
  if (msg.type === "ping") {
    return sendResponse(ws, requestId, true, { pong: true });
  }

  return sendResponse(ws, requestId, false, null, { code: "UNKNOWN", message: "unknown message type" });
}

const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true, ts: nowIso() }));
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ server, path: WS_PATH });

wss.on("connection", (ws) => {
  allSockets.add(ws);
  clientInfoByWs.set(ws, { clientType: "unknown" });

  ws.on("message", (data) => {
    const text = data.toString("utf8");
    const msg = safeJsonParse(text);
    if (!msg) {
      sendResponse(ws, null, false, null, { code: "BAD_JSON", message: "invalid json" });
      return;
    }
    handleMessage(ws, msg);
  });

  ws.on("close", () => {
    allSockets.delete(ws);
    const info = clientInfoByWs.get(ws);
    if (info?.eqid) {
      const set = appSocketsByEqid.get(info.eqid);
      if (set) {
        set.delete(ws);
        if (set.size === 0) appSocketsByEqid.delete(info.eqid);
      }
    }
    if (info?.pcId) {
      const cur = pcSocketById.get(info.pcId);
      if (cur === ws) pcSocketById.delete(info.pcId);
    }
  });
});

server.listen(PORT, HOST, () => {
  // eslint-disable-next-line no-console
  console.log(`uniscan-be-ws listening on ws://${HOST}:${PORT}${WS_PATH}`);
});

