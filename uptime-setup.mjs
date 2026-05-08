import { io } from "socket.io-client";

const UK_URL = "http://localhost:3101";
const USERNAME = "admin";
const PASSWORD = process.env.UK_PASSWORD || "a8c2542aa56c65ae91bccb17973668bd";

const base = {
  type: "http",
  method: "GET",
  interval: 60,
  retryInterval: 60,
  maxretries: 1,
  accepted_statuscodes: ["200-299"],
  notificationIDList: {},
  ignoreTls: false,
  upsideDown: false,
  expiryNotification: false,
  active: true,
};

const MONITORS = [
  { ...base, name: "notion-cache", url: "https://notion-cache.vps.sarvinshrivastava.space/health" },
  { ...base, name: "Grafana", url: "https://monitoring.vps.sarvinshrivastava.space/api/health" },
  { ...base, name: "Uptime Kuma", url: "https://status.vps.sarvinshrivastava.space" },
  { ...base, name: "secrets-manager", url: "https://secrets.vps.sarvinshrivastava.space/healthz" },
];

function call(socket, event, ...args) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Timeout: ${event}`)), 8000);
    socket.emit(event, ...args, (res) => {
      clearTimeout(timer);
      if (res && res.ok === false) return reject(new Error(res.msg || JSON.stringify(res)));
      resolve(res);
    });
  });
}

async function run() {
  const socket = io(UK_URL, { transports: ["websocket"] });

  await new Promise((res, rej) => {
    socket.on("connect", res);
    socket.on("connect_error", rej);
    setTimeout(() => rej(new Error("connect timeout")), 15000);
  });
  console.log("Connected to Uptime Kuma");

  const info = await new Promise((res) => socket.on("info", res));
  console.log("Server version:", info.version);

  let needSetup = false;
  try {
    const status = await call(socket, "loginByToken", "");
    if (!status.ok) needSetup = true;
  } catch {
    needSetup = true;
  }

  if (needSetup) {
    try {
      await call(socket, "setup", USERNAME, PASSWORD);
      console.log("Admin account created");
    } catch (e) {
      if (!e.message.includes("already")) throw e;
      console.log("Admin already exists");
    }
  }

  const loginRes = await call(socket, "login", { username: USERNAME, password: PASSWORD, token: "" });
  if (!loginRes.ok) throw new Error("Login failed: " + loginRes.msg);
  console.log("Logged in");

  const existing = await new Promise((res) => {
    socket.on("monitorList", res);
    setTimeout(() => res({}), 3000);
  });
  const existingNames = new Set(Object.values(existing).map((m) => m.name));
  console.log("Existing monitors:", [...existingNames]);

  for (const mon of MONITORS) {
    if (existingNames.has(mon.name)) {
      console.log(`Skip (exists): ${mon.name}`);
      continue;
    }
    try {
      const r = await call(socket, "add", mon);
      console.log(`Added: ${mon.name} (id=${r.monitorID})`);
    } catch (e) {
      console.error(`Failed: ${mon.name} — ${e.message}`);
    }
  }

  socket.disconnect();
  console.log("Monitor setup done");
}

run().catch((e) => { console.error(e.message); process.exit(1); });
