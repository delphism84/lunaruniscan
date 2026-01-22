import WebSocket from "ws";

const url = process.env.WS_URL || "ws://127.0.0.1:45444/ws/sendReq";

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function wsSend(ws, obj) {
  ws.send(JSON.stringify(obj));
}

function onceMessage(ws, predicate, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const to = setTimeout(() => {
      cleanup();
      reject(new Error("timeout"));
    }, timeoutMs);

    function onMsg(raw) {
      let msg;
      try { msg = JSON.parse(raw.toString("utf8")); } catch { return; }
      if (predicate(msg)) {
        cleanup();
        resolve(msg);
      }
    }
    function cleanup() {
      clearTimeout(to);
      ws.off("message", onMsg);
    }
    ws.on("message", onMsg);
  });
}

async function run() {
  // 1) pc agent connect
  const pc = new WebSocket(url);
  await new Promise((r, j) => { pc.once("open", r); pc.once("error", j); });
  wsSend(pc, {
    type: "pcAgentHello",
    requestId: "pc-hello",
    clientType: "pcAgent",
    timestamp: new Date().toISOString(),
    data: { group: "default", deviceName: "PC-TEST", machineId: "SMOKE" }
  });

  const pairingMsg = await onceMessage(pc, (m) => m?.type === "event" && m?.event === "pairingCode", 5000);
  const code = pairingMsg.data?.code;
  const pcId = pairingMsg.data?.pcId;
  console.log("pairingCode:", code, "pcId:", pcId);

  pc.on("message", (raw) => {
    let m;
    try { m = JSON.parse(raw.toString("utf8")); } catch { return; }
    if (m?.type === "event" && m?.event === "deliverBarcode") {
      const d = m.data || {};
      console.log("pc got deliverBarcode:", d);
      wsSend(pc, {
        type: "deliverAck",
        requestId: "ack-" + d.jobId,
        clientType: "pcAgent",
        timestamp: new Date().toISOString(),
        data: { jobId: d.jobId, pcId, attempt: d.attempt, ok: true, agentAttempt: 1, inputMethod: "mock", durationMs: 1 }
      });
    }
  });

  // 2) app connect + pair + scan
  const app = new WebSocket(url);
  await new Promise((r, j) => { app.once("open", r); app.once("error", j); });
  const eqid = "ABC123";
  wsSend(app, {
    type: "appInit",
    requestId: "app-init",
    clientType: "app",
    timestamp: new Date().toISOString(),
    data: { eqid }
  });
  await onceMessage(app, (m) => m?.type === "response" && m?.requestId === "app-init", 3000);

  wsSend(app, {
    type: "pairRequest",
    requestId: "pair-1",
    clientType: "app",
    timestamp: new Date().toISOString(),
    data: { eqid, code }
  });
  await onceMessage(app, (m) => m?.type === "response" && m?.requestId === "pair-1" && m?.ok === true, 3000);

  app.on("message", (raw) => {
    let m;
    try { m = JSON.parse(raw.toString("utf8")); } catch { return; }
    if (m?.type === "event" && m?.event === "scanJobUpdate") {
      console.log("app got scanJobUpdate:", m.data);
    }
  });

  wsSend(app, {
    type: "scanBarcode",
    requestId: "scan-1",
    clientType: "app",
    timestamp: new Date().toISOString(),
    data: { eqid, barcode: "1234567890" }
  });
  const resp = await onceMessage(app, (m) => m?.type === "response" && m?.requestId === "scan-1" && m?.ok === true, 3000);
  console.log("scan response:", resp.data);

  // wait for ack propagation
  await sleep(1500);

  pc.close();
  app.close();
  await sleep(300);
  console.log("e2e smoke done");
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});

