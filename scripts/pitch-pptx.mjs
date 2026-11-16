#!/usr/bin/env node
/**
 * Exoforge Pitch Deck -> Editable Native PowerPoint (.pptx) Exporter
 *
 * Converts all storyboard beats from ./pitch-storyboard.mjs into native
 * PowerPoint shapes, editable text boxes, syntax-highlighted code runs,
 * rounded persona portraits, crisp vector icon sprites, clickable external
 * reference hyperlinks, and speaker notes from ../docs/pitch/index.html.
 *
 * Output: /Users/alexcs/projects/exoforge/docs/pitch/exoforge-pitch.pptx
 */

import {
  readFileSync,
  writeFileSync,
  mkdirSync,
  rmSync,
  mkdtempSync,
} from "node:fs";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

import { BEATS, renderBeat } from "./pitch-storyboard.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, "..");
const HTML_PATH = join(REPO_ROOT, "docs/pitch/index.html");
const OUT_PPTX = join(REPO_ROOT, "docs/pitch/exoforge-pitch.pptx");
const OUT_PDF = join(REPO_ROOT, "docs/pitch/exoforge-pitch.pdf");
const RSVG_BIN = "/opt/homebrew/bin/rsvg-convert";
const SOFFICE_BIN = "/opt/homebrew/bin/soffice";
const ZIP_BIN = "/usr/bin/zip";

// Fonts bundled with LibreOffice and compatible across macOS/Windows/Linux
const FONT_SANS = "Liberation Sans";
const FONT_SYMBOL = "DejaVu Sans";
const FONT_MONO = "DejaVu Sans Mono";

// Standard Widescreen 16:9 (13.333" x 7.5") -> exact 9525 EMU per 1280x720 px
const SLIDE_CX = 12192000;
const SLIDE_CY = 6858000;
const EMU_PER_PX = 9525;

function emu(px) {
  return Math.round(px * EMU_PER_PX);
}

function pt100(px) {
  return Math.max(600, Math.round(px * 75));
}

function xmlEsc(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function decodeEntities(s) {
  return String(s ?? "")
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) =>
      String.fromCodePoint(parseInt(hex, 16))
    )
    .replace(/&#([0-9]+);/g, (_, dec) =>
      String.fromCodePoint(parseInt(dec, 10))
    )
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&");
}

function parseColor(raw, extraOpacity = 1) {
  if (!raw || raw === "none" || raw === "transparent") return null;
  const s = raw.trim();
  const baseOpacity = Number.isFinite(extraOpacity) ? extraOpacity : 1;

  if (s.startsWith("#")) {
    let hex = s.slice(1);
    if (hex.length === 3) {
      hex = hex
        .split("")
        .map((c) => c + c)
        .join("");
    }
    return {
      hex: hex.slice(0, 6).toUpperCase(),
      alpha: Math.max(0, Math.min(1, baseOpacity)),
    };
  }

  const rgbaMatch = s.match(
    /^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)$/i
  );
  if (rgbaMatch) {
    const hex = [rgbaMatch[1], rgbaMatch[2], rgbaMatch[3]]
      .map((n) => Math.max(0, Math.min(255, Number(n))).toString(16).padStart(2, "0"))
      .join("")
      .toUpperCase();
    const a = rgbaMatch[4] !== undefined ? Number(rgbaMatch[4]) : 1;
    return {
      hex,
      alpha: Math.max(0, Math.min(1, a * baseOpacity)),
    };
  }

  if (s.toLowerCase() === "white") return { hex: "FFFFFF", alpha: baseOpacity };
  if (s.toLowerCase() === "black") return { hex: "000000", alpha: baseOpacity };
  return null;
}

function renderSolidFill(color) {
  if (!color) return "<a:noFill/>";
  const alphaTag =
    color.alpha < 0.999
      ? `<a:alpha val="${Math.max(0, Math.min(100000, Math.round(color.alpha * 100000)))}"/>`
      : "";
  return `<a:solidFill><a:srgbClr val="${color.hex}">${alphaTag}</a:srgbClr></a:solidFill>`;
}

/**
 * Resolve verified external citation URLs for slide runs and bibliography entries.
 * Ordered carefully so URL-specific strings and multi-citation cards link cleanly.
 */
const LINK_RULES = [
  { re: /create\.unity\.com|Unity\s+(?:Gaming\s+)?Report/i, url: "https://create.unity.com/hubfs/Redistributable%20Assets/Unity_Gaming_Report_2024.pdf" },
  { re: /gdconf\.com|GDC\s+(?:State|2024|2025)|live-service/i, url: "https://reg.gdconf.com/state-of-game-industry-2024" },
  { re: /forbes\.com|Irdeto|anti-cheat|cheats/i, url: "https://www.forbes.com/sites/panosmourdoukoutas/2018/04/30/report-cheating-is-becoming-a-big-problem-in-online-gaming/" },
  { re: /stripe\.com|STRIPE\s*\('18\)|Stripe\s*(?:&amp;|&)\s*Harris/i, url: "https://stripe.com/files/reports/the-developer-coefficient.pdf" },
  { re: /gitlab\.com|GITLAB|GitLab/i, url: "https://about.gitlab.com/developer-survey/" },
  { re: /2009\.02440|Politowski|postmortems/i, url: "https://arxiv.org/abs/2009.02440" },
  { re: /2203\.04374|Tornhill|Code\s+Red/i, url: "https://arxiv.org/abs/2203.04374" },
  { re: /CHI2005|Mark\s*(?:,|et\s+al\.)/i, url: "https://ics.uci.edu/~gmark/CHI2005.pdf" },
  { re: /springer\.com|Parnin/i, url: "https://link.springer.com/article/10.1007/s11219-010-9104-9" },
  { re: /queue\.acm\.org|Noda\s+et\s+al\.|DevEx\s*\(|DevEx,\s*ACM\s+Queue/i, url: "https://queue.acm.org/detail.cfm?id=3595878" },
  { re: /sciencedirect|Leroy/i, url: "https://www.sciencedirect.com/science/article/abs/pii/S0749597809000399" },
  { re: /teamtopologies\.com|Team\s+Topologies|Skelton/i, url: "https://teamtopologies.com/book" },
];

function matchExternalUrl(text) {
  for (const rule of LINK_RULES) {
    if (rule.re.test(text)) return rule.url;
  }
  return null;
}

/**
 * Load synchronized speaker notes directly from docs/pitch/index.html.
 */
function loadBeatNotes() {
  const html = readFileSync(HTML_PATH, "utf8");
  const start = html.indexOf("const BEAT_META = [");
  const end = html.indexOf("];", start);
  if (start < 0 || end < 0) {
    throw new Error(`Could not locate BEAT_META in ${HTML_PATH}`);
  }
  const snippet = `${html.slice(start, end + 2)}\nBEAT_META;`;
  const beatMeta = vm.runInNewContext(snippet, Object.create(null));
  if (!Array.isArray(beatMeta) || beatMeta.length !== BEATS.length) {
    throw new Error(
      `Expected ${BEATS.length} BEAT_META entries, got ${beatMeta?.length}`
    );
  }
  return beatMeta.map((b, i) => ({
    ...b,
    slideIndex: BEATS[i] !== undefined ? BEATS[i].slide : b.slideIndex,
  }));
}

/**
 * Parse raw XML attributes string into a decoded dictionary.
 */
function parseAttrs(attrStr) {
  const attrs = {};
  const re = /([a-zA-Z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
  let m;
  while ((m = re.exec(attrStr)) !== null) {
    attrs[m[1]] = decodeEntities(m[2] !== undefined ? m[2] : m[3]);
  }
  return attrs;
}

/**
 * Balanced lightweight SVG/XML AST parser (preserves text whitespace cleanly).
 */
function parseSvgAst(xml) {
  const root = { tag: "__root__", attrs: {}, children: [] };
  const stack = [root];
  let i = 0;

  while (i < xml.length) {
    const lt = xml.indexOf("<", i);
    if (lt < 0) {
      const tail = xml.slice(i);
      if (tail) stack[stack.length - 1].children.push({ type: "text", text: decodeEntities(tail) });
      break;
    }

    if (lt > i) {
      const rawText = xml.slice(i, lt);
      const cur = stack[stack.length - 1];
      if (cur.tag === "text" || cur.tag === "tspan" || rawText.trim().length > 0) {
        cur.children.push({ type: "text", text: decodeEntities(rawText) });
      }
    }

    if (xml.startsWith("<!--", lt)) {
      const closeComment = xml.indexOf("-->", lt + 4);
      i = closeComment < 0 ? xml.length : closeComment + 3;
      continue;
    }

    const gt = xml.indexOf(">", lt + 1);
    if (gt < 0) throw new Error(`Unclosed tag near offset ${lt}`);
    const tagContent = xml.slice(lt + 1, gt).trim();
    i = gt + 1;

    if (tagContent.startsWith("/")) {
      const closeName = tagContent.slice(1).trim();
      const top = stack.pop();
      if (!top || top.tag !== closeName) {
        throw new Error(`Mismatched closing tag </${closeName}> (expected </${top?.tag}>)`);
      }
      continue;
    }

    const selfClosing = tagContent.endsWith("/");
    const inner = selfClosing ? tagContent.slice(0, -1).trim() : tagContent;
    const spaceIdx = inner.search(/\s/);
    const tagName = spaceIdx < 0 ? inner : inner.slice(0, spaceIdx);
    const attrStr = spaceIdx < 0 ? "" : inner.slice(spaceIdx + 1);

    const node = {
      tag: tagName,
      attrs: parseAttrs(attrStr),
      children: [],
    };
    stack[stack.length - 1].children.push(node);
    if (!selfClosing) {
      stack.push(node);
    }
  }

  return root.children.find((c) => c.tag === "svg");
}

function parseTransform(tf) {
  if (!tf) return { tx: 0, ty: 0, scale: null, rotate: null };
  let tx = 0;
  let ty = 0;
  let scale = null;
  let rotate = null;

  const tMatch = tf.match(/translate\(\s*([-\d.]+)(?:[\s,]+([-\d.]+))?\s*\)/);
  if (tMatch) {
    tx = Number(tMatch[1]) || 0;
    ty = tMatch[2] !== undefined ? Number(tMatch[2]) || 0 : 0;
  }
  const sMatch = tf.match(/scale\(\s*([-\d.]+)\s*\)/);
  if (sMatch) {
    scale = Number(sMatch[1]);
  }
  const rMatch = tf.match(
    /rotate\(\s*([-\d.]+)(?:[\s,]+([-\d.]+)[\s,]+([-\d.]+))?\s*\)/
  );
  if (rMatch) {
    rotate = {
      angle: Number(rMatch[1]),
      cx: rMatch[2] !== undefined ? Number(rMatch[2]) : null,
      cy: rMatch[3] !== undefined ? Number(rMatch[3]) : null,
    };
  }
  return { tx, ty, scale, rotate };
}

function serializeInnerElements(children) {
  return children
    .map((ch) => {
      if (ch.type === "text") return xmlEsc(ch.text);
      const attrs = Object.entries(ch.attrs)
        .map(([k, v]) => `${k}="${xmlEsc(v)}"`)
        .join(" ");
      const open = attrs ? `<${ch.tag} ${attrs}` : `<${ch.tag}`;
      if (ch.children.length === 0) return `${open}/>`;
      return `${open}>${serializeInnerElements(ch.children)}</${ch.tag}>`;
    })
    .join("");
}

/**
 * Parse <path d="M x y L x y ..."> points and optional Z closure.
 */
function parsePolylinePath(d) {
  const tokens = d.match(/[MLZmlz]|-?[\d.]+/g) || [];
  const points = [];
  let closed = false;
  let cmd = null;
  let idx = 0;

  while (idx < tokens.length) {
    const tok = tokens[idx];
    if (/^[MLZmlz]$/.test(tok)) {
      cmd = tok;
      if (cmd === "Z" || cmd === "z") closed = true;
      idx++;
      continue;
    }
    if (cmd === "M" || cmd === "L") {
      const x = Number(tokens[idx]);
      const y = Number(tokens[idx + 1]);
      points.push([x, y]);
      idx += 2;
      continue;
    }
    throw new Error(`Unsupported path command "${cmd}" in "${d}"`);
  }
  return { points, closed };
}

/**
 * Central asset store shared across all slides (portraits + icon PNG sprites).
 */
class MediaVault {
  constructor() {
    this.items = new Map(); // key -> { filename, buf }
    this.tmpDir = mkdtempSync(join(tmpdir(), "exo-pptx-icons-"));
    this.counter = 0;
  }

  registerPortrait(dataUri) {
    const b64 = dataUri.replace(/^data:image\/png;base64,/, "");
    const hash = createHash("sha1").update(b64).digest("hex").slice(0, 12);
    const key = `portrait_${hash}`;
    if (!this.items.has(key)) {
      this.counter++;
      this.items.set(key, {
        filename: `portrait_${hash}.png`,
        buf: Buffer.from(b64, "base64"),
      });
    }
    return this.items.get(key).filename;
  }

  registerIcon(iconNode, sizePx) {
    const inner = serializeInnerElements(iconNode.children);
    const groupAttrs = Object.entries(iconNode.attrs)
      .filter(([k]) => k !== "transform")
      .map(([k, v]) => `${k}="${xmlEsc(v)}"`)
      .join(" ");
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 24 24"><g ${groupAttrs}>${inner}</g></svg>`;
    const hash = createHash("sha1").update(svg).digest("hex").slice(0, 12);
    const key = `icon_${hash}`;
    if (!this.items.has(key)) {
      const svgPath = join(this.tmpDir, `${key}.svg`);
      const pngPath = join(this.tmpDir, `${key}.png`);
      writeFileSync(svgPath, svg);
      execFileSync(RSVG_BIN, ["-w", "96", "-h", "96", svgPath, "-o", pngPath]);
      this.items.set(key, {
        filename: `${key}.png`,
        buf: readFileSync(pngPath),
      });
    }
    return {
      filename: this.items.get(key).filename,
      sizePx,
    };
  }

  cleanup() {
    rmSync(this.tmpDir, { recursive: true, force: true });
  }
}

/**
 * Per-slide relationship & shape ID builder producing valid OpenXML shapes.
 */
class SlideBuilder {
  constructor(slideNum, mediaVault) {
    this.slideNum = slideNum;
    this.mediaVault = mediaVault;
    this.shapeId = 2; // id="1" reserved for group spTree
    this.shapes = [];
    this.relIdCounter = 1;
    this.rels = [];
    this.mediaRelByFile = new Map();
    this.linkRelByUrl = new Map();
    this.rects = [];

    // Relationship rId1: Slide Layout
    this.addRel(
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout",
      "../slideLayouts/slideLayout1.xml"
    );
    // Relationship rId2: Bidirectional Notes Slide
    this.addRel(
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide",
      `../notesSlides/notesSlide${slideNum}.xml`
    );
  }

  nextId() {
    return this.shapeId++;
  }

  addRel(type, target, targetMode = null) {
    const id = `rId${this.relIdCounter++}`;
    this.rels.push({ id, type, target, targetMode });
    return id;
  }

  ensureImageRel(filename) {
    if (!this.mediaRelByFile.has(filename)) {
      const rId = this.addRel(
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image",
        `../media/${filename}`
      );
      this.mediaRelByFile.set(filename, rId);
    }
    return this.mediaRelByFile.get(filename);
  }

  ensureLinkRel(url) {
    if (!this.linkRelByUrl.has(url)) {
      const rId = this.addRel(
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink",
        url,
        "External"
      );
      this.linkRelByUrl.set(url, rId);
    }
    return this.linkRelByUrl.get(url);
  }

  strokeXml(attrs, groupOpacity) {
    const strokeRaw = attrs.stroke;
    if (!strokeRaw || strokeRaw === "none") return "";
    const strokeOp =
      attrs["stroke-opacity"] !== undefined
        ? Number(attrs["stroke-opacity"])
        : 1;
    const strokeCol = parseColor(strokeRaw, groupOpacity * strokeOp);
    if (!strokeCol) return "";
    const wPx = attrs["stroke-width"] !== undefined ? Number(attrs["stroke-width"]) : 1;
    const wEmu = Math.max(emu(wPx), 6350);
    const cap = attrs["stroke-linecap"] === "round" ? ` cap="rnd"` : "";
    const dash = attrs["stroke-dasharray"] ? `<a:prstDash val="dash"/>` : "";
    return `<a:ln w="${wEmu}"${cap}>${renderSolidFill(strokeCol)}${dash}</a:ln>`;
  }

  addRect(attrs, dx, dy, groupOpacity) {
    const x = (Number(attrs.x) || 0) + dx;
    const y = (Number(attrs.y) || 0) + dy;
    const w = Number(attrs.width) || 0;
    const h = Number(attrs.height) || 0;
    if (w <= 0 || h <= 0) return;

    const rx = Number(attrs.rx) || 0;
    const fillRaw = attrs.fill !== undefined ? attrs.fill : "#000000";
    const fillOp =
      attrs["fill-opacity"] !== undefined ? Number(attrs["fill-opacity"]) : 1;
    const elemOp = attrs.opacity !== undefined ? Number(attrs.opacity) : 1;
    const effOpacity = groupOpacity * elemOp;
    if (effOpacity >= 0.5) {
      this.rects.push({ x, y, w, h });
    }
    const fillCol = parseColor(fillRaw, effOpacity * fillOp);

    let geomXml = `<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>`;
    if (rx > 0) {
      const adj = Math.min(50000, Math.round((rx / Math.min(w, h)) * 100000));
      geomXml = `<a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val ${adj}"/></a:avLst></a:prstGeom>`;
    }

    const lnXml = this.strokeXml(attrs, effOpacity);
    const id = this.nextId();
    this.shapes.push(`
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="${id}" name="Rect ${id}"/>
          <p:cNvSpPr/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="${emu(x)}" y="${emu(y)}"/><a:ext cx="${emu(w)}" cy="${emu(h)}"/></a:xfrm>
          ${geomXml}
          ${renderSolidFill(fillCol)}
          ${lnXml}
        </p:spPr>
      </p:sp>`);
  }

  addEllipse(node, dx, dy, groupOpacity) {
    const a = node.attrs;
    const cx = (Number(a.cx) || 0) + dx;
    const cy = (Number(a.cy) || 0) + dy;
    const rx = node.tag === "circle" ? Number(a.r) || 0 : Number(a.rx) || 0;
    const ry = node.tag === "circle" ? Number(a.r) || 0 : Number(a.ry) || 0;
    if (rx <= 0 || ry <= 0) return;

    const elemOp = a.opacity !== undefined ? Number(a.opacity) : 1;
    const effOp = groupOpacity * elemOp;
    const fillOp = a["fill-opacity"] !== undefined ? Number(a["fill-opacity"]) : 1;
    const fillCol = parseColor(a.fill !== undefined ? a.fill : "#000000", effOp * fillOp);
    const lnXml = this.strokeXml(a, effOp);

    const id = this.nextId();
    this.shapes.push(`
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="${id}" name="Ellipse ${id}"/>
          <p:cNvSpPr/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="${emu(cx - rx)}" y="${emu(cy - ry)}"/><a:ext cx="${emu(2 * rx)}" cy="${emu(2 * ry)}"/></a:xfrm>
          <a:prstGeom prst="ellipse"><a:avLst/></a:prstGeom>
          ${renderSolidFill(fillCol)}
          ${lnXml}
        </p:spPr>
      </p:sp>`);
  }

  addLine(attrs, dx, dy, groupOpacity) {
    const x1 = (Number(attrs.x1) || 0) + dx;
    const y1 = (Number(attrs.y1) || 0) + dy;
    const x2 = (Number(attrs.x2) || 0) + dx;
    const y2 = (Number(attrs.y2) || 0) + dy;
    const elemOp = attrs.opacity !== undefined ? Number(attrs.opacity) : 1;
    const effOp = groupOpacity * elemOp;
    const minX = Math.min(x1, x2);
    const minY = Math.min(y1, y2);
    const cx = emu(Math.abs(x2 - x1));
    const cy = emu(Math.abs(y2 - y1));
    const flipH = x2 < x1 ? ` flipH="1"` : "";
    const flipV = y2 < y1 ? ` flipV="1"` : "";
    const lnXml = this.strokeXml(attrs, effOp);

    const id = this.nextId();
    this.shapes.push(`
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="${id}" name="Line ${id}"/>
          <p:cNvSpPr/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm${flipH}${flipV}><a:off x="${emu(minX)}" y="${emu(minY)}"/><a:ext cx="${cx}" cy="${cy}"/></a:xfrm>
          <a:prstGeom prst="line"><a:avLst/></a:prstGeom>
          <a:noFill/>
          ${lnXml}
        </p:spPr>
      </p:sp>`);
  }

  addCustomGeomPoints(attrs, points, closed, dx, dy, groupOpacity, label) {
    if (points.length < 2) return;
    const xs = points.map(([x]) => x + dx);
    const ys = points.map(([, y]) => y + dy);
    const minX = Math.min(...xs);
    const maxX = Math.max(...xs);
    const minY = Math.min(...ys);
    const maxY = Math.max(...ys);
    const wPx = Math.max(maxX - minX, 1);
    const hPx = Math.max(maxY - minY, 1);
    const wEmu = emu(wPx);
    const hEmu = emu(hPx);

    const elemOp = attrs.opacity !== undefined ? Number(attrs.opacity) : 1;
    const effOp = groupOpacity * elemOp;
    const fillOp = attrs["fill-opacity"] !== undefined ? Number(attrs["fill-opacity"]) : 1;
    const fillCol = parseColor(attrs.fill, effOp * fillOp);
    const lnXml = this.strokeXml(attrs, effOp);

    const segs = points
      .map(([px, py], idx) => {
        const rx = emu(px + dx - minX);
        const ry = emu(py + dy - minY);
        return idx === 0
          ? `<a:moveTo><a:pt x="${rx}" y="${ry}"/></a:moveTo>`
          : `<a:lnTo><a:pt x="${rx}" y="${ry}"/></a:lnTo>`;
      })
      .join("");

    const id = this.nextId();
    this.shapes.push(`
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="${id}" name="${label} ${id}"/>
          <p:cNvSpPr/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="${emu(minX)}" y="${emu(minY)}"/><a:ext cx="${wEmu}" cy="${hEmu}"/></a:xfrm>
          <a:custGeom>
            <a:avLst/>
            <a:gdLst/>
            <a:ahLst/>
            <a:cxnLst/>
            <a:rect l="0" t="0" r="${wEmu}" b="${hEmu}"/>
            <a:pathLst>
              <a:path w="${wEmu}" h="${hEmu}">
                ${segs}
                ${closed ? "<a:close/>" : ""}
              </a:path>
            </a:pathLst>
          </a:custGeom>
          ${renderSolidFill(fillCol)}
          ${lnXml}
        </p:spPr>
      </p:sp>`);
  }

  addPicture(filename, x, y, w, h, rx = 0, opacity = 1, sliceSquareCrop = false, namePrefix = "Image") {
    const rId = this.ensureImageRel(filename);
    const id = this.nextId();

    let srcRect = `<a:srcRect/>`;
    if (sliceSquareCrop && Math.abs(w - h) > 0.5) {
      // Source portraits are 1024x1024 (1:1); match SVG preserveAspectRatio="xMidYMid slice"
      if (w > h) {
        const crop = Math.round(((1 - h / w) / 2) * 100000);
        srcRect = `<a:srcRect l="0" t="${crop}" r="0" b="${crop}"/>`;
      } else {
        const crop = Math.round(((1 - w / h) / 2) * 100000);
        srcRect = `<a:srcRect l="${crop}" t="0" r="${crop}" b="0"/>`;
      }
    }

    const alphaTag =
      opacity < 0.999
        ? `<a:alphaModFix amt="${Math.max(0, Math.min(100000, Math.round(opacity * 100000)))}"/>`
        : "";

    let geomXml = `<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>`;
    if (rx > 0) {
      const adj = Math.min(50000, Math.round((rx / Math.min(w, h)) * 100000));
      geomXml = `<a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val ${adj}"/></a:avLst></a:prstGeom>`;
    }

    this.shapes.push(`
      <p:pic>
        <p:nvPicPr>
          <p:cNvPr id="${id}" name="${xmlEsc(namePrefix)} ${id}"/>
          <p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr>
          <p:nvPr/>
        </p:nvPicPr>
        <p:blipFill>
          <a:blip r:embed="${rId}">${alphaTag}</a:blip>
          ${srcRect}
          <a:stretch><a:fillRect/></a:stretch>
        </p:blipFill>
        <p:spPr>
          <a:xfrm><a:off x="${emu(x)}" y="${emu(y)}"/><a:ext cx="${emu(w)}" cy="${emu(h)}"/></a:xfrm>
          ${geomXml}
        </p:spPr>
      </p:pic>`);
  }

  addText(node, dx, dy, groupOpacity) {
    const a = node.attrs;
    const baseFontSize = Number(a["font-size"]) || 12;
    const baseWeight = Number(a["font-weight"]) || 400;
    const baseFill = a.fill || "#f3f4f6";
    const isCode =
      a.class === "code" ||
      (a["font-family"] && a["font-family"].toLowerCase().includes("monospace"));
    const anchor = a["text-anchor"] || "start";
    const elemOp = a.opacity !== undefined ? Number(a.opacity) : 1;
    const effOp = groupOpacity * elemOp;

    const rawRuns = [];
    for (const ch of node.children) {
      if (ch.type === "text") {
        if (ch.text.length === 0) continue;
        rawRuns.push({
          text: ch.text,
          fill: baseFill,
          weight: baseWeight,
          fontSize: baseFontSize,
        });
      } else if (ch.tag === "tspan") {
        const innerText = ch.children
          .filter((n) => n.type === "text")
          .map((n) => n.text)
          .join("");
        if (innerText.length === 0) continue;
        rawRuns.push({
          text: innerText,
          fill: ch.attrs.fill || baseFill,
          weight:
            ch.attrs["font-weight"] !== undefined
              ? Number(ch.attrs["font-weight"])
              : baseWeight,
          fontSize:
            ch.attrs["font-size"] !== undefined
              ? Number(ch.attrs["font-size"])
              : baseFontSize,
        });
      }
    }
    if (rawRuns.length === 0) return;

    // Normalize leading/standalone whitespace runs so LibreOffice Impress never
    // measures standalone space runs with a fallback proportional serif font.
    const mergedRuns = [];
    let pendingLeadSpaces = "";
    for (const r of rawRuns) {
      if (mergedRuns.length === 0 && /^ +$/.test(r.text)) {
        pendingLeadSpaces += "\u00A0".repeat(r.text.length);
        continue;
      }
      const textWithLead = pendingLeadSpaces
        ? pendingLeadSpaces + r.text.replace(/^ +/, (m) => "\u00A0".repeat(m.length))
        : mergedRuns.length === 0
        ? r.text.replace(/^ +/, (m) => "\u00A0".repeat(m.length))
        : r.text;
      pendingLeadSpaces = "";
      if (mergedRuns.length > 0 && /^[ \u00A0]+$/.test(textWithLead)) {
        mergedRuns[mergedRuns.length - 1].text += isCode
          ? "\u00A0".repeat(textWithLead.length)
          : textWithLead;
      } else {
        mergedRuns.push({ ...r, text: textWithLead });
      }
    }
    const runs = mergedRuns.length > 0 ? mergedRuns : rawRuns;

    const fullText = runs.map((r) => r.text).join("");
    const charLen = fullText.length;
    const absX = (Number(a.x) || 0) + dx;
    const absY = (Number(a.y) || 0) + dy;
    const visualMidY = absY - baseFontSize * 0.35;
    let bh = Math.max(baseFontSize * 1.35, 14);
    let finalBy = visualMidY - bh / 2;
    const estW = Math.max(
      charLen * baseFontSize * (isCode ? 0.64 : 0.58) + 24,
      60
    );

    let bx = absX;
    let bw = estW;
    let algn = "l";
    if (anchor === "middle") {
      bw = estW;
      bx = absX - bw / 2;
      algn = "ctr";
    } else if (anchor === "end") {
      bw = estW;
      bx = absX - bw;
      algn = "r";
    } else {
      bw = Math.max(60, Math.min(Math.max(estW, 120), 1270 - absX));
      bx = absX;
      algn = "l";
    }

    const tf = parseTransform(a.transform);
    const isRotated90 = tf.rotate && Math.abs(tf.rotate.angle + 90) < 1;
    let rotAttr = "";
    if (isRotated90) {
      rotAttr = ` rot="-5400000"`;
      const cx = (tf.rotate.cx !== null ? tf.rotate.cx : Number(a.x) || 0) + dx;
      const cy = (tf.rotate.cy !== null ? tf.rotate.cy : Number(a.y) || 0) + dy;
      bx = cx - bw / 2;
      finalBy = cy - bh / 2;
    } else {
      // Snap single-line text vertically to its enclosing badge/pill/bar/table-row rect
      // so PowerPoint and LibreOffice center text identically inside boxes.
      let enclosingRect = null;
      let smallestArea = Infinity;
      for (const r of this.rects) {
        if (
          r.h >= baseFontSize + 2 &&
          r.h <= 44 &&
          r.w < 1200 &&
          absX >= r.x - 4 &&
          absX <= r.x + r.w + 4 &&
          visualMidY >= r.y &&
          visualMidY <= r.y + r.h
        ) {
          const isSmallPillOrBar = r.h <= 34;
          const isCenteredInBox =
            anchor === "middle" && Math.abs(visualMidY - (r.y + r.h / 2)) <= 6;
          if (isSmallPillOrBar || isCenteredInBox) {
            const area = r.w * r.h;
            if (area < smallestArea) {
              smallestArea = area;
              enclosingRect = r;
            }
          }
        }
      }
      if (enclosingRect) {
        bh = enclosingRect.h;
        finalBy = enclosingRect.y;
        if (
          anchor === "middle" &&
          Math.abs(absX - (enclosingRect.x + enclosingRect.w / 2)) <= 6 &&
          estW <= enclosingRect.w + 16
        ) {
          bx = enclosingRect.x;
          bw = enclosingRect.w;
        }
      }
    }

    const wholeTextUrl = matchExternalUrl(fullText);
    const runsXml = runs
      .map((r) => {
        const runColor = parseColor(r.fill, effOp) || { hex: "F3F4F6", alpha: effOp };
        const boldAttr = r.weight >= 600 ? ` b="1"` : "";
        const sz = pt100(r.fontSize);
        const runUrl =
          runs.length > 1
            ? matchExternalUrl(r.text) || (r.fill === "#ddd6fe" ? null : wholeTextUrl)
            : wholeTextUrl;
        const hlinkXml = runUrl
          ? `<a:hlinkClick r:id="${this.ensureLinkRel(runUrl)}"/>`
          : "";
        const runFont = isCode
          ? FONT_MONO
          : /[★↻✓✕→↓≥]/.test(r.text)
          ? FONT_SYMBOL
          : FONT_SANS;
        return `<a:r><a:rPr lang="pt-BR" sz="${sz}"${boldAttr} u="none" dirty="0">${renderSolidFill(
          runColor
        )}<a:latin typeface="${runFont}"/><a:ea typeface="${runFont}"/><a:cs typeface="${runFont}"/>${hlinkXml}</a:rPr><a:t xml:space="preserve">${xmlEsc(
          r.text
        )}</a:t></a:r>`;
      })
      .join("");

    const id = this.nextId();
    this.shapes.push(`
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="${id}" name="Text ${id}"/>
          <p:cNvSpPr txBox="1"/>
          <p:nvPr/>
        </p:nvSpPr>
        <p:spPr>
          <a:xfrm${rotAttr}><a:off x="${emu(bx)}" y="${emu(finalBy)}"/><a:ext cx="${emu(bw)}" cy="${emu(bh)}"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:noFill/>
        </p:spPr>
        <p:txBody>
          <a:bodyPr wrap="none" lIns="0" tIns="0" rIns="0" bIns="0" anchor="ctr"><a:noAutofit/></a:bodyPr>
          <a:lstStyle/>
          <a:p>
            <a:pPr algn="${algn}"/>
            ${runsXml}
            <a:endParaRPr lang="pt-BR" sz="${pt100(baseFontSize)}" dirty="0"/>
          </a:p>
        </p:txBody>
      </p:sp>`);
  }

  /**
   * Recursively traverse the parsed SVG AST and emit OpenXML nodes.
   */
  ingestNode(node, dx = 0, dy = 0, groupOpacity = 1) {
    if (!node || node.type === "text") return;
    if (node.tag === "defs" || node.tag === "style" || node.tag === "clipPath") {
      return;
    }

    if (node.tag === "svg") {
      for (const ch of node.children) {
        this.ingestNode(ch, dx, dy, groupOpacity);
      }
      return;
    }

    if (node.tag === "g") {
      const op =
        node.attrs.opacity !== undefined ? Number(node.attrs.opacity) : 1;
      const effOp = groupOpacity * op;
      if (effOp <= 0) return;

      const tf = parseTransform(node.attrs.transform);
      const nx = dx + tf.tx;
      const ny = dy + tf.ty;

      // Crisp geometric icon group (<g transform="translate(x,y) scale(s)">)
      if (tf.scale !== null) {
        const sizePx = Math.round(tf.scale * 24 * 100) / 100;
        const { filename } = this.mediaVault.registerIcon(node, sizePx);
        this.addPicture(filename, nx, ny, sizePx, sizePx, 0, effOp, false, "Icon");
        return;
      }

      // Portrait wrapper group (<g opacity><defs>clipPath</defs><rect><image><rect></g>)
      const imageChild = node.children.find((c) => c.tag === "image");
      if (imageChild) {
        const clipRect =
          node.children
            .find((c) => c.tag === "defs")
            ?.children.find((c) => c.tag === "clipPath")
            ?.children.find((c) => c.tag === "rect") ||
          node.children.find((c) => c.tag === "rect");
        const rx = Number(clipRect?.attrs?.rx) || 0;
        for (const ch of node.children) {
          if (ch.tag === "image") {
            const href = ch.attrs.href || ch.attrs["xlink:href"] || "";
            const filename = this.mediaVault.registerPortrait(href);
            const ix = (Number(ch.attrs.x) || 0) + nx;
            const iy = (Number(ch.attrs.y) || 0) + ny;
            const iw = Number(ch.attrs.width) || 0;
            const ih = Number(ch.attrs.height) || 0;
            this.addPicture(
              filename,
              ix,
              iy,
              iw,
              ih,
              rx,
              effOp,
              ch.attrs.preserveAspectRatio === "xMidYMid slice",
              "Portrait"
            );
          } else {
            this.ingestNode(ch, nx, ny, effOp);
          }
        }
        return;
      }

      for (const ch of node.children) {
        this.ingestNode(ch, nx, ny, effOp);
      }
      return;
    }

    if (node.tag === "rect") {
      // Skip full-bleed canvas background rect (already rendered in <p:bg>)
      const w = Number(node.attrs.width) || 0;
      const h = Number(node.attrs.height) || 0;
      const x = Number(node.attrs.x) || 0;
      const y = Number(node.attrs.y) || 0;
      if (dx === 0 && dy === 0 && x === 0 && y === 0 && w === 1280 && h === 720) {
        return;
      }
      this.addRect(node.attrs, dx, dy, groupOpacity);
      return;
    }

    if (node.tag === "circle" || node.tag === "ellipse") {
      this.addEllipse(node, dx, dy, groupOpacity);
      return;
    }

    if (node.tag === "line") {
      this.addLine(node.attrs, dx, dy, groupOpacity);
      return;
    }

    if (node.tag === "polygon") {
      const nums = (node.attrs.points || "").trim().split(/[\s,]+/).map(Number);
      const points = [];
      for (let k = 0; k + 1 < nums.length; k += 2) {
        points.push([nums[k], nums[k + 1]]);
      }
      this.addCustomGeomPoints(node.attrs, points, true, dx, dy, groupOpacity, "Polygon");
      return;
    }

    if (node.tag === "path") {
      const { points, closed } = parsePolylinePath(node.attrs.d || "");
      this.addCustomGeomPoints(node.attrs, points, closed, dx, dy, groupOpacity, "Path");
      return;
    }

    if (node.tag === "text") {
      this.addText(node, dx, dy, groupOpacity);
      return;
    }

    if (node.tag === "image") {
      const href = node.attrs.href || node.attrs["xlink:href"] || "";
      const filename = this.mediaVault.registerPortrait(href);
      this.addPicture(
        filename,
        (Number(node.attrs.x) || 0) + dx,
        (Number(node.attrs.y) || 0) + dy,
        Number(node.attrs.width) || 0,
        Number(node.attrs.height) || 0,
        0,
        groupOpacity,
        node.attrs.preserveAspectRatio === "xMidYMid slice",
        "Image"
      );
    }
  }

  toSlideXml() {
    return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:bg>
      <p:bgPr>
        <a:solidFill><a:srgbClr val="141417"/></a:solidFill>
        <a:effectLst/>
      </p:bgPr>
    </p:bg>
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="1" name=""/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      <p:grpSpPr>
        <a:xfrm>
          <a:off x="0" y="0"/><a:ext cx="0" cy="0"/>
          <a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/>
        </a:xfrm>
      </p:grpSpPr>
      ${this.shapes.join("")}
    </p:spTree>
  </p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sld>
`;
  }

  toRelsXml() {
    const items = this.rels
      .map((r) => {
        const mode = r.targetMode ? ` TargetMode="${r.targetMode}"` : "";
        return `<Relationship Id="${r.id}" Type="${r.type}" Target="${xmlEsc(r.target)}"${mode}/>`;
      })
      .join("\n  ");
    return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  ${items}
</Relationships>
`;
  }
}

function buildNotesSlideXml(beatInfo, beatIdx) {
  const headerLine = `[Etapa ${beatIdx + 1}/${BEATS.length} · Slide ${beatInfo.slideIndex + 1}/10] ${beatInfo.label}`;
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="1" name=""/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      <p:grpSpPr>
        <a:xfrm>
          <a:off x="0" y="0"/><a:ext cx="0" cy="0"/>
          <a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/>
        </a:xfrm>
      </p:grpSpPr>
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="2" name="Slide Image Placeholder 1"/>
          <p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr>
          <p:nvPr><p:ph type="sldImg"/></p:nvPr>
        </p:nvSpPr>
        <p:spPr/>
      </p:sp>
      <p:sp>
        <p:nvSpPr>
          <p:cNvPr id="3" name="Notes Placeholder 2"/>
          <p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>
          <p:nvPr><p:ph type="body" idx="1"/></p:nvPr>
        </p:nvSpPr>
        <p:spPr/>
        <p:txBody>
          <a:bodyPr/>
          <a:lstStyle/>
          <a:p>
            <a:r><a:rPr lang="pt-BR" b="1" dirty="0"/><a:t>${xmlEsc(headerLine)}</a:t></a:r>
            <a:endParaRPr lang="pt-BR" dirty="0"/>
          </a:p>
          <a:p>
            <a:r><a:rPr lang="pt-BR" dirty="0"/><a:t>${xmlEsc(beatInfo.notes)}</a:t></a:r>
            <a:endParaRPr lang="pt-BR" dirty="0"/>
          </a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:notes>
`;
}

function buildNotesSlideRelsXml(slideNum) {
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster" Target="../notesMasters/notesMaster1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="../slides/slide${slideNum}.xml"/>
</Relationships>
`;
}

function writePackageStaticFiles(pkgDir, slideCount) {
  const dirs = [
    "_rels",
    "docProps",
    "ppt/_rels",
    "ppt/theme",
    "ppt/slideMasters/_rels",
    "ppt/slideLayouts/_rels",
    "ppt/notesMasters/_rels",
    "ppt/slides/_rels",
    "ppt/notesSlides/_rels",
    "ppt/media",
  ];
  for (const d of dirs) {
    mkdirSync(join(pkgDir, d), { recursive: true });
  }

  const slideOverrides = Array.from({ length: slideCount }, (_, i) => {
    const n = i + 1;
    return `  <Override PartName="/ppt/slides/slide${n}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>\n  <Override PartName="/ppt/notesSlides/notesSlide${n}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"/>`;
  }).join("\n");

  writeFileSync(
    join(pkgDir, "[Content_Types].xml"),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="png" ContentType="image/png"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
  <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
  <Override PartName="/ppt/notesMasters/notesMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml"/>
  <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
${slideOverrides}
</Types>
`
  );

  writeFileSync(
    join(pkgDir, "_rels/.rels"),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
`
  );

  const nowIso = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  writeFileSync(
    join(pkgDir, "docProps/core.xml"),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>Exoforge — Pitch para Investidores (${BEATS.length} Etapas)</dc:title>
  <dc:creator>Exoforge</dc:creator>
  <dcterms:created xsi:type="dcterms:W3CDTF">${nowIso}</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">${nowIso}</dcterms:modified>
</cp:coreProperties>
`
  );

  writeFileSync(
    join(pkgDir, "docProps/app.xml"),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
  <Application>Exoforge Pitch Exporter</Application>
  <PresentationFormat>Widescreen</PresentationFormat>
  <Slides>${slideCount}</Slides>
  <Notes>${slideCount}</Notes>
</Properties>
`
  );

  const presRels = Array.from({ length: slideCount }, (_, i) => {
    const n = i + 1;
    return `  <Relationship Id="rId${i + 4}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${n}.xml"/>`;
  }).join("\n");

  writeFileSync(
    join(pkgDir, "ppt/_rels/presentation.xml.rels"),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster" Target="notesMasters/notesMaster1.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
${presRels}
</Relationships>
`
  );

  const sldIds = Array.from({ length: slideCount }, (_, i) => {
    return `    <p:sldId id="${256 + i}" r:id="rId${i + 4}"/>`;
  }).join("\n");

  writeFileSync(
    join(pkgDir, "ppt/presentation.xml"),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" saveSubsetFonts="1">
  <p:sldMasterIdLst>
    <p:sldMasterId id="2147483648" r:id="rId1"/>
  </p:sldMasterIdLst>
  <p:notesMasterIdLst>
    <p:notesMasterId r:id="rId2"/>
  </p:notesMasterIdLst>
  <p:sldIdLst>
${sldIds}
  </p:sldIdLst>
  <p:sldSz cx="${SLIDE_CX}" cy="${SLIDE_CY}"/>
  <p:notesSz cx="6858000" cy="9144000"/>
  <p:defaultTextStyle>
    <a:defPPr><a:defRPr lang="pt-BR"/></a:defPPr>
  </p:defaultTextStyle>
</p:presentation>
`
  );

  writeFileSync(
    join(pkgDir, "ppt/theme/theme1.xml"),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Exoforge Dark">
  <a:themeElements>
    <a:clrScheme name="Exoforge">
      <a:dk1><a:srgbClr val="141417"/></a:dk1>
      <a:lt1><a:srgbClr val="F3F4F6"/></a:lt1>
      <a:dk2><a:srgbClr val="1E1E24"/></a:dk2>
      <a:lt2><a:srgbClr val="9CA3AF"/></a:lt2>
      <a:accent1><a:srgbClr val="8B5CF6"/></a:accent1>
      <a:accent2><a:srgbClr val="10B981"/></a:accent2>
      <a:accent3><a:srgbClr val="38BDF8"/></a:accent3>
      <a:accent4><a:srgbClr val="FBBF24"/></a:accent4>
      <a:accent5><a:srgbClr val="EF4444"/></a:accent5>
      <a:accent6><a:srgbClr val="F97316"/></a:accent6>
      <a:hlink><a:srgbClr val="93C5FD"/></a:hlink>
      <a:folHlink><a:srgbClr val="DDD6FE"/></a:folHlink>
    </a:clrScheme>
    <a:fontScheme name="Exoforge">
      <a:majorFont><a:latin typeface="${FONT_SANS}"/><a:ea typeface="${FONT_SANS}"/><a:cs typeface="${FONT_SANS}"/></a:majorFont>
      <a:minorFont><a:latin typeface="${FONT_SANS}"/><a:ea typeface="${FONT_SANS}"/><a:cs typeface="${FONT_SANS}"/></a:minorFont>
    </a:fontScheme>
    <a:fmtScheme name="Exoforge">
      <a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>
      <a:lnStyleLst><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="25400"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>
      <a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>
      <a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst>
    </a:fmtScheme>
  </a:themeElements>
</a:theme>
`
  );

  writeFileSync(
    join(pkgDir, "ppt/slideMasters/slideMaster1.xml"),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:bg>
      <p:bgPr>
        <a:solidFill><a:srgbClr val="141417"/></a:solidFill>
        <a:effectLst/>
      </p:bgPr>
    </p:bg>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
    </p:spTree>
  </p:cSld>
  <p:clrMap bg1="dk1" tx1="lt1" bg2="dk2" tx2="lt2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
  <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
  <p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles>
</p:sldMaster>
`
  );

  writeFileSync(
    join(pkgDir, "ppt/slideMasters/_rels/slideMaster1.xml.rels"),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
</Relationships>
`
  );

  writeFileSync(
    join(pkgDir, "ppt/slideLayouts/slideLayout1.xml"),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1">
  <p:cSld name="Blank">
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
    </p:spTree>
  </p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sldLayout>
`
  );

  writeFileSync(
    join(pkgDir, "ppt/slideLayouts/_rels/slideLayout1.xml.rels"),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
</Relationships>
`
  );

  writeFileSync(
    join(pkgDir, "ppt/notesMasters/notesMaster1.xml"),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:notesMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
    </p:spTree>
  </p:cSld>
  <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
  <p:notesStyle/>
</p:notesMaster>
`
  );

  writeFileSync(
    join(pkgDir, "ppt/notesMasters/_rels/notesMaster1.xml.rels"),
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
</Relationships>
`
  );
}

function buildPptx() {
  const beatNotes = loadBeatNotes();
  const mediaVault = new MediaVault();
  const pkgDir = mkdtempSync(join(tmpdir(), "exo-pptx-pkg-"));

  try {
    writePackageStaticFiles(pkgDir, BEATS.length);

    let totalShapes = 0;
    const allExternalUrls = new Set();

    for (let i = 0; i < BEATS.length; i++) {
      const slideNum = i + 1;
      const svg = renderBeat(i, 1.0);
      const ast = parseSvgAst(svg);
      const builder = new SlideBuilder(slideNum, mediaVault);
      builder.ingestNode(ast, 0, 0, 1);

      totalShapes += builder.shapes.length;
      for (const u of builder.linkRelByUrl.keys()) {
        allExternalUrls.add(u);
      }

      writeFileSync(join(pkgDir, `ppt/slides/slide${slideNum}.xml`), builder.toSlideXml());
      writeFileSync(
        join(pkgDir, `ppt/slides/_rels/slide${slideNum}.xml.rels`),
        builder.toRelsXml()
      );
      writeFileSync(
        join(pkgDir, `ppt/notesSlides/notesSlide${slideNum}.xml`),
        buildNotesSlideXml(beatNotes[i], i)
      );
      writeFileSync(
        join(pkgDir, `ppt/notesSlides/_rels/notesSlide${slideNum}.xml.rels`),
        buildNotesSlideRelsXml(slideNum)
      );
    }

    for (const { filename, buf } of mediaVault.items.values()) {
      writeFileSync(join(pkgDir, `ppt/media/${filename}`), buf);
    }

    rmSync(OUT_PPTX, { force: true });
    rmSync(OUT_PDF, { force: true });
    execFileSync(ZIP_BIN, ["-q", "-X", "-r", OUT_PPTX, "."], { cwd: pkgDir });

    const loProfileDir = mkdtempSync(join(tmpdir(), "exo-lo-profile-"));
    try {
      execFileSync(
        SOFFICE_BIN,
        [
          `-env:UserInstallation=file://${loProfileDir}`,
          "--headless",
          "--convert-to",
          "pdf",
          "--outdir",
          dirname(OUT_PDF),
          OUT_PPTX,
        ],
        { stdio: ["ignore", "pipe", "pipe"] }
      );
    } finally {
      rmSync(loProfileDir, { recursive: true, force: true });
    }

    const pptxBytes = readFileSync(OUT_PPTX).length;
    const pdfBytes = readFileSync(OUT_PDF).length;
    console.log(
      JSON.stringify(
        {
          outputPptx: OUT_PPTX,
          pptxBytes,
          outputPdf: OUT_PDF,
          pdfBytes,
          slides: BEATS.length,
          notesSlides: beatNotes.length,
          shapesAndPics: totalShapes,
          mediaAssets: mediaVault.items.size,
          uniqueExternalLinks: allExternalUrls.size,
        },
        null,
        2
      )
    );
  } finally {
    mediaVault.cleanup();
    rmSync(pkgDir, { recursive: true, force: true });
  }
}

buildPptx();
