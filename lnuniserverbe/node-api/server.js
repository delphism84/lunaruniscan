import express from 'express';
import http from 'http';
import { Server as SocketIOServer } from 'socket.io';
import cors from 'cors';
import morgan from 'morgan';
import multer from 'multer';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import dayjs from 'dayjs';
import { v4 as uuidv4 } from 'uuid';
import { WebSocketServer } from 'ws';
import crypto from 'crypto';
import { MongoClient, ObjectId } from 'mongodb';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const server = http.createServer(app);
const io = new SocketIOServer(server, {
  path: '/scannerhub',
  cors: {
    origin: ['http://127.0.0.1:58000', 'http://localhost:58000'],
    credentials: true
  }
});

// configuration
// Default to 45444 to match existing app/pc-agent configs.
const PORT = Number(process.env.PORT || 45444);
const HOST = process.env.HOST || '0.0.0.0';
const WS_PATH = process.env.WS_PATH || '/ws/sendReq';

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017';
const MONGO_DB = process.env.MONGO_DB || 'uniscan';

// dispatcher integration (history-key -> dispatch trigger)
const DISPATCHER_URL = process.env.DISPATCHER_URL || 'http://127.0.0.1:50210/enqueue';
// internal endpoint for dispatcher -> node-api
const INTERNAL_TOKEN = process.env.INTERNAL_TOKEN || '';

// middlewares
app.use(cors({
  origin: ['http://127.0.0.1:58000', 'http://localhost:58000'],
  credentials: true
}));
app.use(morgan('combined'));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// static files exposure (optional)
const filesRoot = path.join(__dirname, 'files');
if (!fs.existsSync(filesRoot)) {
  fs.mkdirSync(filesRoot, { recursive: true });
}
app.use('/files', express.static(filesRoot));

// ---------------------------
// WS-only protocol (be-ws compatible) + Mongo persistence
// ---------------------------

/** @type {MongoClient | null} */
let mongoClient = null;
/** @type {import('mongodb').Db | null} */
let db = null;

function nowIso() {
  return new Date().toISOString();
}

function genEqid6() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let s = '';
  for (let i = 0; i < 6; i++) s += chars[Math.floor(Math.random() * chars.length)];
  return s;
}

function safeJsonParse(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function sendJson(ws, obj) {
  if (!ws || ws.readyState !== ws.OPEN) return false;
  try {
    ws.send(JSON.stringify(obj));
    return true;
  } catch {
    return false;
  }
}

function sendResponse(ws, requestId, ok, data, error) {
  return sendJson(ws, {
    type: 'response',
    requestId: requestId || null,
    ok: !!ok,
    error: ok ? undefined : (error || { code: 'ERR', message: 'unknown' }),
    data: ok ? data : undefined,
    timestamp: nowIso()
  });
}

// connections (in-memory)
/** @type {Set<import('ws').WebSocket>} */
const allSockets = new Set();
/** eqid -> Set(ws) */
const appSocketsByEqid = new Map();
/** pcId -> ws */
const pcSocketById = new Map();
/** ws -> { clientType, eqid?, pcId? } */
const clientInfoByWs = new WeakMap();

// pairing (ephemeral code/pin issuance, persisted link is in Mongo `pairings`)
/** pairingCode -> pcId */
const pairingCodeToPcId = new Map();
/** pairingCode -> { pin: string, expiresAtMs: number, failCount: number } */
const pairingMetaByCode = new Map();
/** pcId -> pairingCode */
const pairingCodeByPcId = new Map();

function nowMs() {
  return Date.now();
}

function genPairingCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}
function genPin4() {
  return String(Math.floor(1000 + Math.random() * 9000));
}
function getPairingMeta(code) {
  const m = pairingMetaByCode.get(code);
  if (!m) return null;
  if (m.expiresAtMs <= nowMs()) {
    pairingMetaByCode.delete(code);
    pairingCodeToPcId.delete(code);
    for (const [pcId, curCode] of pairingCodeByPcId.entries()) {
      if (curCode === code) pairingCodeByPcId.delete(pcId);
    }
    return null;
  }
  return m;
}
function invalidatePairingCode(code) {
  if (!code) return;
  pairingMetaByCode.delete(code);
  pairingCodeToPcId.delete(code);
}
function issuePairing(ws, pcId) {
  const ttlMs = Number(process.env.PAIR_TTL_MS || 5 * 60 * 1000);
  const prev = pairingCodeByPcId.get(pcId);
  if (prev) invalidatePairingCode(prev);
  let code = genPairingCode();
  for (let i = 0; i < 10 && pairingCodeToPcId.has(code); i++) code = genPairingCode();
  const pin = genPin4();
  pairingCodeByPcId.set(pcId, code);
  pairingCodeToPcId.set(code, pcId);
  pairingMetaByCode.set(code, { pin, expiresAtMs: nowMs() + ttlMs, failCount: 0 });
  sendJson(ws, {
    type: 'event',
    event: 'pairingCode',
    data: { code, pin, pcId, expiresAt: new Date(nowMs() + ttlMs).toISOString() },
    timestamp: nowIso()
  });
  return { code, pin, ttlMs };
}

function registerAppSocket(eqid, ws) {
  let set = appSocketsByEqid.get(eqid);
  if (!set) {
    set = new Set();
    appSocketsByEqid.set(eqid, set);
  }
  set.add(ws);
}

function broadcastToEqid(eqid, event, data) {
  const set = appSocketsByEqid.get(eqid);
  if (!set) return;
  for (const ws of set) sendJson(ws, { type: 'event', event, data, timestamp: nowIso() });
}

function hashPcId(group, deviceName, machineId) {
  // deterministic-ish key for same device; keep readable and compatible with existing pc-agent config.
  const raw = `${group}:${deviceName}:${machineId}`.trim();
  if (!raw || raw === '::') return `default:PC:${uuidv4().slice(0, 8)}`;
  // keep old format from be-ws for compatibility
  return raw;
}

async function ensureMongo() {
  if (db) return db;
  mongoClient = new MongoClient(MONGO_URI);
  await mongoClient.connect();
  db = mongoClient.db(MONGO_DB);

  // indexes (best-effort)
  try {
    await db.collection('pairings').createIndex({ eqid: 1, pcId: 1 }, { unique: true });
  } catch { }
  try {
    await db.collection('scanDeliveries').createIndex({ scanId: 1 });
    await db.collection('scanDeliveries').createIndex({ status: 1, lockUntil: 1 });
    await db.collection('scanDeliveries').createIndex({ pcId: 1, status: 1, updatedAt: -1 });
  } catch { }
  try {
    await db.collection('apps').createIndex({ eqid: 1 }, { unique: true });
  } catch { }
  try {
    await db.collection('pcDevices').createIndex({ pcId: 1 }, { unique: true });
  } catch { }

  return db;
}

async function getApp(eqid) {
  const d = await ensureMongo();
  return await d.collection('apps').findOne({ eqid });
}

async function upsertApp(eqid, alias) {
  const d = await ensureMongo();
  const now = new Date();
  await d.collection('apps').updateOne(
    { eqid },
    {
      $set: { alias: alias || 'SCANNER', updatedAt: now },
      $setOnInsert: { eqid, createdAt: now }
    },
    { upsert: true }
  );
  return await d.collection('apps').findOne({ eqid });
}

async function upsertPcDevice(pcId, group, deviceName, machineId, online) {
  const d = await ensureMongo();
  const now = new Date();
  await d.collection('pcDevices').updateOne(
    { pcId },
    {
      $set: {
        pcId,
        group,
        deviceName,
        machineId,
        online: !!online,
        lastSeenAt: now
      },
      $setOnInsert: { createdAt: now }
    },
    { upsert: true }
  );
}

async function setPairing(eqid, pcId, enabled) {
  const d = await ensureMongo();
  const now = new Date();
  await d.collection('pairings').updateOne(
    { eqid, pcId },
    {
      $set: { enabled: !!enabled, updatedAt: now },
      $setOnInsert: { eqid, pcId, createdAt: now }
    },
    { upsert: true }
  );
}

async function listPairings(eqid) {
  const d = await ensureMongo();
  return await d.collection('pairings').find({ eqid }).toArray();
}

async function insertScanDeliveries(scanId, eqid, barcode, targets) {
  const d = await ensureMongo();
  const now = new Date();
  const docs = targets.map((pcId) => ({
    scanId,
    eqid,
    pcId,
    kind: 'barcode',
    barcode,
    status: 'pending',
    serverAttempt: 0,
    lastSentAt: null,
    ackAt: null,
    ackOk: null,
    ackError: null,
    agentAttempt: null,
    inputMethod: null,
    durationMs: null,
    lockOwner: null,
    lockUntil: null,
    createdAt: now,
    updatedAt: now
  }));
  const res = await d.collection('scanDeliveries').insertMany(docs, { ordered: true });
  // insertedIds: {0: ObjectId,...}
  const ids = Object.values(res.insertedIds).map((x) => x.toString());
  return ids;
}

async function getScanDeliveryById(deliveryId) {
  const d = await ensureMongo();
  const _id = new ObjectId(deliveryId);
  return await d.collection('scanDeliveries').findOne({ _id });
}

async function markDeliverySent(deliveryId, serverAttempt) {
  const d = await ensureMongo();
  const _id = new ObjectId(deliveryId);
  const now = new Date();
  await d.collection('scanDeliveries').updateOne(
    { _id },
    {
      $set: {
        status: 'sent',
        serverAttempt,
        lastSentAt: now,
        lockOwner: null,
        lockUntil: null,
        updatedAt: now
      }
    }
  );
}

async function applyDeliverAck({ deliveryId, scanId, pcId, attempt, ok, error, agentAttempt, inputMethod, durationMs }) {
  const d = await ensureMongo();
  const now = new Date();
  const patch = {
    status: ok ? 'ack_ok' : 'ack_fail',
    ackAt: now,
    ackOk: !!ok,
    ackError: ok ? null : (error || 'AGENT_FAIL'),
    agentAttempt: Number.isFinite(agentAttempt) ? agentAttempt : null,
    inputMethod: inputMethod || null,
    durationMs: Number.isFinite(durationMs) ? durationMs : null,
    updatedAt: now
  };

  if (deliveryId) {
    await d.collection('scanDeliveries').updateOne({ _id: new ObjectId(deliveryId) }, { $set: patch });
    const row = await d.collection('scanDeliveries').findOne({ _id: new ObjectId(deliveryId) });
    return row;
  }

  // fallback: match by scanId + pcId (+ attempt best-effort)
  const q = { scanId, pcId };
  const row = await d.collection('scanDeliveries').find(q).sort({ createdAt: -1 }).limit(1).next();
  if (!row) return null;
  await d.collection('scanDeliveries').updateOne({ _id: row._id }, { $set: patch });
  return await d.collection('scanDeliveries').findOne({ _id: row._id });
}

async function emitScanJobUpdate(scanId) {
  const d = await ensureMongo();
  const rows = await d.collection('scanDeliveries').find({ scanId }).toArray();
  if (!rows || rows.length === 0) return;
  const eqid = rows[0].eqid;
  const targets = rows.map((r) => ({
    pcId: r.pcId,
    status: r.status,
    attempt: r.serverAttempt || 0,
    updatedAt: (r.updatedAt instanceof Date) ? r.updatedAt.toISOString() : nowIso(),
    error: r.ackError || undefined
  }));
  broadcastToEqid(eqid, 'scanJobUpdate', { jobId: scanId, eqid, kind: 'barcode', targets });
}

async function notifyDispatcher(deliveryIds) {
  if (!deliveryIds || deliveryIds.length === 0) return;
  try {
    await fetch(DISPATCHER_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ deliveryIds })
    });
  } catch {
    // ignore; dispatcher may be down, it can still poll pending deliveries.
  }
}

// REST endpoints
app.get('/api/agents', (req, res) => {
  const owner = String(req.query.owner || '').trim();
  if (owner.length > 0) {
    // legacy endpoint kept (now backed by Mongo pairings)
    return res.json([]);
  }
  return res.json([]);
});

app.patch('/api/agents/:id', (req, res) => {
  // legacy endpoint kept for compatibility with old admin UI; no-op for now.
  return res.json({ ok: true });
});

// unbind owner (clear ownership) if eqid matches (optional guard)
app.delete('/api/agents/:id/owner', (req, res) => {
  return res.json({ unbound: true });
});

app.get('/api/scanner', (req, res) => {
  return res.json({ message: 'Scanner API is running', timestamp: new Date().toISOString() });
});

app.post('/api/scanner/scan', (req, res) => {
  try {
    const { data, eqid, deviceIds } = req.body || {};
    if (typeof data !== 'string' || data.length === 0) {
      return res.status(400).json({ error: 'data required' });
    }
    const result = {
      id: uuidv4(),
      data,
      timestamp: new Date().toISOString(),
      status: 'Success',
      eqid: eqid || null,
      targets: Array.isArray(deviceIds) ? deviceIds : undefined
    };
    io.emit('ScanResult', result);
    return res.json(result);
  } catch (err) {
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// NOTE: REST app/device endpoints are legacy; WS is the primary protocol now.

// multer storage to temp, then we will move to the desired structure
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 50 * 1024 * 1024 } });

app.post('/api/scanner/image', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }
    const userIdRaw = String(req.body?.userId || '').trim();
    const userId = userIdRaw.length > 0 ? userIdRaw : 'anonymous';
    const day = dayjs().utc().format('YYYYMMDD');

    const root = path.join(filesRoot, 'images', userId, day);
    fs.mkdirSync(root, { recursive: true });

    const stamp = dayjs().utc().format('YYYYMMDD-HHmmssSSS');
    const providedName = String(req.body?.fileName || '').trim();
    const safeProvidedName = providedName.replace(/[^\w.\-]/g, '').slice(0, 128);
    const finalName = safeProvidedName && safeProvidedName.length > 0
      ? safeProvidedName
      : `${stamp}_${uuidv4().replace(/-/g, '').substring(0, 6)}.jpg`;
    const fullPath = path.join(root, finalName);

    fs.writeFileSync(fullPath, req.file.buffer);

    const result = {
      id: uuidv4(),
      fileName: finalName,
      storagePath: fullPath,
      userId,
      timestamp: new Date().toISOString(),
      status: 'Success'
    };

    io.emit('ScanResult', {
      id: result.id,
      type: 'image',
      data: result.fileName,
      userId: result.userId,
      timestamp: result.timestamp,
      status: result.status
    });

    return res.json(result);
  } catch (err) {
    return res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/api/scanner/broadcast', (req, res) => {
  try {
    const { message } = req.body || {};
    io.emit('Broadcast', message);
    return res.json({ message: 'Broadcast sent successfully' });
  } catch (err) {
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// socket.io handlers (SignalR-like)
io.on('connection', (socket) => {
  io.emit('UserConnected', socket.id);

  socket.on('disconnect', () => {
    io.emit('UserDisconnected', socket.id);
  });

  socket.on('JoinGroup', (groupName) => {
    const group = String(groupName || '').trim();
    if (group.length === 0) return;
    socket.join(group);
    io.to(group).emit('UserJoined', socket.id);
  });

  socket.on('LeaveGroup', (groupName) => {
    const group = String(groupName || '').trim();
    if (group.length === 0) return;
    socket.leave(group);
    io.to(group).emit('UserLeft', socket.id);
  });

  socket.on('SendMessage', (user, message) => {
    io.emit('ReceiveMessage', user, message);
  });

  socket.on('SendScanResult', (scanData) => {
    io.emit('ScanResult', scanData);
  });

  socket.on('SendToGroup', (groupName, message) => {
    const group = String(groupName || '').trim();
    if (group.length === 0) return;
    io.to(group).emit('GroupMessage', message);
  });

  socket.on('DispatchRequest', (request) => {
    try {
      const agentId = String(request?.agentId || '').trim();
      const group = `agent:${agentId}`;
      io.to(group).emit('DispatchRequest', {
        id: request?.id || uuidv4(),
        agentId,
        type: request?.type || 'barcode',
        data: request?.data || '',
        options: {
          sendEnter: !!request?.options?.sendEnter ?? true,
          delayMs: Number(request?.options?.delayMs ?? 10)
        }
      });
    } catch (e) {
      // noop
    }
  });

  socket.on('AckDispatch', (ack) => {
    try {
      io.emit('DispatchAck', {
        id: String(ack?.id || ''),
        agentId: String(ack?.agentId || ''),
        success: !!ack?.success,
        error: ack?.error ? String(ack.error) : undefined,
        receivedAt: new Date().toISOString()
      });
    } catch (e) {
      // noop
    }
  });
});

// ---------------------------
// Internal dispatch endpoint (dispatcher -> node-api)
// ---------------------------
app.post('/internal/dispatch', async (req, res) => {
  const token = String(req.header('x-internal-token') || '');
  if (INTERNAL_TOKEN && token !== INTERNAL_TOKEN) return res.status(401).json({ error: 'unauthorized' });
  const deliveryId = String(req.body?.deliveryId || '').trim();
  if (!deliveryId) return res.status(400).json({ error: 'deliveryId required' });

  try {
    const row = await getScanDeliveryById(deliveryId);
    if (!row) return res.status(404).json({ error: 'not_found' });
    if (row.status === 'ack_ok' || row.status === 'ack_fail') return res.json({ ok: true, skipped: true, reason: 'already_acked' });

    const pcId = String(row.pcId || '');
    const ws = pcSocketById.get(pcId);
    if (!ws) {
      // keep pending; dispatcher can retry/poll later
      return res.status(202).json({ ok: false, queued: true, reason: 'pc_offline' });
    }

    const nextAttempt = Number(row.serverAttempt || 0) + 1;
    await markDeliverySent(deliveryId, nextAttempt);

    sendJson(ws, {
      type: 'event',
      event: 'deliverBarcode',
      data: {
        deliveryId,
        jobId: row.scanId, // keep PC agent behavior (jobId idempotency)
        attempt: nextAttempt,
        createdAt: (row.createdAt instanceof Date) ? row.createdAt.toISOString() : nowIso(),
        eqid: row.eqid,
        barcode: row.barcode,
        suffixKey: 'Enter'
      },
      timestamp: nowIso()
    });

    await emitScanJobUpdate(String(row.scanId));
    return res.json({ ok: true, delivered: true, pcId, attempt: nextAttempt });
  } catch (e) {
    return res.status(500).json({ error: 'dispatch_failed' });
  }
});

// ---------------------------
// Raw WS endpoint for app + pcAgent (be-ws compatible)
// ---------------------------
const wss = new WebSocketServer({ server, path: WS_PATH });

async function handleMessage(ws, msg) {
  const requestId = msg.requestId || null;
  const clientType = msg.clientType || null;

  if (typeof clientType === 'string') {
    const existing = clientInfoByWs.get(ws) || {};
    clientInfoByWs.set(ws, { ...existing, clientType });
  }

  // app init (client supplies eqid or server issues one)
  if (msg.type === 'appInit') {
    const candidate = (msg.data && String(msg.data.eqid || '').trim().toUpperCase()) || '';
    let eqid = /^[A-Z0-9]{6}$/.test(candidate) ? candidate : genEqid6();
    for (let i = 0; i < 5; i++) {
      const exists = await getApp(eqid);
      if (!exists) break;
      eqid = genEqid6();
    }
    const row = await upsertApp(eqid, 'SCANNER');

    const existing = clientInfoByWs.get(ws) || {};
    clientInfoByWs.set(ws, { ...existing, clientType: 'app', eqid });
    registerAppSocket(eqid, ws);

    return sendResponse(ws, requestId, true, { eqid, alias: row?.alias || 'SCANNER' });
  }

  // pc agent hello
  if (msg.type === 'pcAgentHello') {
    const data = msg.data || {};
    const group = String(data.group || 'default').trim();
    const deviceName = String(data.deviceName || 'pc').trim();
    const machineId = String(data.machineId || '').trim();
    const pcId = String(data.pcId || hashPcId(group, deviceName, machineId));

    clientInfoByWs.set(ws, { clientType: 'pcAgent', pcId });
    pcSocketById.set(pcId, ws);

    await upsertPcDevice(pcId, group, deviceName, machineId, true);

    const issued = issuePairing(ws, pcId);
    // eslint-disable-next-line no-console
    console.log(`[pcAgentHello] pcId=${pcId} pairingCode=${issued.code} pin=${issued.pin}`);

    return sendResponse(ws, requestId, true, { pcId, pairingCode: issued.code, pairingPin: issued.pin });
  }

  // pairing request from app
  if (msg.type === 'pairRequest') {
    const data = msg.data || {};
    const eqid = String(data.eqid || '').trim();
    const code = String(data.code || '').trim();
    const pin = String(data.pin || '').trim();
    if (!eqid || !code) return sendResponse(ws, requestId, false, null, { code: 'INVALID', message: 'eqid/code required' });

    const pcId = pairingCodeToPcId.get(code);
    const meta = getPairingMeta(code);
    if (!pcId || !meta) return sendResponse(ws, requestId, false, null, { code: 'NOT_FOUND', message: 'invalid or expired pairing code' });
    if (!pin) return sendResponse(ws, requestId, false, null, { code: 'PIN_REQUIRED', message: 'pairing pin required' });
    if (pin !== meta.pin) {
      meta.failCount++;
      if (meta.failCount >= 5) {
        pairingMetaByCode.delete(code);
        pairingCodeToPcId.delete(code);
      } else {
        pairingMetaByCode.set(code, meta);
      }
      return sendResponse(ws, requestId, false, null, { code: 'PIN_MISMATCH', message: 'invalid pin' });
    }

    await setPairing(eqid, pcId, true);
    broadcastToEqid(eqid, 'paired', { eqid, pcId });

    const pcWs = pcSocketById.get(pcId);
    if (pcWs) sendJson(pcWs, { type: 'event', event: 'paired', data: { eqid }, timestamp: nowIso() });

    // one-time use: invalidate code after successful pairing
    pairingMetaByCode.delete(code);
    pairingCodeToPcId.delete(code);

    return sendResponse(ws, requestId, true, { eqid, pcId, enabled: true });
  }

  // list pairings
  if (msg.type === 'pairList') {
    const data = msg.data || {};
    const eqid = String(data.eqid || '').trim();
    if (!eqid) return sendResponse(ws, requestId, false, null, { code: 'INVALID', message: 'eqid required' });
    const rows = await listPairings(eqid);
    const list = rows.map((r) => ({
      pcId: r.pcId,
      enabled: !!r.enabled,
      online: pcSocketById.has(r.pcId)
    }));
    return sendResponse(ws, requestId, true, { eqid, list });
  }

  // enable/disable
  if (msg.type === 'pairSetEnabled') {
    const data = msg.data || {};
    const eqid = String(data.eqid || '').trim();
    const pcId = String(data.pcId || '').trim();
    const enabled = !!data.enabled;
    if (!eqid || !pcId) return sendResponse(ws, requestId, false, null, { code: 'INVALID', message: 'eqid/pcId required' });
    await setPairing(eqid, pcId, enabled);
    return sendResponse(ws, requestId, true, { eqid, pcId, enabled });
  }

  // scan barcode -> DB history rows only, then hand keys to dispatcher
  if (msg.type === 'scanBarcode') {
    const data = msg.data || {};
    const eqid = String(data.eqid || '').trim();
    const barcode = String(data.barcode || '').trim();
    if (!eqid || !barcode) return sendResponse(ws, requestId, false, null, { code: 'INVALID', message: 'eqid/barcode required' });

    // register this ws for events
    const existing = clientInfoByWs.get(ws) || {};
    clientInfoByWs.set(ws, { ...existing, clientType: 'app', eqid });
    registerAppSocket(eqid, ws);

    const scanId = uuidv4();
    const pairRows = await listPairings(eqid);
    const targets = pairRows.filter((r) => r.enabled === true).map((r) => String(r.pcId));

    const deliveryIds = targets.length > 0 ? await insertScanDeliveries(scanId, eqid, barcode, targets) : [];

    // reply immediately (keep old key name jobId for Flutter compatibility)
    sendResponse(ws, requestId, true, { jobId: scanId, targets, deliveryIds });

    // push initial status snapshot to app (pending rows)
    await emitScanJobUpdate(scanId);

    // async notify dispatcher with keys
    setTimeout(() => { notifyDispatcher(deliveryIds); }, 0);
    return;
  }

  // deliver ack from pc agent -> persist into history row
  if (msg.type === 'deliverAck') {
    const info = clientInfoByWs.get(ws);
    if (!info || info.clientType !== 'pcAgent' || !info.pcId) return sendResponse(ws, requestId, true, { received: true });
    const data = msg.data || {};
    const pcId = String(data.pcId || info.pcId);
    const scanId = String(data.jobId || '');
    const deliveryId = data.deliveryId ? String(data.deliveryId) : '';
    const attempt = Number(data.attempt || 0);
    const ok = !!data.ok;
    const agentAttempt = Number(data.agentAttempt || 0);
    const error = data.error ? String(data.error) : '';
    const inputMethod = data.inputMethod ? String(data.inputMethod) : '';
    const durationMs = Number(data.durationMs || 0);

    const row = await applyDeliverAck({
      deliveryId: deliveryId || null,
      scanId,
      pcId,
      attempt,
      ok,
      error,
      agentAttempt,
      inputMethod,
      durationMs
    });

    if (row?.scanId) await emitScanJobUpdate(String(row.scanId));

    // eslint-disable-next-line no-console
    console.log(`[deliverAck] scanId=${scanId} deliveryId=${deliveryId || '(none)'} pcId=${pcId} attempt=${attempt} ok=${ok}`);
    return sendResponse(ws, requestId, true, { received: true });
  }

  // ping/pong
  if (msg.type === 'ping') {
    return sendResponse(ws, requestId, true, { pong: true });
  }

  return sendResponse(ws, requestId, false, null, { code: 'UNKNOWN', message: 'unknown message type' });
}

wss.on('connection', (ws) => {
  allSockets.add(ws);
  clientInfoByWs.set(ws, { clientType: 'unknown' });

  ws.on('message', (data) => {
    const text = data.toString('utf8');
    const msg = safeJsonParse(text);
    if (!msg) {
      sendResponse(ws, null, false, null, { code: 'BAD_JSON', message: 'invalid json' });
      return;
    }
    handleMessage(ws, msg).catch((e) => {
      sendResponse(ws, msg.requestId || null, false, null, { code: 'ERR', message: 'server_error' });
    });
  });

  ws.on('close', () => {
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
      upsertPcDevice(info.pcId, '', '', '', false).catch(() => { });
      const curCode = pairingCodeByPcId.get(info.pcId);
      if (curCode) {
        invalidatePairingCode(curCode);
        pairingCodeByPcId.delete(info.pcId);
      }
    }
  });
});

server.listen(PORT, HOST, () => {
  // eslint-disable-next-line no-console
  console.log(`node-api listening on http://${HOST}:${PORT} and ws://${HOST}:${PORT}${WS_PATH}`);
});


