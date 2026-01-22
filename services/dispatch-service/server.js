import express from 'express';
import crypto from 'crypto';
import { MongoClient, ObjectId } from 'mongodb';

const PORT = Number(process.env.PORT || 50210);
const HOST = process.env.HOST || '0.0.0.0';

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017';
const MONGO_DB = process.env.MONGO_DB || 'uniscan';

// node-api internal dispatch endpoint
const NODE_API_INTERNAL_URL = process.env.NODE_API_INTERNAL_URL || 'http://127.0.0.1:45444/internal/dispatch';
const INTERNAL_TOKEN = process.env.INTERNAL_TOKEN || '';

const POLL_MS = Number(process.env.DISPATCH_POLL_MS || 1000);
const LOCK_MS = Number(process.env.DISPATCH_LOCK_MS || 30_000);
const CONCURRENCY = Math.max(1, Number(process.env.DISPATCH_CONCURRENCY || 2));

const serviceId = process.env.SERVICE_ID || `disp_${crypto.randomBytes(6).toString('hex')}`;

const app = express();
app.use(express.json({ limit: '2mb' }));

/** @type {MongoClient | null} */
let mongoClient = null;
/** @type {import('mongodb').Db | null} */
let db = null;

async function ensureMongo() {
  if (db) return db;
  mongoClient = new MongoClient(MONGO_URI);
  await mongoClient.connect();
  db = mongoClient.db(MONGO_DB);
  return db;
}

function now() {
  return new Date();
}

async function claimOnePending() {
  const d = await ensureMongo();
  const col = d.collection('scanDeliveries');
  const t = now();
  const lockUntil = new Date(t.getTime() + LOCK_MS);

  // Only claim deliveries that are not yet ACKed.
  const filter = {
    status: 'pending',
    $or: [{ lockUntil: null }, { lockUntil: { $lte: t } }]
  };

  const update = {
    $set: {
      status: 'dispatching',
      lockOwner: serviceId,
      lockUntil,
      updatedAt: t
    }
  };

  const res = await col.findOneAndUpdate(filter, update, { sort: { createdAt: 1 }, returnDocument: 'after' });
  return res.value;
}

async function releaseToPending(_id) {
  const d = await ensureMongo();
  await d.collection('scanDeliveries').updateOne(
    { _id },
    {
      $set: { status: 'pending', lockOwner: null, lockUntil: null, updatedAt: now() }
    }
  );
}

async function dispatchById(deliveryId) {
  const resp = await fetch(NODE_API_INTERNAL_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(INTERNAL_TOKEN ? { 'x-internal-token': INTERNAL_TOKEN } : {})
    },
    body: JSON.stringify({ deliveryId })
  });
  return resp;
}

let inFlight = 0;
async function pumpOnce() {
  if (inFlight >= CONCURRENCY) return;

  const row = await claimOnePending();
  if (!row) return;
  inFlight++;

  (async () => {
    try {
      const deliveryId = row._id.toString();
      const resp = await dispatchById(deliveryId);

      if (resp.status === 202) {
        // PC offline or not ready -> release back to pending so it can be retried.
        await releaseToPending(row._id);
        return;
      }
      if (!resp.ok) {
        await releaseToPending(row._id);
        return;
      }

      // success: node-api will mark as sent and clear lock; nothing else needed here
      return;
    } catch {
      try {
        await releaseToPending(row._id);
      } catch { }
    } finally {
      inFlight--;
    }
  })();
}

const enqueueSet = new Set();
app.post('/enqueue', async (req, res) => {
  const ids = req.body?.deliveryIds;
  const list = Array.isArray(ids) ? ids.map((x) => String(x)).filter(Boolean) : [];
  for (const id of list) enqueueSet.add(id);

  // best-effort immediate dispatch attempts for enqueued ids
  (async () => {
    for (const id of list) {
      try {
        const d = await ensureMongo();
        const col = d.collection('scanDeliveries');
        const _id = new ObjectId(id);
        // If it's still pending, set to pending explicitly (so poller can pick up in order)
        await col.updateOne(
          { _id, status: { $in: ['pending', 'dispatching'] } },
          { $set: { status: 'pending', updatedAt: now() } }
        );
      } catch { }
    }
  })();

  return res.json({ ok: true, queued: list.length });
});

app.get('/health', (req, res) => {
  return res.json({ ok: true, serviceId, ts: new Date().toISOString(), inFlight });
});

async function main() {
  await ensureMongo();
  setInterval(() => {
    pumpOnce().catch(() => { });
    pumpOnce().catch(() => { });
  }, Math.max(200, POLL_MS));

  app.listen(PORT, HOST, () => {
    // eslint-disable-next-line no-console
    console.log(`dispatch-service listening on http://${HOST}:${PORT} serviceId=${serviceId}`);
  });
}

main().catch((e) => {
  // eslint-disable-next-line no-console
  console.error('dispatch-service failed to start', e);
  process.exit(1);
});

