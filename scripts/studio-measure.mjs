#!/usr/bin/env node
// Measure the Studio top bar at several widths and pin counts, over CDP.
// Reports facts the eye would only guess at: clipping, off-screen menus, overlap.
//
//   node scripts/studio-measure.mjs

import { spawn } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";

const PORT = 9334;
const BASE = "http://localhost:4005";
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

const chrome = spawn(
  CHROME,
  [
    "--headless=new",
    "--disable-gpu",
    "--no-first-run",
    `--remote-debugging-port=${PORT}`,
    `--user-data-dir=/tmp/studio-measure-${process.pid}`,
    "about:blank",
  ],
  { stdio: "ignore", detached: true },
);

async function target() {
  // A leftover Chrome from an earlier run would answer on this port and hand us a stale
  // page, which reads as "the login form vanished". Own the port or fail.
  for (let i = 0; i < 60; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      const page = list.find((t) => t.type === "page" && t.url === "about:blank");
      if (page) return page.webSocketDebuggerUrl;
    } catch {}
    await sleep(200);
  }
  throw new Error("no fresh about:blank target on port " + PORT + " (leftover Chrome?)");
}

const ws = new WebSocket(await target());
await new Promise((r) => (ws.onopen = r));
let seq = 0;
const pending = new Map();
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) {
    const { resolve, reject } = pending.get(m.id);
    pending.delete(m.id);
    m.error ? reject(new Error(JSON.stringify(m.error))) : resolve(m.result);
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
  const { result, exceptionDetails } = await send("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  if (exceptionDetails) throw new Error(JSON.stringify(exceptionDetails));
  return result.value;
};

// CDP device-metrics override does not fire a window resize event, and NavCapacity listens for
// one. Dispatch it, or the probe measures a bar that never re-measured itself.
const viewport = async (width, height = 900) => {
  await send("Emulation.setDeviceMetricsOverride", {
    width,
    height,
    deviceScaleFactor: 1,
    mobile: width < 640,
  });
  await js(`window.dispatchEvent(new Event('resize')); true`).catch(() => {});
  await sleep(400);
};

const goto = async (url) => {
  await send("Page.navigate", { url });
  await sleep(1100);
};

const waitFor = async (expression, tries = 40) => {
  for (let i = 0; i < tries; i++) {
    if (await js(expression)) return true;
    await sleep(250);
  }
  return false;
};

await viewport(1440);
await goto(`${BASE}/login`);
await waitFor(`!!document.querySelector('#email')`);
await js(`(() => {
  document.querySelector('#email').value = 'admin';
  document.querySelector('#password').value = 'admin';
  document.querySelector('form[action="/login"]').submit();
  return true;
})()`);
await sleep(2000);

const setPins = async (ids) => {
  await goto(`${BASE}/extensions`);
  await js(`(() => { document.querySelectorAll('[phx-click="unpin_extension"]').forEach(b => b.click()); return true; })()`);
  await sleep(700);
  for (const id of ids) {
    await js(`(() => {
      const b = document.querySelector('[phx-click="pin_extension"][phx-value-id="${id}"]');
      if (b) b.click();
      return !!b;
    })()`);
    await sleep(450);
  }
};

const PROBE = `(() => {
  const r = (el) => { if (!el) return null;
    if (el.offsetParent === null && getComputedStyle(el).position !== 'fixed') return null; // display:none
    const b = el.getBoundingClientRect();
    return { l: Math.round(b.left), r: Math.round(b.right), w: Math.round(b.width), h: Math.round(b.height) }; };
  const nav = document.querySelector('#nav-container');
  const header = document.querySelector('header');
  const tabs = [...(nav ? nav.querySelectorAll(':scope > button, :scope > div') : [])].map(el => ({
    label: (el.textContent || '').replace(/\\s+/g, ' ').trim().slice(0, 22),
    box: r(el),
  }));
  const pinnedBtn = [...document.querySelectorAll('button')].find(b => b.textContent.trim().startsWith('Pinned'));
  // the badge inside Overview/Extensions tabs, and the gap to its label
  const badges = [...document.querySelectorAll('#nav-container .rounded-full')]
    .filter(b => b.offsetParent !== null)
    .map(b => {
      const prev = b.previousElementSibling;
      return { text: b.textContent.trim(), gap: prev ? Math.round(b.getBoundingClientRect().left - prev.getBoundingClientRect().right) : null };
    });
  return {
    viewport: window.innerWidth,
    nav: nav ? { ...r(nav), scrollW: nav.scrollWidth, clientW: nav.clientWidth, clipped: nav.scrollWidth > nav.clientWidth + 1 } : null,
    header: r(header),
    tabs,
    pinnedBtn: r(pinnedBtn),
    badges,
    docScrollW: document.documentElement.scrollWidth,
  };
})()`;

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

for (const width of [375, 640, 768, 1024, 1440]) {
  await viewport(width);
  for (const { label, ids } of STATES) {
    await setPins(ids);
    await goto(`${BASE}/`);
    await sleep(700);
    const m = await js(PROBE);

    const problems = [];
    if (m.nav && m.nav.clipped)
      problems.push(`NAV CLIPPED (content ${m.nav.scrollW} > box ${m.nav.clientW})`);
    if (m.docScrollW > m.viewport + 1) problems.push(`PAGE OVERFLOWS X (${m.docScrollW} > ${m.viewport})`);
    if (m.pinnedBtn && m.pinnedBtn.r > m.viewport) problems.push("PINNED BUTTON OFF-SCREEN");
    for (const t of m.tabs) {
      if (!t.box) continue;
      if (t.box.r > m.viewport + 1) problems.push(`TAB OFF-SCREEN: "${t.label}" right=${t.box.r}`);
      if (t.box.l < -1) problems.push(`TAB OFF-LEFT: "${t.label}" left=${t.box.l}`);
    }
    for (let i = 1; i < m.tabs.length; i++) {
      const a = m.tabs[i - 1].box, b = m.tabs[i].box;
      if (a && b && b.l < a.r - 1) problems.push(`OVERLAP: "${m.tabs[i - 1].label}" / "${m.tabs[i].label}"`);
    }
    for (const b of m.badges) {
      if (b.gap !== null && b.gap < 2) problems.push(`BADGE CROWDED: "${b.text}" gap=${b.gap}px`);
    }

    console.log(
      `\n${width}px ${label}: nav=${m.nav ? `${m.nav.w}x${m.nav.h} content=${m.nav.scrollW}` : "none"} tabs=${m.tabs.length}`,
    );
    console.log("   " + m.tabs.map((t) => `${t.label || "-"}${t.box ? `[${t.box.l}..${t.box.r}]` : "[hidden]"}`).join("  "));
    if (m.badges.length) console.log("   badges:", m.badges.map((b) => `${b.text}(gap ${b.gap})`).join(" "));
    console.log(problems.length ? "   !! " + problems.join("; ") : "   ok");
  }
}

// dropdown placement at the narrowest width
for (const width of [375, 640]) {
  await viewport(width);
  await setPins(STATES[2].ids);
  await goto(`${BASE}/`);
  await sleep(700);
  const box = await js(`(() => {
    const btn = [...document.querySelectorAll('button')].find(b => b.textContent.trim().startsWith('Pinned'));
    if (!btn) return { error: 'no pinned button' };
    btn.click();
    return { clicked: true };
  })()`);
  await sleep(500);
  const menu = await js(`(() => {
    const m = document.querySelector('nav .absolute');
    if (!m) return null;
    const b = m.getBoundingClientRect();
    return { l: Math.round(b.left), r: Math.round(b.right), w: Math.round(b.width), viewport: window.innerWidth };
  })()`);
  console.log(`\nPinned dropdown @${width}px:`, JSON.stringify(box), JSON.stringify(menu),
    menu && menu.r > menu.viewport ? `  !! OFF-SCREEN BY ${menu.r - menu.viewport}px` : "  ok");
}

ws.close();
try { process.kill(-chrome.pid); } catch {}
process.exit(0);
