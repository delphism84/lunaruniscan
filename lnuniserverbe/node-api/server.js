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

// REST endpoints
app.get('/api/agents', (req, res) => {
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
  }
  return res.json(agent);
});

app.get('/api/scanner', (req, res) => {
  return res.json({ message: 'Scanner API is running', timestamp: new Date().toISOString() });
});

app.post('/api/scanner/scan', (req, res) => {
  try {
    const { data } = req.body || {};
    if (typeof data !== 'string' || data.length === 0) {
      return res.status(400).json({ error: 'data required' });
    }
    const result = {
      id: uuidv4(),
      data,
      timestamp: new Date().toISOString(),
      status: 'Success'
    };
    io.emit('ScanResult', result);
    return res.json(result);
  } catch (err) {
    return res.status(500).json({ error: 'Internal server error' });
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


