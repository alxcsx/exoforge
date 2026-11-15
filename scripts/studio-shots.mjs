#!/usr/bin/env node
// Screenshot the Studio at several widths/themes/pin-states over CDP.
// Node 22+ has a built-in WebSocket, so this needs no dependencies.
//
//   node scripts/studio-shots.mjs [outdir]
//
// Assumes the dev server is on :4005 with admin/admin (config/dev.exs defaults).

import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";

const OUT = process.argv[2] || "/tmp/studio-shots";
const PORT = 9333;
const BASE = "http://localhost:4005";
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

mkdirSync(OUT, { recursive: true });

const chrome = spawn(
  CHROME,
  [
    "--headless=new",
    "--disable-gpu",
    "--no-first-run",
    "--no-default-browser-check",
    `--remote-debugging-port=${PORT}`,
    `--user-data-dir=/tmp/studio-shots-${process.pid}`,
    "about:blank",
  ],
  { stdio: "ignore", detached: true },
);

async function cdpTarget() {
  for (let i = 0; i < 50; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${PORT}/json/list`);
      const targets = await res.json();
      const page = targets.find((t) => t.type === "page");
      if (page) return page.webSocketDebuggerUrl;
    } catch {}
    await sleep(200);
  }
  throw new Error("chrome did not expose a page target");
}

const ws = new WebSocket(await cdpTarget());
await new Promise((r) => (ws.onopen = r));

let seq = 0;
const pending = new Map();
ws.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result);
  }
};

const send = (method, params = {}) =>
  new Promise((resolve, reject) => {
    const id = ++seq;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });

await send("Page.enable");
await send("Runtime.enable");

const js = async (expression) => {
  const { result } = await send("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  return result.value;
};

const goto = async (url) => {
  await send("Page.navigate", { url });
  await sleep(1200);
};

const shot = async (name) => {
  const { data } = await send("Page.captureScreenshot", { format: "png" });
  writeFileSync(`${OUT}/${name}.png`, Buffer.from(data, "base64"));
  console.log("  ", `${OUT}/${name}.png`);
};

const viewport = async (width, height) =>
  send("Emulation.setDeviceMetricsOverride", {
    width,
    height,
    deviceScaleFactor: 1,
    mobile: width < 640,
  });

const setTheme = (theme) =>
  js(`localStorage.setItem('exo_theme', '${theme}'); document.documentElement.classList.remove('dark','light'); document.documentElement.classList.add('${theme}'); true`);

// --- log in through the real form so the session cookie is genuine -------------
await viewport(1440, 900);
await goto(`${BASE}/login`);

// Submit the real form: the POST is CSRF-protected, so the token has to come from the page.
await js(`(() => {
  document.querySelector('#email').value = 'admin';
  document.querySelector('#password').value = 'admin';
  document.querySelector('form[action="/login"]').submit();
  return true;
})()`);
await sleep(2000);
const who = await js(`document.body.innerText.slice(0, 60)`);
console.log("after login, body starts:", JSON.stringify(who.replace(/\s+/g, " ").slice(0, 60)));

// Pins are LiveView state, so drive them through the registry's own pin buttons:
// unpin everything first, then pin the ids we want in order.
const setPins = async (ids) => {
  await goto(`${BASE}/extensions`);
  await js(`(() => {
    document.querySelectorAll('[phx-click="unpin_extension"]').forEach(b => b.click());
    return true;
  })()`);
  await sleep(600);
  for (const id of ids) {
    const clicked = await js(`(() => {
      const b = document.querySelector('[phx-click="pin_extension"][phx-value-id="${id}"]');
      if (!b) return false;
      b.click();
      return true;
    })()`);
    if (!clicked) console.log("   !! no pin button for", id);
    await sleep(500);
  }
};

const STATES = [
  { label: "0pin", ids: [] },
  { label: "2pin", ids: ["exoforge_std_auth", "exoforge_std_player_data"] },
  {
    label: "4pin",
    ids: [
      "exoforge_std_auth",
      "exoforge_std_player_data",
      "exoforge_std_database",
      "exoforge_std_resources",
    ],
  },
];

for (const theme of ["dark", "light"]) {
  for (const width of [375, 768, 1440]) {
    await viewport(width, 900);
    await goto(`${BASE}/`);
    await setTheme(theme);

    for (const { label, ids } of STATES) {
      await setPins(ids);
      await goto(`${BASE}/`);
      await sleep(700);
      await shot(`${theme}-${width}-${label}`);

      if (label === "4pin" && width === 375) {
        // open the overflow menu and measure it against the viewport
        const opened = await js(`(() => {
          const btn = [...document.querySelectorAll('button')].find(b => b.textContent.trim().startsWith('Pinned'));
          if (!btn) return 'no pinned button';
          btn.click();
          return 'clicked';
        })()`);
        await sleep(400);
        const box = await js(`(() => {
          const menu = document.querySelector('nav .absolute');
          if (!menu) return null;
          const r = menu.getBoundingClientRect();
          return { left: Math.round(r.left), right: Math.round(r.right), width: Math.round(r.width), viewport: window.innerWidth };
        })()`);
        console.log("   pinned menu @375:", opened, JSON.stringify(box));
        await shot(`${theme}-${width}-${label}-menu`);
      }
    }
  }
}

ws.close();
try {
  process.kill(-chrome.pid);
} catch {}
console.log("done");
process.exit(0);
