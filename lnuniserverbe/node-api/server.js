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
const PORT = Number(process.env.PORT || 50100);
const HOST = process.env.HOST || '0.0.0.0';

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

// in-memory agents store
const agentList = [];

// simple persistent store for app init and device ownership
const dataRoot = path.join(filesRoot, 'data');
const devicesFile = path.join(dataRoot, 'devices.json'); // [{ eqid, alias, createdAt }]
const ownershipFile = path.join(dataRoot, 'ownership.json'); // { agentId: eqid }
function ensureDataDir() {
  if (!fs.existsSync(dataRoot)) fs.mkdirSync(dataRoot, { recursive: true });
  if (!fs.existsSync(devicesFile)) fs.writeFileSync(devicesFile, '[]');
  if (!fs.existsSync(ownershipFile)) fs.writeFileSync(ownershipFile, '{}');
}
function readJsonSafe(file, fallback) {
  try {
    const raw = fs.readFileSync(file, 'utf8');
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
}
function writeJsonSafe(file, obj) {
  fs.writeFileSync(file, JSON.stringify(obj, null, 2), 'utf8');
}
function generateEqid() {
  const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const digits = '0123456789';
  const l = () => letters[Math.floor(Math.random() * letters.length)];
  const d = () => digits[Math.floor(Math.random() * digits.length)];
  return `${l()}${l()}${l()}${d()}${d()}${d()}`;
}

// REST endpoints
app.get('/api/agents', (req, res) => {
  const owner = String(req.query.owner || '').trim();
  if (owner.length > 0) {
    const owners = readJsonSafe(ownershipFile, {});
    const list = agentList.filter(a => owners[a.agentId] === owner);
    return res.json(list);
  }
  return res.json(agentList);
});

app.patch('/api/agents/:id', (req, res) => {
  const id = String(req.params.id || '').trim();
  if (!id) {
    return res.status(400).json({ error: 'id required' });
  }
  const { status, ownerUserId } = req.body || {};
  let agent = agentList.find(a => a.agentId === id);
  if (!agent) {
    agent = {
      agentId: id,
      name: `Agent-${id.substring(0, 6)}`,
      status: 'offline',
      ownerUserId: undefined
    };
    agentList.push(agent);
  }
  if (typeof status === 'string' && status.length > 0) {
    agent.status = status;
  }
  if (typeof ownerUserId === 'string' && ownerUserId.length > 0) {
    agent.ownerUserId = ownerUserId;
    ensureDataDir();
    const owners = readJsonSafe(ownershipFile, {});
    owners[id] = ownerUserId;
    writeJsonSafe(ownershipFile, owners);
  }
  return res.json(agent);
});

// unbind owner (clear ownership) if eqid matches (optional guard)
app.delete('/api/agents/:id/owner', (req, res) => {
  try {
    const id = String(req.params.id || '').trim();
    if (!id) return res.status(400).json({ error: 'id required' });
    ensureDataDir();
    const owners = readJsonSafe(ownershipFile, {});
    const targetEqid = String(req.query.eqid || '').trim();
    if (owners[id]) {
      if (targetEqid && owners[id] !== targetEqid) {
        return res.status(403).json({ error: 'eqid mismatch' });
      }
      delete owners[id];
      writeJsonSafe(ownershipFile, owners);
    }
    const agent = agentList.find(a => a.agentId === id);
    if (agent) agent.ownerUserId = undefined;
    return res.json({ id, unbound: true });
  } catch {
    return res.status(500).json({ error: 'failed to unbind' });
  }
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

// app init: issue EQID and persist
app.post('/api/app/init', (req, res) => {
  try {
    ensureDataDir();
    const devices = readJsonSafe(devicesFile, []);
    // try to reuse if provided eqid exists
    const provided = String(req.body?.eqid || '').trim();
    if (provided.length === 6 && /^[A-Z]{3}\d{3}$/.test(provided)) {
      const found = devices.find(d => d.eqid === provided);
      if (found) return res.json(found);
    }
    // generate new unique eqid
    let eqid;
    do {
      eqid = generateEqid();
    } while (devices.some(d => d.eqid === eqid));
    const alias = 'SCANNER';
    const record = { eqid, alias, createdAt: new Date().toISOString() };
    devices.push(record);
    writeJsonSafe(devicesFile, devices);
    return res.json(record);
  } catch (e) {
    return res.status(500).json({ error: 'init failed' });
  }
});

// update alias
app.patch('/api/app/alias', (req, res) => {
  try {
    ensureDataDir();
    const { eqid, alias } = req.body || {};
    if (typeof eqid !== 'string' || !/^[A-Z]{3}\d{3}$/.test(eqid)) {
      return res.status(400).json({ error: 'invalid eqid' });
    }
    const devices = readJsonSafe(devicesFile, []);
    const idx = devices.findIndex(d => d.eqid === eqid);
    if (idx === -1) return res.status(404).json({ error: 'not found' });
    const nextAlias = String(alias || '').trim() || 'SCANNER';
    devices[idx].alias = nextAlias;
    writeJsonSafe(devicesFile, devices);
    return res.json(devices[idx]);
  } catch {
    return res.status(500).json({ error: 'alias update failed' });
  }
});

// list agents bound to eqid
app.get('/api/app/devices', (req, res) => {
  try {
    ensureDataDir();
    const eqid = String(req.query.eqid || '').trim();
    if (!/^[A-Z]{3}\d{3}$/.test(eqid)) {
      return res.status(400).json({ error: 'invalid eqid' });
    }
    const owners = readJsonSafe(ownershipFile, {});
    const bound = agentList.filter(a => owners[a.agentId] === eqid);
    // shape rows
    const rows = bound.map(a => ({
      id: a.agentId,
      name: a.name,
      status: a.status,
      type: 'PC'
    }));
    return res.json(rows);
  } catch {
    return res.status(500).json({ error: 'failed to list devices' });
  }
});

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

server.listen(PORT, HOST, () => {
  // eslint-disable-next-line no-console
  console.log(`node-api listening on http://${HOST}:${PORT}`);
});


