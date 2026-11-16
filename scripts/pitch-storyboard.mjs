// Storyboard SVG Renderer for Exoforge Concrete Investor Pitch (10 Slides / 26 Beats)
// Renders crisp 1280x720 SVG frames in Brazilian Portuguese (pt-BR) with embedded persona portraits.

import { readFileSync } from "node:fs";

function loadPngDataUri(filename) {
  const buf = readFileSync(new URL(`../docs/pitch/assets/${filename}`, import.meta.url));
  return `data:image/png;base64,${buf.toString("base64")}`;
}

const IMG_FLOW = loadPngDataUri("persona-flow.png");
const IMG_OVERWHELMED = loadPngDataUri("persona-overwhelmed.png");
const IMG_SHIPPING = loadPngDataUri("persona-shipping.png");

export function esc(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

export function easeOutCubic(t) {
  return 1 - Math.pow(1 - Math.max(0, Math.min(1, t)), 3);
}

/**
 * Vertically center single-line SVG text inside a pill/bar rect.
 */
function pillTextY(y, h, fontSize) {
  return Math.round((y + h / 2 + fontSize * 0.36) * 10) / 10;
}

export const BEATS = [
  // Slide 0: 2 beats (steps 0, 1) -> Slide 1
  { beat: 0, slide: 0, step: 0, name: "Slide 1: ATO I · O Pedido do Game Design (Fluxograma)" },
  { beat: 1, slide: 0, step: 1, name: "Slide 1: ATO I · Fluxo Familiar na Unity & C#" },

  // Slide 1: 3 beats (steps 0, 1, 2) -> Slide 2
  { beat: 2, slide: 1, step: 0, name: "Slide 2: ATO I · Regra do Jogo (1. Jogador Clica Comprar)" },
  { beat: 3, slide: 1, step: 1, name: "Slide 2: ATO I · Regra do Jogo (2. Saldo & Fronteira do Servidor)" },
  { beat: 4, slide: 1, step: 2, name: "Slide 2: ATO I · Regra do Jogo (3. Entrega & Servidor vs Cliente)" },

  // Slide 2: 5 beats (steps 0, 1, 2, 3, 4) -> Slide 3
  { beat: 5, slide: 2, step: 0, name: "Slide 3: ATO II · Onde o Tempo Vaza (Sobrecarga de Infra)" },
  { beat: 6, slide: 2, step: 1, name: "Slide 3: ATO II · Papel 1 · DBA (PostgreSQL · SQL)" },
  { beat: 7, slide: 2, step: 2, name: "Slide 3: ATO II · Papel 2 · Backend (REST · HTTP · JSON)" },
  { beat: 8, slide: 2, step: 3, name: "Slide 3: ATO II · Papel 3 · Segurança (Anti-Cheat · Auth)" },
  { beat: 9, slide: 2, step: 4, name: "Slide 3: ATO II · Papel 4 · DevOps & Nuvem (Containers)" },

  // Slide 3: 1 beat (step 0) -> Slide 4
  { beat: 10, slide: 3, step: 0, name: "Slide 4: ATO II · O Custo Real (Contexto de Indústria & Estudo)" },

  // Slide 4 (Unity Inteira + New Extension): 1 beat (step 0) -> Slide 5
  { beat: 11, slide: 4, step: 0, name: "Slide 5: ATO III · Unity Editor · Ênfase em + New Extension" },

  // Slide 5 (Popup Create New Extension): 1 beat (step 0) -> Slide 6
  { beat: 12, slide: 5, step: 0, name: "Slide 6: ATO III · Popup Create New Extension & Template" },

  // Slide 6 (Código C# 9): 6 beats (steps 0, 1, 2, 3, 4, 5) -> Slide 7
  { beat: 13, slide: 6, step: 0, name: "Slide 7: ATO III · LojaDeItens.cs (21 Linhas em C# 9)" },
  { beat: 14, slide: 6, step: 1, name: "Slide 7: ATO III · [ExoResource] · Elimina Papel DBA" },
  { beat: 15, slide: 6, step: 2, name: "Slide 7: ATO III · [ExoAction] · Elimina Papel Backend" },
  { beat: 16, slide: 6, step: 3, name: "Slide 7: ATO III · Scope = \"player\" · Elimina Segurança" },
  { beat: 17, slide: 6, step: 4, name: "Slide 7: ATO III · [ExoService] · Elimina Papel DevOps" },
  { beat: 18, slide: 6, step: 5, name: "Slide 7: ATO III · Core Gameplay em C# 9 (Unity)" },

  // Slide 7 (Operação Gerenciada): 4 beats (steps 0, 1, 2, 3) -> Slide 8
  { beat: 19, slide: 7, step: 0, name: "Slide 8: ATO III · Producer Studio (Painel Ao Vivo)" },
  { beat: 20, slide: 7, step: 1, name: "Slide 8: ATO III · Tabela de Logs em Fluxo & Replay" },
  { beat: 21, slide: 7, step: 2, name: "Slide 8: ATO III · Grafo de Escalabilidade Automática" },
  { beat: 22, slide: 7, step: 3, name: "Slide 8: ATO III · Upload < 1s & Zero Tempo Fora do Ar" },

  // Slide 8 (Impacto no Negócio): 2 beats (steps 0, 1) -> Slide 9
  { beat: 23, slide: 8, step: 0, name: "Slide 9: ATO III · Impacto no Negócio (Placar Executivo)" },
  { beat: 24, slide: 8, step: 1, name: "Slide 9: ATO III · Visão Final (Você descreve a sua ideia)" },

  // Slide 9 (Apêndice): 1 beat (step 0) -> Slide 10
  { beat: 25, slide: 9, step: 0, name: "Slide 10: Apêndice · 10 Fontes Verificáveis" },
];

function renderPortrait(id, href, x, y, w, h, r, strokeColor = "#8b5cf6", opacity = 1) {
  return `
  <g opacity="${opacity}">
    <defs>
      <clipPath id="${id}">
        <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" ry="${r}"/>
      </clipPath>
    </defs>
    <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" ry="${r}" fill="#18181d"/>
    <image href="${href}" x="${x}" y="${y}" width="${w}" height="${h}" clip-path="url(#${id})" preserveAspectRatio="xMidYMid slice"/>
    <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" ry="${r}" fill="none" stroke="${strokeColor}" stroke-width="2"/>
  </g>`;
}

function renderHeader(actText, titleText, stepText) {
  return `
  <!-- Header -->
  <text x="50" y="46" font-size="12" font-weight="700" fill="#8b5cf6" letter-spacing="1.5">${esc(actText)}</text>
  <text x="50" y="76" font-size="22" font-weight="700" fill="#f3f4f6">${esc(titleText)}</text>
  <rect x="1080" y="42" width="150" height="30" rx="15" fill="#1e1e24" stroke="#2e2e38"/>
  <text x="1155" y="${pillTextY(42, 30, 12)}" font-size="12" font-weight="600" fill="#9ca3af" text-anchor="middle">${esc(stepText)}</text>
  <line x1="50" y1="96" x2="1230" y2="96" stroke="#24242c" stroke-width="1"/>
`;
}

// Crisp inline geometric icons (no font or emoji dependencies)
function iconGamepad(x, y, size = 20, color = "#8b5cf6") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <rect x="2" y="6" width="20" height="12" rx="4"/>
    <line x1="6" y1="12" x2="10" y2="12"/>
    <line x1="8" y1="10" x2="8" y2="14"/>
    <circle cx="15" cy="11" r="1" fill="${color}"/>
    <circle cx="18" cy="13" r="1" fill="${color}"/>
  </g>`;
}

function iconServer(x, y, size = 20, color = "#38bdf8") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <rect x="2" y="3" width="20" height="5" rx="2"/>
    <rect x="2" y="10" width="20" height="5" rx="2"/>
    <rect x="2" y="17" width="20" height="5" rx="2"/>
    <circle cx="6" cy="5.5" r="1" fill="${color}"/>
    <circle cx="6" cy="12.5" r="1" fill="${color}"/>
    <circle cx="6" cy="19.5" r="1" fill="${color}"/>
  </g>`;
}

function iconDatabase(x, y, size = 20, color = "#fbbf24") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <ellipse cx="12" cy="5" rx="9" ry="3"/>
    <path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/>
    <path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/>
  </g>`;
}

function iconShield(x, y, size = 20, color = "#ef4444") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
  </g>`;
}

function iconCloud(x, y, size = 20, color = "#f97316") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <path d="M18 10h-1.26A8 8 0 1 0 9 20h9a5 5 0 0 0 0-10z"/>
  </g>`;
}

function iconBolt(x, y, size = 20, color = "#10b981") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="${color}">
    <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>
  </g>`;
}

function iconCheck(x, y, size = 20, color = "#10b981") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <polyline points="20 6 9 17 4 12"/>
  </g>`;
}

function iconAlert(x, y, size = 20, color = "#ef4444") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/>
    <line x1="12" y1="9" x2="12" y2="13"/>
    <circle cx="12" cy="17" r="0.75" fill="${color}"/>
  </g>`;
}

function iconClock(x, y, size = 20, color = "#ef4444") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <circle cx="12" cy="12" r="10"/>
    <polyline points="12 6 12 12 16 14"/>
  </g>`;
}

function iconUsers(x, y, size = 20, color = "#8b5cf6") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/>
    <circle cx="9" cy="7" r="4"/>
    <path d="M22 21v-2a4 4 0 0 0-3-3.87"/>
    <path d="M16 3.13a4 4 0 0 1 0 7.75"/>
  </g>`;
}

function iconReplay(x, y, size = 20, color = "#10b981") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/>
    <path d="M3 3v5h5"/>
  </g>`;
}

function iconRocket(x, y, size = 20, color = "#10b981") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <path d="M4.5 16.5c-1.5 1.26-2 5-2 5s3.74-.5 5-2c.71-.84.7-2.13-.09-2.91a2.18 2.18 0 0 0-2.91-.09z"/>
    <path d="m12 15-3-3a22 22 0 0 1 2-3.95A12.88 12.88 0 0 1 22 2c0 2.72-.78 7.5-6 11a22.35 22.35 0 0 1-4 2z"/>
    <path d="M9 12H4s.55-3.03 2-4.5c1.62-1.63 5-2.5 5-2.5"/>
    <path d="M12 15v5s3.03-.55 4.5-2c1.63-1.62 2.5-5 2.5-5"/>
  </g>`;
}

function iconSword(x, y, size = 24, color = "#fbbf24") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <!-- Blade -->
    <path d="M12 2 L14.5 6 L14 14 L12 15 L10 14 L9.5 6 Z" fill="${color}" fill-opacity="0.25" stroke="${color}" stroke-width="1.5"/>
    <line x1="12" y1="4" x2="12" y2="13" stroke="${color}" stroke-width="1"/>
    <!-- Guard -->
    <path d="M6 14.5 C8 13.5 16 13.5 18 14.5" stroke="${color}" stroke-width="2"/>
    <circle cx="6" cy="14.5" r="1" fill="${color}"/>
    <circle cx="18" cy="14.5" r="1" fill="${color}"/>
    <!-- Grip & Pommel -->
    <line x1="12" y1="15" x2="12" y2="20" stroke="${color}" stroke-width="2"/>
    <circle cx="12" cy="21.5" r="1.5" fill="${color}"/>
  </g>`;
}

function iconFolder(x, y, size = 14, color = "#9ca3af") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/>
  </g>`;
}

function iconFileCode(x, y, size = 14, color = "#7dd3fc") {
  const s = size / 24;
  return `<g transform="translate(${x}, ${y}) scale(${s})" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
    <polyline points="14 2 14 8 20 8"/>
    <polyline points="10 13 8 15 10 17"/>
    <polyline points="14 13 16 15 14 17"/>
  </g>`;
}

// ==========================================
// SLIDE 0: O Pedido do Game Design (2 Beats)
// ==========================================
function renderSlide0(step, t) {
  const e = easeOutCubic(t);
  const cardOpacity = step === 0 ? 0 : Math.max(0, Math.min(1, e));
  const cardY = step === 0 ? 390 : Math.round(390 - 24 * e);

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="720" viewBox="0 0 1280 720">
  <defs>
    <style>
      text { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif; }
    </style>
  </defs>
  <rect width="1280" height="720" fill="#141417"/>
  ${renderHeader("ATO I · O PEDIDO DO DESIGN", "A Ilusão do Offline: Uma feature simples que deveria levar 2 horas.", `Etapa ${step + 1} de 2`)}

  <!-- Left: Portrait Card Lucas Flow (x=50..500, w=450) -->
  ${renderPortrait("p_s0_flow", IMG_FLOW, 50, 114, 450, 392, 12, "#8b5cf6")}

  <!-- Left: Persona Info Box (y=522..684, h=162) -->
  <rect x="50" y="522" width="450" height="162" rx="12" fill="#1e1e24" stroke="#8b5cf6" stroke-width="1.5"/>
  ${iconGamepad(72, 548, 24, "#a78bfa")}
  <text x="108" y="560" font-size="16.5" font-weight="700" fill="#f3f4f6">Lucas · Dev de Gameplay</text>
  <text x="108" y="584" font-size="13" fill="#9ca3af">Time indie de 8 pessoas (sem infra) · Foco em gameplay</text>
  <text x="108" y="614" font-size="12.5" fill="#9ca3af">Contratado para desenhar mecânicas e diversão.</text>
  <rect x="336" y="542" width="144" height="28" rx="14" fill="rgba(16, 185, 129, 0.15)" stroke="#10b981"/>
  <text x="408" y="${pillTextY(542, 28, 11)}" font-size="11" font-weight="700" fill="#34d399" text-anchor="middle">Foco no Jogo</text>

  <!-- Right Top: Mission Card (x=526..1230, w=704, y=114..350, h=236) -->
  <rect x="526" y="114" width="704" height="236" rx="12" fill="#1e1e24" stroke="#38bdf8" stroke-width="1.5"/>
  <rect x="551" y="132" width="180" height="26" rx="13" fill="rgba(56, 189, 248, 0.15)" stroke="#38bdf8"/>
  <text x="641" y="${pillTextY(132, 26, 10.5)}" font-size="10.5" font-weight="700" fill="#38bdf8" text-anchor="middle">PEDIDO DO GAME DESIGN</text>

  <rect x="1065" y="132" width="140" height="26" rx="13" fill="rgba(16, 185, 129, 0.15)" stroke="#10b981"/>
  <text x="1135" y="${pillTextY(132, 26, 10.5)}" font-size="10.5" font-weight="700" fill="#34d399" text-anchor="middle">Meta: ~2h em C#</text>

  <text x="551" y="180" font-size="18.5" font-weight="700" fill="#f3f4f6">Comprar Espada Lendária · 500 Ouro</text>

  <!-- Top Flowchart: 3 Horizontal Nodes (y=194..272, h=78) -->
  <!-- Node 1 -->
  <rect x="551" y="194" width="198" height="78" rx="8" fill="#18181d" stroke="#38bdf8" stroke-width="1.5"/>
  <rect x="561" y="202" width="68" height="18" rx="4" fill="rgba(56, 189, 248, 0.15)" stroke="#38bdf8"/>
  <text x="595" y="${pillTextY(202, 18, 9)}" font-size="9" font-weight="700" fill="#38bdf8" text-anchor="middle">PASSO 1</text>
  <text x="561" y="238" font-size="13" font-weight="700" fill="#f3f4f6">Validar Saldo</text>
  <text x="561" y="258" font-size="11" fill="#9ca3af">Tem 500 Ouro?</text>

  <!-- Arrow 1 -> 2 -->
  <line x1="755" y1="233" x2="773" y2="233" stroke="#38bdf8" stroke-width="2.5"/>
  <polygon points="771,228 779,233 771,238" fill="#38bdf8"/>

  <!-- Node 2 -->
  <rect x="779" y="194" width="198" height="78" rx="8" fill="#18181d" stroke="#38bdf8" stroke-width="1.5"/>
  <rect x="789" y="202" width="68" height="18" rx="4" fill="rgba(56, 189, 248, 0.15)" stroke="#38bdf8"/>
  <text x="823" y="${pillTextY(202, 18, 9)}" font-size="9" font-weight="700" fill="#38bdf8" text-anchor="middle">PASSO 2</text>
  <text x="789" y="238" font-size="13" font-weight="700" fill="#f3f4f6">Descontar &amp; Entregar</text>
  <text x="789" y="258" font-size="11" fill="#9ca3af">−500 Ouro + Espada</text>

  <!-- Arrow 2 -> 3 -->
  <line x1="983" y1="233" x2="1001" y2="233" stroke="#38bdf8" stroke-width="2.5"/>
  <polygon points="999,228 1007,233 999,238" fill="#38bdf8"/>

  <!-- Node 3 -->
  <rect x="1007" y="194" width="198" height="78" rx="8" fill="#18181d" stroke="#38bdf8" stroke-width="1.5"/>
  <rect x="1017" y="202" width="68" height="18" rx="4" fill="rgba(56, 189, 248, 0.15)" stroke="#38bdf8"/>
  <text x="1051" y="${pillTextY(202, 18, 9)}" font-size="9" font-weight="700" fill="#38bdf8" text-anchor="middle">PASSO 3</text>
  <text x="1017" y="238" font-size="13" font-weight="700" fill="#f3f4f6">Notificar Jogador</text>
  <text x="1017" y="258" font-size="11" fill="#9ca3af">Atualiza a loja</text>

  <!-- Rodapé enxuto (y=302..334) -->
  <rect x="551" y="302" width="654" height="32" rx="6" fill="#141417" stroke="#2e2e38"/>
  ${iconCheck(565, 310, 16, "#10b981")}
  <text x="590" y="${pillTextY(302, 32, 11)}" font-size="11" font-weight="600" fill="#9ca3af">No cliente local, roda perfeitamente em 2 horas.</text>

  <!-- Right Bottom: Card Direito Inferior (Reveals on Beat 1 / y=366..684, h=318) -->
  ${cardOpacity > 0 ? `
  <g transform="translate(526, ${cardY})" opacity="${cardOpacity}">
    <rect width="704" height="318" rx="12" fill="#1e1e24" stroke="#10b981" stroke-width="1.5"/>
    <text x="25" y="38" font-size="12.5" font-weight="800" fill="#34d399" letter-spacing="0.5">FLUXO FAMILIAR NA UNITY (SEM SERVIDORES)</text>

    <!-- 3 nós horizontais conectados por setas (y=76..194, h=118) -->
    <!-- Nó 1 -->
    <rect x="25" y="76" width="198" height="118" rx="8" fill="#18181d" stroke="#2e2e38"/>
    ${iconGamepad(37, 90, 20, "#34d399")}
    <text x="65" y="104" font-size="12" font-weight="700" fill="#34d399">1. Cena na Unity</text>
    <text x="37" y="136" font-size="11" fill="#cbd5e1">UI e botão &quot;Comprar&quot;</text>
    <text x="37" y="156" font-size="11" fill="#cbd5e1">já montados no Editor</text>

    <!-- Seta 1 -> 2 -->
    <line x1="227" y1="135" x2="247" y2="135" stroke="#10b981" stroke-width="2.5"/>
    <polygon points="245,130 253,135 245,140" fill="#10b981"/>

    <!-- Nó 2 -->
    <rect x="253" y="76" width="198" height="118" rx="8" fill="#18181d" stroke="#2e2e38"/>
    ${iconBolt(265, 90, 20, "#34d399")}
    <text x="293" y="104" font-size="12" font-weight="700" fill="#34d399">2. C# Conhecido</text>
    <text x="265" y="136" font-size="11" fill="#cbd5e1">Dados simples do jogador</text>
    <text x="265" y="156" font-size="11" fill="#cbd5e1">e lógica direta em C# 9</text>

    <!-- Seta 2 -> 3 -->
    <line x1="455" y1="135" x2="475" y2="135" stroke="#10b981" stroke-width="2.5"/>
    <polygon points="473,130 481,135 473,140" fill="#10b981"/>

    <!-- Nó 3 -->
    <rect x="481" y="76" width="198" height="118" rx="8" fill="#18181d" stroke="#2e2e38"/>
    ${iconCheck(493, 90, 20, "#34d399")}
    <text x="521" y="104" font-size="12" font-weight="700" fill="#34d399">3. Roda Local</text>
    <text x="493" y="136" font-size="11" fill="#cbd5e1">Testado na hora</text>
    <text x="493" y="156" font-size="11" fill="#cbd5e1">em 1 tarde (~2h)</text>

    <!-- Faixa de gancho inferior (y=266..308, h=42) -->
    <rect x="25" y="266" width="654" height="42" rx="8" fill="#18181d" stroke="#f59e0b" stroke-opacity="0.4"/>
    ${iconAlert(38, 277, 20, "#fbbf24")}
    <text x="68" y="${pillTextY(266, 42, 11.5)}" font-size="11.5" font-weight="600" fill="#fde68a">Mas o jogo é multiplayer: para monetizar sem trapaças, a regra precisa rodar no servidor.</text>
  </g>` : ""}
</svg>`;
}

// ==========================================
// SLIDE 1: A Regra do Jogo (3 Beats)
// ==========================================
function renderSlide1(step, t) {
  const e = easeOutCubic(t);
  const alphaStep1 = step >= 1 ? (step === 1 ? e : 1) : 0;
  const alphaStep2 = step >= 2 ? (step === 2 ? e : 1) : 0;

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="720" viewBox="0 0 1280 720">
  <defs>
    <style>
      text { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif; }
    </style>
  </defs>
  <rect width="1280" height="720" fill="#141417"/>
  ${renderHeader("ATO I · A REGRA DO JOGO", "A Lógica Essencial: No Editor, a compra cabe em 3 passos.", `Etapa ${step + 1} de 3`)}

  <!-- Left: Portrait Card Lucas Shipping -->
  ${renderPortrait("p_s1_shipping", IMG_SHIPPING, 50, 114, 370, 392, 12, "#10b981")}

  <!-- Left: Compact Info Card (y=522..684, h=162) -->
  <rect x="50" y="522" width="370" height="162" rx="12" fill="#1e1e24" stroke="#10b981" stroke-width="2"/>
  <rect x="70" y="538" width="204" height="24" rx="12" fill="rgba(16, 185, 129, 0.15)" stroke="#10b981"/>
  <text x="172" y="${pillTextY(538, 24, 10.5)}" font-size="10.5" font-weight="700" fill="#34d399" text-anchor="middle">Unity &amp; C# · Zona Criativa</text>

  <text x="70" y="586" font-size="17" font-weight="700" fill="#f3f4f6">O Trabalho Real do Estúdio</text>
  <text x="70" y="608" font-size="11.5" fill="#9ca3af">Apenas a lógica que gera diversão e receita.</text>
  <text x="70" y="630" font-size="9.5" font-weight="600" fill="#ddd6fe">DevEx (ACM Queue, 2023): fluxo contínuo eleva entregas.</text>

  <rect x="70" y="646" width="154" height="24" rx="12" fill="#262630" stroke="#10b981"/>
  <text x="147" y="${pillTextY(646, 24, 10.5)}" font-size="10.5" font-weight="700" fill="#34d399" text-anchor="middle">Estado de Fluxo</text>

  <!-- Right: Spacious Flowchart Canvas (x=446..1230, w=784) -->
  <rect x="446" y="114" width="784" height="570" rx="12" fill="#18181d" stroke="#2e2e38" stroke-width="1.5"/>

  <!-- Flowchart Header -->
  <rect x="466" y="130" width="220" height="24" rx="12" fill="rgba(139, 92, 246, 0.18)" stroke="#8b5cf6"/>
  <text x="576" y="${pillTextY(130, 24, 10.5)}" font-size="10.5" font-weight="700" fill="#ddd6fe" text-anchor="middle">REGRA DE NEGÓCIO (GAMEPLAY)</text>
  <text x="702" y="${pillTextY(130, 24, 13.5)}" font-size="13.5" font-weight="700" fill="#f3f4f6">Loja de Itens · Compra em Tempo Real</text>
  <text x="1208" y="${pillTextY(130, 24, 12)}" font-size="12" font-weight="700" fill="#34d399" text-anchor="end">Regra Pura</text>

  <!-- NODE 1: Entrada (Beat 2 / Step 0) — center x = 785 -->
  <rect x="610" y="190" width="350" height="70" rx="10" fill="#262630" stroke="#8b5cf6" stroke-width="2"/>
  <rect x="626" y="198" width="76" height="20" rx="10" fill="rgba(139, 92, 246, 0.15)" stroke="#8b5cf6"/>
  <text x="664" y="${pillTextY(198, 20, 9.5)}" font-size="9.5" font-weight="700" fill="#ddd6fe" text-anchor="middle">ENTRADA</text>
  <rect x="836" y="198" width="110" height="20" rx="10" fill="rgba(139, 92, 246, 0.2)" stroke="#8b5cf6"/>
  <text x="891" y="${pillTextY(198, 20, 9.5)}" font-size="9.5" font-weight="700" fill="#ddd6fe" text-anchor="middle">Cliente (Unity)</text>
  <text x="785" y="234" font-size="16" font-weight="700" fill="#ffffff" text-anchor="middle">1. Jogador Clica &quot;Comprar&quot;</text>
  <text x="785" y="252" font-size="11.5" fill="#fde68a" text-anchor="middle">Espada Lendária · 500 Ouro</text>

  <!-- STEP 1: Decisão Saldo >= 500 Ouro? (Beat 3) -->
  ${alphaStep1 > 0 ? `
  <g opacity="${alphaStep1}">
    <!-- Arrow 1 -> 2 (y=260 -> y=322) -->
    <line x1="785" y1="260" x2="785" y2="314" stroke="#8b5cf6" stroke-width="2.5"/>
    <polygon points="779,314 785,322 791,314" fill="#8b5cf6"/>

    <!-- Node 2: Decision (y=322..394, h=72) -->
    <rect x="610" y="322" width="350" height="72" rx="10" fill="rgba(245, 158, 11, 0.12)" stroke="#f59e0b" stroke-width="2"/>
    <rect x="625" y="328" width="320" height="20" rx="10" fill="rgba(139, 92, 246, 0.2)" stroke="#f59e0b"/>
    <text x="785" y="${pillTextY(328, 20, 9)}" font-size="9" font-weight="700" fill="#fde68a" text-anchor="middle">Fronteira: Regra do Jogo ↔ Validação no Servidor</text>
    <text x="785" y="369" font-size="16" font-weight="700" fill="#ffffff" text-anchor="middle">2. Saldo ≥ 500 Ouro?</text>

    <!-- Branch NÃO -> Recusada (x=960 -> x=1034) -->
    <line x1="960" y1="358" x2="1024" y2="358" stroke="#ef4444" stroke-width="2.5"/>
    <polygon points="1024,352 1032,358 1024,364" fill="#ef4444"/>
    <rect x="970" y="330" width="44" height="18" rx="4" fill="#18181d" stroke="#ef4444" stroke-opacity="0.5"/>
    <text x="992" y="${pillTextY(330, 18, 9.5)}" font-size="9.5" font-weight="800" fill="#f87171" text-anchor="middle">NÃO</text>

    <rect x="1034" y="328" width="174" height="60" rx="8" fill="rgba(239, 68, 68, 0.14)" stroke="#ef4444" stroke-width="1.5"/>
    <text x="1121" y="353" font-size="13" font-weight="700" fill="#fca5a5" text-anchor="middle">Compra Recusada</text>
    <text x="1121" y="372" font-size="10.5" fill="#9ca3af" text-anchor="middle">Saldo insuficiente</text>
  </g>` : ""}

  <!-- STEP 2: Entrega + Pílulas de Resultado Embutidas (Beat 4) -->
  ${alphaStep2 > 0 ? `
  <g opacity="${alphaStep2}">
    <!-- Arrow 2 -> 3 (y=394 -> y=448) -->
    <line x1="785" y1="394" x2="785" y2="446" stroke="#10b981" stroke-width="2.5"/>
    <polygon points="779,446 785,454 791,446" fill="#10b981"/>
    <rect x="798" y="412" width="40" height="20" rx="4" fill="#18181d" stroke="#10b981" stroke-opacity="0.5"/>
    <text x="818" y="${pillTextY(412, 20, 9.5)}" font-size="9.5" font-weight="800" fill="#34d399" text-anchor="middle">SIM</text>

    <!-- Node 3: Entrega + Resultado Final (y=454..588, h=134) -->
    <rect x="535" y="454" width="500" height="134" rx="10" fill="rgba(16, 185, 129, 0.12)" stroke="#10b981" stroke-width="2"/>
    <text x="785" y="474" font-size="10.5" font-weight="700" fill="#6ee7b7" text-anchor="middle" letter-spacing="1">ENTREGA</text>
    <text x="785" y="498" font-size="16" font-weight="700" fill="#ffffff" text-anchor="middle">3. Desconta 500 Ouro · Entrega Espada</text>

    <!-- Internal Outcome Pills with Server / Client Responsibility Labels -->
    <rect x="547" y="516" width="232" height="58" rx="8" fill="#1e1e24" stroke="#10b981" stroke-width="1.5"/>
    ${iconDatabase(557, 532, 22, "#34d399")}
    <text x="586" y="538" font-size="12" font-weight="700" fill="#6ee7b7">Salvo no Inventário</text>
    <text x="586" y="558" font-size="9" font-weight="600" fill="#9ca3af">Responsabilidade do Servidor (Banco)</text>

    <rect x="791" y="516" width="232" height="58" rx="8" fill="#1e1e24" stroke="#10b981" stroke-width="1.5"/>
    ${iconBolt(801, 532, 22, "#38bdf8")}
    <text x="830" y="538" font-size="12" font-weight="700" fill="#6ee7b7">Jogador Notificado</text>
    <text x="830" y="558" font-size="9" font-weight="600" fill="#9ca3af">Resposta ao Cliente (Unity)</text>
  </g>` : ""}

  <!-- Bottom Footer Strip -->
  <rect x="466" y="616" width="744" height="46" rx="8" fill="#1e1e24" stroke="#2e2e38"/>
  <text x="486" y="${pillTextY(616, 46, 10.8)}" font-size="10.8" font-weight="700" fill="#34d399">Ponto de ruptura: salvar inventário e validar saldo exigem servidor.</text>
  <rect x="1072" y="627" width="122" height="24" rx="12" fill="rgba(16, 185, 129, 0.2)" stroke="#10b981"/>
  <text x="1133" y="${pillTextY(627, 24, 10.5)}" font-size="10.5" font-weight="700" fill="#34d399" text-anchor="middle">Foco 100%</text>
</svg>`;
}

// ==========================================
// SLIDE 2: Onde o Tempo Vaza · 4 Papéis Extras (5 Beats)
// ==========================================
function renderSlide2(step, t) {
  const e = easeOutCubic(t);
  const prevPct = Math.max(0, step - 1) * 25;
  const targetPct = step * 25;
  const pct = Math.round(prevPct + (targetPct - prevPct) * e);

  const roles = [
    {
      idx: 1,
      badge: "PAPEL 1 · DBA",
      short: "1. DBA",
      tech: "PostgreSQL · SQL",
      title: "Administrador de Banco de Dados",
      desc: "Tabelas, transações e migrações (~45 linhas).",
      source: "Politowski et al. (2021 · 200 jogos): erros técnicos travam produção",
      snippet: [
        `<tspan fill="#fbbf24" font-weight="700">BEGIN TRANSACTION</tspan><tspan fill="#9ca3af">;</tspan>`,
        `<tspan fill="#fbbf24" font-weight="700">UPDATE</tspan> <tspan fill="#38bdf8">wallets</tspan> <tspan fill="#fbbf24" font-weight="700">SET</tspan> <tspan fill="#38bdf8">gold</tspan> = gold - <tspan fill="#34d399">500</tspan> <tspan fill="#fbbf24" font-weight="700">WHERE</tspan> <tspan fill="#38bdf8">id</tspan> = <tspan fill="#34d399">$1</tspan>;`,
        `<tspan fill="#fbbf24" font-weight="700">INSERT INTO</tspan> <tspan fill="#38bdf8">inventory</tspan> <tspan fill="#fbbf24" font-weight="700">VALUES</tspan> (<tspan fill="#34d399">$1</tspan>, <tspan fill="#fde68a">&apos;espada&apos;</tspan>);`,
      ],
      color: "#fbbf24",
      x: 50, y: 248, w: 575, h: 210,
      icon: (x, y) => iconDatabase(x, y, 22, "#fbbf24"),
    },
    {
      idx: 2,
      badge: "PAPEL 2 · BACKEND",
      short: "2. Backend",
      tech: "REST · HTTP · JSON",
      title: "Engenheiro de Backend",
      desc: "Rotas HTTP, APIs e JSON manual (~50 linhas).",
      source: "Unity Gaming Report (2024): 37% travam ao integrar sistemas",
      snippet: [
        `<tspan fill="#34d399" font-weight="700">POST</tspan> <tspan fill="#38bdf8">/api/v1/shop/buy</tspan> <tspan fill="#9ca3af">HTTP/1.1</tspan>`,
        `<tspan fill="#c084fc" font-weight="700">Content-Type:</tspan> <tspan fill="#fde68a">application/json</tspan>`,
        `{<tspan fill="#7dd3fc">&quot;itemId&quot;</tspan>: <tspan fill="#fbbf24">&quot;espada_lendaria&quot;</tspan>, <tspan fill="#7dd3fc">&quot;price&quot;</tspan>: <tspan fill="#34d399">500</tspan>}`,
      ],
      color: "#38bdf8",
      x: 655, y: 248, w: 575, h: 210,
      icon: (x, y) => iconServer(x, y, 22, "#38bdf8"),
    },
    {
      idx: 3,
      badge: "PAPEL 3 · SEGURANÇA",
      short: "3. Segurança",
      tech: "Auth · Anti-Cheat",
      title: "Segurança e Anti-Cheat",
      desc: "Sessão, escopo e anti-cheat no servidor (~40 linhas).",
      source: "Irdeto/Forbes: 77% largam jogos com cheats; 48% compram menos",
      snippet: [
        `<tspan fill="#fb7185" font-weight="700">Authorization:</tspan> <tspan fill="#fbbf24">Bearer eyJhbGciOiJIUzI1Ni...</tspan>`,
        `<tspan fill="#f472b6" font-weight="700">if</tspan> (!<tspan fill="#38bdf8">VerifyToken</tspan>(tok) || scope != <tspan fill="#fde68a">&quot;player&quot;</tspan>) <tspan fill="#f472b6" font-weight="700">return</tspan> <tspan fill="#34d399">403</tspan>;`,
        `<tspan fill="#f472b6" font-weight="700">if</tspan> (req.Price &lt;= <tspan fill="#34d399">0</tspan>) <tspan fill="#38bdf8">RejectFraud</tspan>(req);`,
      ],
      color: "#ef4444",
      x: 50, y: 474, w: 575, h: 210,
      icon: (x, y) => iconShield(x, y, 22, "#ef4444"),
    },
    {
      idx: 4,
      badge: "PAPEL 4 · DEVOPS",
      short: "4. DevOps",
      tech: "Containers · Nuvem",
      title: "Operações e Nuvem (DevOps)",
      desc: "Containers, portas e deploy em nuvem (~45 linhas).",
      source: "GDC State of Industry (2024): custo restringe live-service a 16%",
      snippet: [
        `<tspan fill="#fb923c" font-weight="700">FROM</tspan> <tspan fill="#38bdf8">mcr.microsoft.com/dotnet/aspnet:9.0</tspan>`,
        `<tspan fill="#fb923c" font-weight="700">EXPOSE</tspan> <tspan fill="#fbbf24">8080 443</tspan>`,
        `<tspan fill="#fb923c" font-weight="700">ENTRYPOINT</tspan> [<tspan fill="#34d399">&quot;dotnet&quot;</tspan>, <tspan fill="#34d399">&quot;GameShop.dll&quot;</tspan>]`,
      ],
      color: "#f97316",
      x: 655, y: 474, w: 575, h: 210,
      icon: (x, y) => iconCloud(x, y, 22, "#f97316"),
    },
  ];

  function renderRoleCard(r) {
    const isActive = step >= r.idx;
    const isNew = step === r.idx;
    const alpha = isActive ? (isNew ? e : 1) : 0.24;
    const dy = isNew ? Math.round(10 * (1 - e)) : 0;
    const borderCol = isActive ? r.color : "#2e2e38";

    return `
    <g transform="translate(0, ${dy})" opacity="${alpha}">
      <rect x="${r.x}" y="${r.y}" width="${r.w}" height="${r.h}" rx="10" fill="#1e1e24" stroke="${borderCol}" stroke-width="${isActive ? "1.5" : "1"}"/>

      <!-- Badge strip -->
      <rect x="${r.x + 18}" y="${r.y + 14}" width="160" height="24" rx="4" fill="#18181d" stroke="${borderCol}"/>
      <text x="${r.x + 98}" y="${pillTextY(r.y + 14, 24, 10.5)}" font-size="10.5" font-weight="700" fill="${r.color}" text-anchor="middle">${esc(r.badge)}</text>

      <rect x="${r.x + 188}" y="${r.y + 14}" width="150" height="24" rx="4" fill="#18181d"/>
      <text x="${r.x + 263}" y="${pillTextY(r.y + 14, 24, 10.5)}" font-size="10.5" font-weight="600" fill="#9ca3af" text-anchor="middle">${esc(r.tech)}</text>

      ${r.icon(r.x + r.w - 40, r.y + 15)}

      <text x="${r.x + 18}" y="${r.y + 62}" font-size="14.5" font-weight="700" fill="#f3f4f6">${esc(r.title)}</text>

      <!-- Snippet Box -->
      <rect x="${r.x + 18}" y="${r.y + 73}" width="${r.w - 36}" height="80" rx="6" fill="#141417" stroke="#2e2e38"/>
      ${r.snippet.map((line, i) => `
      <text x="${r.x + 28}" y="${r.y + 94 + i * 20}" font-family="Menlo, Monaco, Consolas, monospace" font-size="10.2" fill="#d1d5db" xml:space="preserve">${line}</text>
      `).join("")}

      <text x="${r.x + 18}" y="${r.y + 174}" font-size="10.5" fill="#9ca3af">${esc(r.desc)}</text>
      <text x="${r.x + 18}" y="${r.y + 190}" font-size="9.5" font-weight="600" fill="#ddd6fe">${esc(r.source)}</text>
    </g>`;
  }

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="720" viewBox="0 0 1280 720">
  <defs>
    <style>
      text { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif; }
    </style>
  </defs>
  <rect width="1280" height="720" fill="#141417"/>
  ${renderHeader("ATO II · ONDE O TEMPO VAZA", "A Armadilha do Multiplayer: 1 Dev Forçado a Virar 4.", `Etapa ${step + 1} de 5`)}

  <!-- Top Strip: Segmented 4-Role Overload Meter -->
  <rect x="50" y="114" width="1180" height="118" rx="12" fill="#1e1e24" stroke="#ef4444" stroke-width="1.5"/>
  ${renderPortrait("p_s2_overwhelmed", IMG_OVERWHELMED, 65, 123, 130, 100, 8, "#ef4444")}

  <text x="215" y="144" font-size="16" font-weight="700" fill="#f87171">Sobrecarga de Infraestrutura · ${step} de 4 papéis fora do jogo</text>
  <text x="215" y="166" font-size="10.8" fill="#9ca3af"><tspan fill="#ddd6fe" font-weight="700">Mark et al. (ACM CHI 2005):</tspan> 25m26s p/ retomar tarefa após troca · <tspan fill="#ddd6fe" font-weight="700">Parnin &amp; Rugaber (2011):</tspan> só 10% retomam em &lt;1 min</text>

  <!-- 4 Clean Segment Pills (215..985) + Summary Pill (1000..1210) -->
  ${roles.map((r, i) => {
    const segW = 186;
    const segGap = 8;
    const sx = 215 + i * (segW + segGap);
    const active = step >= r.idx;
    return `
    <rect x="${sx}" y="185" width="${segW}" height="28" rx="5" fill="${active ? r.color : "#141417"}" fill-opacity="${active ? "0.22" : "1"}" stroke="${active ? r.color : "#2e2e38"}" stroke-width="${active ? "1.5" : "1"}"/>
    <text x="${sx + segW / 2}" y="${pillTextY(185, 28, 10.5)}" font-size="10.5" font-weight="700" fill="${active ? "#ffffff" : "#6b7280"}" text-anchor="middle">${esc(r.short)}</text>`;
  }).join("")}

  <rect x="1000" y="185" width="210" height="28" rx="14" fill="${pct > 0 ? "rgba(239, 68, 68, 0.22)" : "#141417"}" stroke="${pct > 0 ? "#ef4444" : "#2e2e38"}"/>
  <text x="1105" y="${pillTextY(185, 28, 11)}" font-size="11" font-weight="800" fill="${pct > 0 ? "#fca5a5" : "#9ca3af"}" text-anchor="middle">${pct}% sobrecarga (${step}/4)</text>

  <!-- 4 Role Cards (2x2 Grid, always populated and progressively illuminated) -->
  ${roles.map(renderRoleCard).join("")}
</svg>`;
}

// ==========================================
// SLIDE 3: O Custo Real (1 Beat)
// ==========================================
function renderSlide3(step, t) {
  const e = easeOutCubic(t);

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="720" viewBox="0 0 1280 720">
  <defs>
    <style>
      text { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif; }
    </style>
  </defs>
  <rect width="1280" height="720" fill="#141417"/>
  ${renderHeader("ATO II · O CUSTO REAL", "O Gargalo Real: 90% do Tempo Gasto Fora do Gameplay.", "Slide 4 de 10")}

  <g opacity="${e}">
    <!-- Coluna Esquerda (x=50..500, w=450) -->
    ${renderPortrait("p_s3_overwhelmed", IMG_OVERWHELMED, 50, 114, 450, 250, 12, "#ef4444")}

    <!-- Card Consolidado (x=50, y=380, width=450, height=304, borda #ef4444) -->
    <rect x="50" y="380" width="450" height="304" rx="12" fill="#1e1e24" stroke="#ef4444" stroke-width="1.5"/>
    <text x="70" y="412" font-size="12.5" font-weight="800" fill="#f87171" letter-spacing="0.6">A SOMA DOS 4 PAPÉIS FORA DO JOGO</text>

    <!-- 1. DBA -->
    <rect x="70" y="428" width="410" height="36" rx="6" fill="#18181d" stroke="#2e2e38"/>
    ${iconDatabase(80, 436, 20, "#fbbf24")}
    <text x="110" y="${pillTextY(428, 36, 11)}" font-size="11" font-weight="600" fill="#f3f4f6">1. DBA (PostgreSQL &amp; SQL)</text>
    <rect x="382" y="434" width="88" height="24" rx="4" fill="rgba(251, 191, 36, 0.15)" stroke="#fbbf24"/>
    <text x="426" y="${pillTextY(434, 24, 10.5)}" font-size="10.5" font-weight="700" fill="#fbbf24" text-anchor="middle">~45 linhas</text>

    <!-- 2. Backend -->
    <rect x="70" y="474" width="410" height="36" rx="6" fill="#18181d" stroke="#2e2e38"/>
    ${iconServer(80, 482, 20, "#38bdf8")}
    <text x="110" y="${pillTextY(474, 36, 11)}" font-size="11" font-weight="600" fill="#f3f4f6">2. Backend (REST, HTTP &amp; JSON)</text>
    <rect x="382" y="480" width="88" height="24" rx="4" fill="rgba(56, 189, 248, 0.15)" stroke="#38bdf8"/>
    <text x="426" y="${pillTextY(480, 24, 10.5)}" font-size="10.5" font-weight="700" fill="#38bdf8" text-anchor="middle">~50 linhas</text>

    <!-- 3. Segurança -->
    <rect x="70" y="520" width="410" height="36" rx="6" fill="#18181d" stroke="#2e2e38"/>
    ${iconShield(80, 528, 20, "#ef4444")}
    <text x="110" y="${pillTextY(520, 36, 11)}" font-size="11" font-weight="600" fill="#f3f4f6">3. Segurança (Auth &amp; Anti-Cheat)</text>
    <rect x="382" y="526" width="88" height="24" rx="4" fill="rgba(239, 68, 68, 0.15)" stroke="#ef4444"/>
    <text x="426" y="${pillTextY(526, 24, 10.5)}" font-size="10.5" font-weight="700" fill="#f87171" text-anchor="middle">~40 linhas</text>

    <!-- 4. DevOps -->
    <rect x="70" y="566" width="410" height="36" rx="6" fill="#18181d" stroke="#2e2e38"/>
    ${iconCloud(80, 574, 20, "#f97316")}
    <text x="110" y="${pillTextY(566, 36, 11)}" font-size="11" font-weight="600" fill="#f3f4f6">4. DevOps (Docker, Portas &amp; Nuvem)</text>
    <rect x="382" y="572" width="88" height="24" rx="4" fill="rgba(249, 115, 22, 0.15)" stroke="#f97316"/>
    <text x="426" y="${pillTextY(572, 24, 10.5)}" font-size="10.5" font-weight="700" fill="#fb923c" text-anchor="middle">~45 linhas</text>

    <!-- Linha Total Destacada em vermelho -->
    <rect x="70" y="614" width="410" height="46" rx="8" fill="rgba(239, 68, 68, 0.18)" stroke="#ef4444" stroke-width="1.5"/>
    ${iconAlert(82, 627, 20, "#ef4444")}
    <text x="110" y="${pillTextY(614, 46, 11.5)}" font-size="11.5" font-weight="800" fill="#fca5a5">Total fora do gameplay: ~180 linhas em 4 camadas</text>

    <!-- Coluna Direita (x=526..1230, w=704, y=114..684, h=570) -->
    <rect x="526" y="114" width="704" height="570" rx="12" fill="#1e1e24" stroke="#ef4444" stroke-width="1.5"/>
    <text x="551" y="146" font-size="13" font-weight="800" fill="#f87171" letter-spacing="0.6">DESPROPORÇÃO ENTRE GAMEPLAY E INFRAESTRUTURA</text>

    <!-- Barra de proporção (~21 linhas de Jogo (10%) vs ~180 linhas de Infraestrutura (90% fora do gameplay)) -->
    <text x="551" y="174" font-size="11.5" font-weight="700" fill="#34d399">~21 linhas de Jogo (10%)</text>
    <text x="1205" y="174" font-size="11.5" font-weight="700" fill="#fca5a5" text-anchor="end">~180 linhas de Infraestrutura (90% fora do gameplay)</text>
    <rect x="551" y="184" width="654" height="36" rx="6" fill="#18181d" stroke="#2e2e38"/>
    <rect x="551" y="184" width="65" height="36" rx="6" fill="#10b981"/>
    <rect x="619" y="184" width="586" height="36" rx="6" fill="#ef4444" fill-opacity="0.88"/>
    <text x="583.5" y="${pillTextY(184, 36, 11)}" font-size="11" font-weight="800" fill="#ffffff" text-anchor="middle">21</text>
    <text x="912" y="${pillTextY(184, 36, 11.5)}" font-size="11.5" font-weight="700" fill="#ffffff" text-anchor="middle">Banco de Dados · API · Anti-Cheat · Nuvem (~180 linhas)</text>

    <!-- 2 Cartões de Evidências Específicas de Jogos -->
    <!-- Card 1: UNITY GAMING REPORT -->
    <rect x="551" y="246" width="317" height="306" rx="10" fill="#18181d" stroke="#38bdf8" stroke-opacity="0.65"/>
    <text x="571" y="274" font-size="10.5" font-weight="700" fill="#38bdf8" letter-spacing="0.5">UNITY GAMING REPORT (2024 · ESTÚDIOS GLOBAIS)</text>
    <text x="571" y="318" font-size="25" font-weight="800" fill="#f3f4f6">218 → 304 dias</text>
    <text x="571" y="346" font-size="13" font-weight="700" fill="#7dd3fc">+39% no prazo de lançamento</text>
    <text x="571" y="384" font-size="11.5" fill="#cbd5e1">Pesquisa anual da Unity com estúdios:</text>
    <text x="571" y="408" font-size="11.5" fill="#cbd5e1">68% desenvolvem jogos online e 37%</text>
    <text x="571" y="432" font-size="11.5" fill="#cbd5e1">atrasam integrando sistemas externos.</text>
    <text x="571" y="522" font-size="9.8" font-weight="600" fill="#9ca3af">create.unity.com/gaming-report-2024</text>

    <!-- Card 2: POLITOWSKI ET AL. -->
    <rect x="888" y="246" width="317" height="306" rx="10" fill="#18181d" stroke="#8b5cf6" stroke-opacity="0.65"/>
    <text x="908" y="274" font-size="10.5" font-weight="700" fill="#a78bfa" letter-spacing="0.5">POLITOWSKI ET AL. (2021 · ESTUDO ACADÊMICO)</text>
    <text x="908" y="318" font-size="22" font-weight="800" fill="#f3f4f6">927 falhas em 200 jogos</text>
    <text x="908" y="346" font-size="13" font-weight="700" fill="#ddd6fe">Postmortems públicos (1997–2019)</text>
    <text x="908" y="384" font-size="11.5" fill="#cbd5e1">Relatos reais de equipes após o lançamento</text>
    <text x="908" y="408" font-size="11.5" fill="#cbd5e1">mostram sobrecarga técnica e gargalos</text>
    <text x="908" y="432" font-size="11.5" fill="#cbd5e1">liderando atrasos e cortes.</text>
    <text x="908" y="522" font-size="9.8" font-weight="600" fill="#9ca3af">arxiv.org/abs/2009.02440 (Peer-reviewed)</text>

    <!-- Faixa inferior consolidando -->
    <rect x="551" y="580" width="654" height="56" rx="8" fill="#18181d" stroke="#ef4444" stroke-opacity="0.5"/>
    ${iconClock(568, 598, 20, "#ef4444")}
    <text x="598" y="${pillTextY(580, 56, 11.5)}" font-size="11.5" font-weight="700" fill="#fca5a5">Resultado: Features de 2 horas viram semanas travadas em banco, APIs e DevOps.</text>
  </g>
</svg>`;
}

// ==========================================
// Shared Unity Editor Shell (Full 1180x570 Screen)
// ==========================================
function renderUnityEditorShell(highlightNewExt = false, bgOpacity = 1) {
  return `
  <g opacity="${bgOpacity}">
    <!-- Unity Window Outer Frame (x=50, y=114, w=1180, h=570) -->
    <rect x="50" y="114" width="1180" height="570" rx="12" fill="#18181d" stroke="#3a3a46" stroke-width="1.5"/>

    <!-- Barra de Título & Toolbar do Unity (y=114..156) -->
    <rect x="50" y="114" width="1180" height="42" rx="12" fill="#202026"/>
    <rect x="50" y="144" width="1180" height="12" fill="#202026"/>
    <line x1="50" y1="156" x2="1230" y2="156" stroke="#2e2e38" stroke-width="1"/>

    <!-- Window Controls & Title (Esquerda) -->
    <circle cx="72" cy="135" r="4.5" fill="#ef4444"/>
    <circle cx="88" cy="135" r="4.5" fill="#fbbf24"/>
    <circle cx="104" cy="135" r="4.5" fill="#10b981"/>
    <text x="122" y="139" font-size="12" font-weight="700" fill="#f3f4f6">MyFantasyRPG — LojaUI.unity — Unity 6</text>

    <!-- Toolbar do Unity (Centro: Play / Pause / Step) -->
    <rect x="580" y="122" width="120" height="26" rx="6" fill="#262630" stroke="#3a3a46"/>
    <rect x="584" y="124" width="34" height="22" rx="4" fill="rgba(56, 189, 248, 0.2)" stroke="#38bdf8" stroke-width="1"/>
    <polygon points="597,130 597,140 606,135" fill="#38bdf8"/>
    <rect x="637" y="130" width="3" height="10" rx="1" fill="#9ca3af"/>
    <rect x="644" y="130" width="3" height="10" rx="1" fill="#9ca3af"/>
    <polygon points="674,130 674,140 681,135" fill="#9ca3af"/>
    <rect x="682" y="130" width="2" height="10" rx="0.5" fill="#9ca3af"/>

    <!-- Toolbar Direita (Layers e Layout: Exoforge) -->
    <rect x="1004" y="123" width="70" height="24" rx="4" fill="#22222b" stroke="#3a3a46"/>
    <text x="1039" y="${pillTextY(123, 24, 10)}" font-size="10" font-weight="600" fill="#9ca3af" text-anchor="middle">Layers</text>
    <rect x="1082" y="123" width="134" height="24" rx="4" fill="#22222b" stroke="#8b5cf6"/>
    <text x="1149" y="${pillTextY(123, 24, 10)}" font-size="10" font-weight="700" fill="#ddd6fe" text-anchor="middle">Layout: Exoforge</text>

    <!-- COLUNA 1 — HIERARCHY (x=62..252, y=166..524, w=190, h=358) -->
    <rect x="62" y="166" width="190" height="358" rx="8" fill="#141417" stroke="#2e2e38"/>
    <rect x="62" y="166" width="190" height="28" rx="8" fill="#1e1e24"/>
    <rect x="62" y="186" width="190" height="8" fill="#1e1e24"/>
    <text x="74" y="${pillTextY(166, 28, 9.5)}" font-size="9.5" font-weight="700" fill="#9ca3af" letter-spacing="0.5">HIERARCHY</text>
    <line x1="62" y1="194" x2="252" y2="194" stroke="#2e2e38" stroke-width="1"/>

    <!-- Lista de objetos da cena -->
    <text x="74" y="218" font-size="10.5" font-weight="700" fill="#a78bfa">▾ LojaUI (Scene)</text>
    <text x="86" y="244" font-size="10" fill="#9ca3af">Main Camera</text>
    <text x="86" y="270" font-size="10" fill="#9ca3af">Directional Light</text>
    <text x="74" y="300" font-size="10.5" font-weight="700" fill="#a78bfa">▾ Canvas</text>
    <text x="94" y="326" font-size="10" fill="#cbd5e1">LojaPanel</text>
    <!-- BtnComprarEspada (destacado em azul #38bdf8) -->
    <rect x="72" y="342" width="172" height="26" rx="4" fill="rgba(56, 189, 248, 0.18)" stroke="#38bdf8" stroke-width="1.2"/>
    <text x="94" y="${pillTextY(342, 26, 10.5)}" font-size="10.5" font-weight="700" fill="#38bdf8">BtnComprarEspada</text>

    <rect x="72" y="478" width="170" height="34" rx="6" fill="#18181d" stroke="#262632"/>
    <text x="82" y="${pillTextY(478, 34, 9)}" font-size="9" fill="#9ca3af">UI selecionada na cena</text>

    <!-- COLUNA 2 — GAME VIEW (Mockup de Jogo RPG! x=264..746, y=166..524, w=482, h=358) -->
    <rect x="264" y="166" width="482" height="358" rx="8" fill="#181820" stroke="#2e2e38"/>

    <!-- Abas no topo: Scene e Game -->
    <rect x="270" y="170" width="60" height="24" rx="4" fill="#141417"/>
    <text x="300" y="${pillTextY(170, 24, 9.5)}" font-size="9.5" font-weight="600" fill="#6b7280" text-anchor="middle">Scene</text>
    <rect x="336" y="170" width="66" height="24" rx="4" fill="#202434" stroke="#38bdf8" stroke-width="1.5"/>
    <text x="369" y="${pillTextY(170, 24, 10)}" font-size="10" font-weight="700" fill="#38bdf8" text-anchor="middle">Game</text>
    <rect x="638" y="171" width="98" height="22" rx="11" fill="#141417" stroke="#2e2e38"/>
    <circle cx="650" cy="182" r="3" fill="#10b981"/>
    <text x="694" y="${pillTextY(171, 22, 9.5)}" font-size="9.5" font-weight="600" fill="#9ca3af" text-anchor="middle">16:9 · Play</text>
    <line x1="264" y1="196" x2="746" y2="196" stroke="#2e2e38" stroke-width="1"/>

    <!-- Canvas do Jogo Mockup (x=278..732, y=206..510, w=454, h=304) -->
    <rect x="278" y="206" width="454" height="304" rx="8" fill="#0f1219" stroke="#222838"/>
    <rect x="282" y="210" width="446" height="296" rx="6" fill="#111522" fill-opacity="0.9"/>

    <!-- Barra superior do jogo: OURO: 1.250 e NÍVEL 12 -->
    <rect x="288" y="216" width="434" height="28" rx="6" fill="#161c2c" stroke="#283248"/>
    <circle cx="304" cy="230" r="7" fill="#fbbf24"/>
    <text x="304" y="233.5" font-size="10" font-weight="900" fill="#78350f" text-anchor="middle">G</text>
    <text x="318" y="${pillTextY(216, 28, 10.5)}" font-size="10.5" font-weight="800" fill="#fbbf24">OURO: 1.250</text>
    <text x="505" y="${pillTextY(216, 28, 10.5)}" font-size="10.5" font-weight="700" fill="#94a3b8" letter-spacing="0.5">Loja do Ferreiro</text>
    <rect x="646" y="221" width="68" height="18" rx="9" fill="rgba(139, 92, 246, 0.2)" stroke="#8b5cf6"/>
    <text x="680" y="${pillTextY(221, 18, 9)}" font-size="9" font-weight="800" fill="#ddd6fe" text-anchor="middle">NÍVEL 12</text>

    <!-- Card central do item da Loja -->
    <rect x="335" y="252" width="340" height="248" rx="10" fill="#151b2a" stroke="#eab308" stroke-width="1.5"/>
    <rect x="425" y="260" width="160" height="20" rx="10" fill="rgba(234, 179, 8, 0.15)" stroke="#eab308"/>
    <text x="505" y="${pillTextY(260, 20, 9)}" font-size="9" font-weight="800" fill="#fde047" text-anchor="middle">ITEM EM DESTAQUE</text>
    <rect x="475" y="286" width="60" height="60" rx="8" fill="#1e263c" stroke="#fbbf24" stroke-width="1.5"/>
    ${iconSword(485, 296, 40, "#fbbf24")}
    <text x="505" y="364" font-size="15" font-weight="800" fill="#f3f4f6" text-anchor="middle">Espada Lendária</text>
    <text x="505" y="384" font-size="11" font-weight="600" fill="#a78bfa" text-anchor="middle">Dano +45 · Raridade Épica</text>
    <rect x="370" y="402" width="270" height="42" rx="8" fill="#059669" stroke="#34d399" stroke-width="2"/>
    <rect x="372" y="404" width="266" height="20" rx="6" fill="#10b981" fill-opacity="0.35"/>
    <text x="505" y="${pillTextY(402, 42, 12.5)}" font-size="12.5" font-weight="800" fill="#ffffff" text-anchor="middle">COMPRAR · 500 OURO</text>
    <text x="505" y="462" font-size="9" fill="#94a3b8" text-anchor="middle">O clique chama BtnComprarEspada.OnClick()</text>
    <text x="505" y="476" font-size="9.5" fill="#64748b" text-anchor="middle">Canvas UI 16:9 · Cena ativa LojaUI.unity</text>

    <!-- BARRA INFERIOR — PROJECT / ASSETS (x=62..746, y=534..672, w=684, h=138) -->
    <rect x="62" y="534" width="684" height="138" rx="8" fill="#141417" stroke="#2e2e38"/>

    <!-- Abas Project e Console -->
    <rect x="68" y="538" width="76" height="22" rx="4" fill="#1e1e24" stroke="#38bdf8" stroke-width="1.2"/>
    <text x="106" y="${pillTextY(538, 22, 9.5)}" font-size="9.5" font-weight="700" fill="#38bdf8" text-anchor="middle">Project</text>
    <rect x="150" y="538" width="116" height="22" rx="4" fill="#18181d"/>
    <circle cx="162" cy="549" r="3" fill="#10b981"/>
    <text x="212" y="${pillTextY(538, 22, 9)}" font-size="9" fill="#9ca3af" text-anchor="middle">Console (0 erros)</text>
    <text x="734" y="${pillTextY(538, 22, 9)}" font-size="9" fill="#6b7280" text-anchor="end">Exoforge SDK v0.1.38</text>
    <line x1="62" y1="562" x2="746" y2="562" stroke="#2e2e38" stroke-width="1"/>

    <!-- Pastas e Arquivos -->
    ${iconFolder(78, 574, 13, "#9ca3af")}
    <text x="96" y="584" font-size="10" font-weight="700" fill="#9ca3af">Assets /</text>
    ${iconFolder(96, 594, 13, "#9ca3af")}
    <text x="114" y="604" font-size="9.5" fill="#9ca3af">Scenes / LojaUI.unity</text>
    ${iconFolder(96, 614, 13, "#9ca3af")}
    <text x="114" y="624" font-size="9.5" fill="#9ca3af">Scripts /</text>
    <rect x="108" y="632" width="180" height="24" rx="4" fill="#1c202a" stroke="#38bdf8"/>
    ${iconFileCode(116, 637, 14, "#7dd3fc")}
    <text x="136" y="${pillTextY(632, 24, 9.5)}" font-size="9.5" font-weight="600" fill="#7dd3fc">LojaController.cs</text>

    <!-- Pasta destacada Exoforge / Extensions -->
    <rect x="334" y="572" width="402" height="90" rx="6" fill="rgba(139, 92, 246, 0.12)" stroke="#8b5cf6" stroke-width="1.5"/>
    <rect x="344" y="580" width="194" height="20" rx="10" fill="rgba(139, 92, 246, 0.25)" stroke="#a78bfa"/>
    <text x="441" y="${pillTextY(580, 20, 9.2)}" font-size="9.2" font-weight="800" fill="#ddd6fe" text-anchor="middle">PASTA EXCLUSIVA EXOFORGE</text>
    <text x="724" y="${pillTextY(580, 20, 9.5)}" font-size="9.5" fill="#a78bfa" text-anchor="end">Workspace do Jogo</text>
    ${iconFolder(344, 608, 15, "#a78bfa")}
    <text x="366" y="618" font-size="10.5" font-weight="700" fill="#f3f4f6">Exoforge / Extensions /</text>
    <text x="344" y="636" font-size="9.5" fill="#cbd5e1">Onde os módulos C# nascem e compilam nativamente.</text>
    <text x="344" y="652" font-size="9" fill="#9ca3af">Totalmente integrado ao assembly do Unity sem abrir IDE externa.</text>

    <!-- COLUNA 3 — EXOFORGE STUDIO (DOCKED) (x=758..1218, y=166..672, w=460, h=506) -->
    <rect x="758" y="166" width="460" height="506" rx="8" fill="#1e1e24" stroke="#2e2e38"/>

    <!-- Aba ativa: Exoforge Studio ▸ Extensions + Cluster Conectado -->
    <rect x="758" y="166" width="460" height="42" rx="8" fill="#18181d" stroke="#2e2e38"/>
    <text x="774" y="${pillTextY(166, 42, 12)}" font-size="12" font-weight="700" fill="#f3f4f6">Exoforge Studio ▸ Extensions</text>
    <rect x="1070" y="176" width="134" height="22" rx="11" fill="rgba(16, 185, 129, 0.15)" stroke="#10b981"/>
    <circle cx="1082" cy="187" r="3.5" fill="#10b981"/>
    <text x="1144" y="${pillTextY(176, 22, 9.5)}" font-size="9.5" font-weight="700" fill="#34d399" text-anchor="middle">Cluster Conectado</text>
    <line x1="758" y1="208" x2="1218" y2="208" stroke="#2e2e38" stroke-width="1"/>

    <text x="774" y="230" font-size="10" font-weight="700" fill="#a78bfa" letter-spacing="0.5">EXTENSÕES NO WORKSPACE DO JOGO</text>

    <!-- Extensão 1: player_profile -->
    <rect x="774" y="242" width="428" height="56" rx="8" fill="#18181d" stroke="#2e2e38"/>
    ${iconServer(788, 259, 22, "#38bdf8")}
    <text x="822" y="267" font-size="12.5" font-weight="700" fill="#f3f4f6">player_profile</text>
    <text x="822" y="285" font-size="10" fill="#9ca3af">Autenticação, sessões e perfil de jogadores</text>
    <rect x="1038" y="257" width="68" height="22" rx="4" fill="#202026"/>
    <text x="1072" y="${pillTextY(257, 22, 9)}" font-size="9" font-weight="600" fill="#9ca3af" text-anchor="middle">C# Nativo</text>
    <rect x="1114" y="257" width="76" height="22" rx="11" fill="rgba(16, 185, 129, 0.15)" stroke="#10b981"/>
    <text x="1152" y="${pillTextY(257, 22, 9)}" font-size="9" font-weight="700" fill="#34d399" text-anchor="middle">✓ Ativo</text>

    <!-- Extensão 2: match_events -->
    <rect x="774" y="306" width="428" height="56" rx="8" fill="#18181d" stroke="#2e2e38"/>
    ${iconBolt(788, 323, 22, "#a78bfa")}
    <text x="822" y="331" font-size="12.5" font-weight="700" fill="#f3f4f6">match_events</text>
    <text x="822" y="349" font-size="10" fill="#9ca3af">Telemetria e eventos de partida em tempo real</text>
    <rect x="1038" y="321" width="68" height="22" rx="4" fill="#202026"/>
    <text x="1072" y="${pillTextY(321, 22, 9)}" font-size="9" font-weight="600" fill="#9ca3af" text-anchor="middle">C# Nativo</text>
    <rect x="1114" y="321" width="76" height="22" rx="11" fill="rgba(16, 185, 129, 0.15)" stroke="#10b981"/>
    <text x="1152" y="${pillTextY(321, 22, 9)}" font-size="9" font-weight="700" fill="#34d399" text-anchor="middle">✓ Ativo</text>

    <!-- Botão + New Extension -->
    ${highlightNewExt ? `
    <rect x="942" y="374" width="92" height="18" rx="9" fill="#10b981" stroke="#34d399"/>
    <text x="988" y="${pillTextY(374, 18, 9)}" font-size="9" font-weight="800" fill="#ffffff" text-anchor="middle">CLIQUE AQUI</text>
    <polygon points="984,392 992,392 988,397" fill="#10b981"/>
    <rect x="770" y="394" width="436" height="56" rx="10" fill="none" stroke="#10b981" stroke-width="2.5" stroke-dasharray="6,4"/>
    <rect x="774" y="398" width="428" height="48" rx="8" fill="#7c3aed" stroke="#c084fc" stroke-width="2"/>
    ${iconBolt(900, 411, 22, "#ffffff")}
    <text x="988" y="${pillTextY(398, 48, 13.5)}" font-size="13.5" font-weight="800" fill="#ffffff" text-anchor="middle">+ New Extension</text>
    ` : `
    <rect x="774" y="398" width="428" height="48" rx="8" fill="#6d28d9" stroke="#8b5cf6" stroke-width="1.5"/>
    ${iconBolt(900, 411, 22, "#ffffff")}
    <text x="988" y="${pillTextY(398, 48, 13.5)}" font-size="13.5" font-weight="800" fill="#ffffff" text-anchor="middle">+ New Extension</text>
    `}

    <!-- Placeholder slot below button -->
    <rect x="774" y="456" width="428" height="40" rx="6" fill="#141417" stroke="#262632" stroke-dasharray="4,4"/>
    <text x="988" y="${pillTextY(456, 40, 9.5)}" font-size="9.5" fill="#6b7280" text-anchor="middle">+ Nova extensão aparecerá aqui após criada</text>
  </g>`;
}

// ==========================================
// SLIDE 4: Unity Editor · Ênfase em + New Extension (1 Beat)
// ==========================================
function renderSlide4(step, t) {
  const e = easeOutCubic(t);

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="720" viewBox="0 0 1280 720">
  <defs>
    <style>
      text { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif; }
    </style>
  </defs>
  <rect width="1280" height="720" fill="#141417"/>
  ${renderHeader("ATO III · DA UNITY PARA A NUVEM (1/2)", "Sem sair da Unity: 1 clique para iniciar o serviço.", "Slide 5 de 10")}

  <g opacity="${e}">
    ${renderUnityEditorShell(true, 1)}

    <!-- Toast 1 Flutuante: 100% dentro da Unity -->
    <rect x="774" y="510" width="428" height="56" rx="8" fill="#141417" fill-opacity="0.95" stroke="#8b5cf6" stroke-width="1.5"/>
    ${iconBolt(790, 526, 24, "#a78bfa")}
    <text x="826" y="533" font-size="12.5" font-weight="800" fill="#ddd6fe">100% dentro da Unity</text>
    <text x="826" y="552" font-size="10.5" fill="#cbd5e1">Sem terminal, Docker ou console da nuvem.</text>

    <!-- Toast 2 Flutuante: 1 clique em + New Extension -->
    <rect x="774" y="578" width="428" height="56" rx="8" fill="#141417" fill-opacity="0.95" stroke="#10b981" stroke-width="1.5"/>
    ${iconCheck(790, 594, 24, "#10b981")}
    <text x="826" y="601" font-size="12.5" font-weight="800" fill="#34d399">1 clique em + New Extension</text>
    <text x="826" y="620" font-size="10.5" fill="#cbd5e1">Inicia o serviço C# já conectado ao jogo.</text>
  </g>
</svg>`;
}

// ==========================================
// SLIDE 5: Popup Create New Extension & Template (1 Beat)
// ==========================================
function renderSlide5(step, t) {
  const e = easeOutCubic(t);

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="720" viewBox="0 0 1280 720">
  <defs>
    <style>
      text { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif; }
      .code { font-family: Menlo, Monaco, Consolas, monospace; }
    </style>
  </defs>
  <rect width="1280" height="720" fill="#141417"/>
  ${renderHeader("ATO III · DA UNITY PARA A NUVEM (2/2)", "Um template pronto gera o serviço online na hora.", "Slide 6 de 10")}

  <g opacity="${e}">
    <!-- Fundo escurecido da Unity inteira (com o jogo mockup visível suavemente atrás) -->
    ${renderUnityEditorShell(false, 0.28)}

    <!-- Dimming Overlay adicional para destaque suave do modal -->
    <rect x="50" y="114" width="1180" height="570" rx="12" fill="rgba(10, 10, 14, 0.52)"/>

    <!-- Popup Modal Create New Extension centralizado (x=290, y=144, width=620, height=452) -->
    <rect x="290" y="144" width="620" height="452" rx="12" fill="#18181d" stroke="#8b5cf6" stroke-width="2"/>

    <!-- Header do Modal -->
    <text x="316" y="176" font-size="17" font-weight="800" fill="#f3f4f6">Create New Extension</text>
    <rect x="760" y="158" width="126" height="22" rx="11" fill="rgba(139, 92, 246, 0.2)" stroke="#8b5cf6"/>
    <text x="823" y="${pillTextY(158, 22, 9.5)}" font-size="9.5" font-weight="700" fill="#ddd6fe" text-anchor="middle">POPUP NA UNITY</text>
    <text x="316" y="196" font-size="10.5" fill="#9ca3af">Gere um módulo C# pronto direto no workspace do jogo.</text>
    <line x1="290" y1="208" x2="910" y2="208" stroke="#2e2e38" stroke-width="1"/>

    <!-- Campo 1: Extension Name -->
    <text x="316" y="228" font-size="9.5" font-weight="700" fill="#a78bfa" letter-spacing="0.5">EXTENSION NAME (ID DO SERVIÇO)</text>
    <rect x="316" y="236" width="568" height="32" rx="6" fill="#141417" stroke="#38bdf8" stroke-width="1.5"/>
    <text class="code" x="330" y="${pillTextY(236, 32, 11.5)}" font-size="11.5" font-weight="700" fill="#38bdf8">loja_itens</text>

    <!-- Campo 2: Template Selection -->
    <text x="316" y="286" font-size="9.5" font-weight="700" fill="#a78bfa" letter-spacing="0.5">TEMPLATE DA EXTENSÃO</text>

    <!-- Opção 1: Persistent Data (Resource & DB) - RECOMENDADO -->
    <rect x="316" y="296" width="568" height="62" rx="8" fill="rgba(16, 185, 129, 0.14)" stroke="#10b981" stroke-width="2"/>
    ${iconDatabase(328, 311, 24, "#34d399")}
    <text x="362" y="317" font-size="12" font-weight="800" fill="#34d399">Persistent Data (Resource &amp; DB)</text>
    <rect x="760" y="303" width="112" height="20" rx="10" fill="rgba(16, 185, 129, 0.25)" stroke="#10b981"/>
    <text x="816" y="${pillTextY(303, 20, 9)}" font-size="9" font-weight="800" fill="#6ee7b7" text-anchor="middle">RECOMENDADO</text>
    <text x="362" y="335" font-size="10" fill="#cbd5e1">Gera serviço com [ExoResource] e banco transacional em C#.</text>
    <text x="362" y="349" font-size="9.2" font-weight="600" fill="#9ca3af">Ideal para lojas de itens, inventários, carteiras e dados de jogador.</text>

    <!-- Opção 2: Basic Service -->
    <rect x="316" y="364" width="568" height="28" rx="6" fill="#18181d" stroke="#2e2e38"/>
    <text x="330" y="${pillTextY(364, 28, 10)}" font-size="10" font-weight="600" fill="#d1d5db">Basic Service</text>
    <text x="440" y="${pillTextY(364, 28, 9.5)}" font-size="9.5" fill="#6b7280">· Ações RPC simples sem persistência em banco</text>

    <!-- Opção 3: Config & State -->
    <rect x="316" y="396" width="568" height="28" rx="6" fill="#18181d" stroke="#2e2e38"/>
    <text x="330" y="${pillTextY(396, 28, 10)}" font-size="10" font-weight="600" fill="#d1d5db">Config &amp; State</text>
    <text x="440" y="${pillTextY(396, 28, 9.5)}" font-size="9.5" fill="#6b7280">· Singleton de configuração com cache em memória</text>

    <!-- Opção 4: Event Producer -->
    <rect x="316" y="428" width="568" height="28" rx="6" fill="#18181d" stroke="#2e2e38"/>
    <text x="330" y="${pillTextY(428, 28, 10)}" font-size="10" font-weight="600" fill="#d1d5db">Event Producer</text>
    <text x="440" y="${pillTextY(428, 28, 9.5)}" font-size="9.5" fill="#6b7280">· Publicação de eventos pub/sub em tempo real</text>

    <!-- Botão Roxo: Create Extension -->
    <rect x="316" y="462" width="568" height="38" rx="8" fill="#8b5cf6" stroke="#c084fc" stroke-width="1.5"/>
    ${iconBolt(525, 471, 18, "#ffffff")}
    <text x="551" y="${pillTextY(462, 38, 12.5)}" font-size="12.5" font-weight="800" fill="#ffffff">Create Extension</text>

    <!-- Card de Resultado no Modal -->
    <rect x="316" y="508" width="568" height="66" rx="8" fill="#141417" stroke="#10b981" stroke-width="1.5"/>
    ${iconCheck(330, 526, 20, "#10b981")}
    <text x="362" y="534" font-size="11.5" font-weight="800" fill="#34d399">Extensão Criada com Sucesso</text>
    <text x="362" y="552" font-size="10" fill="#f3f4f6">Gera LojaDeItens.cs pronto na Unity — sem Docker nem YAML.</text>

    <!-- Faixa Inferior: 2 Toasts Flutuantes Lado a Lado (y=614, h=54) -->
    <!-- Toast 1: Template Persistent Data -->
    <rect x="140" y="614" width="485" height="54" rx="8" fill="#141417" fill-opacity="0.95" stroke="#10b981" stroke-width="1.5"/>
    ${iconCheck(156, 629, 22, "#10b981")}
    <text x="190" y="635" font-size="12" font-weight="800" fill="#34d399">Template Persistent Data → Banco e API já prontos</text>
    <text x="190" y="653" font-size="10.5" fill="#cbd5e1">Estrutura transacional pronta para itens e ouro.</text>

    <!-- Toast 2: Gera LojaDeItens.cs -->
    <rect x="645" y="614" width="485" height="54" rx="8" fill="#141417" fill-opacity="0.95" stroke="#8b5cf6" stroke-width="1.5"/>
    ${iconBolt(661, 629, 22, "#a78bfa")}
    <text x="695" y="635" font-size="12" font-weight="800" fill="#ddd6fe">Gera LojaDeItens.cs na Unity</text>
    <text x="695" y="653" font-size="10.5" fill="#cbd5e1">Código C# pronto para a regra do jogo, sem SQL nem YAML.</text>
  </g>
</svg>`;
}

// ==========================================
// SLIDE 6: A Solução em C# (6 Beats)
// ==========================================
function renderSlide6(step, t) {
  const e = easeOutCubic(t);

  const isDbaActive = step >= 1;
  const isBackendActive = step >= 2;
  const isSegurancaActive = step >= 3;
  const isDevopsActive = step >= 4;
  const isCoreActive = step >= 5;

  const alphaDba = step === 1 ? e : (step > 1 ? 1 : 0);
  const alphaBackend = step === 2 ? e : (step > 2 ? 1 : 0);
  const alphaSeguranca = step === 3 ? e : (step > 3 ? 1 : 0);
  const alphaDevops = step === 4 ? e : (step > 4 ? 1 : 0);
  const alphaCore = step === 5 ? e : (step > 5 ? 1 : 0);

  function renderConnector(y1, y2, xMid, color, opacity) {
    if (opacity <= 0) return "";
    return `
    <g opacity="${opacity}">
      <circle cx="615" cy="${y1}" r="3.5" fill="${color}"/>
      <path d="M 615 ${y1} L ${xMid} ${y1} L ${xMid} ${y2} L 682 ${y2}" fill="none" stroke="${color}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>
      <polygon points="682,${y2 - 5} 690,${y2} 682,${y2 + 5}" fill="${color}"/>
    </g>`;
  }

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="720" viewBox="0 0 1280 720">
  <defs>
    <style>
      text { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif; }
      .code { font-family: Menlo, Monaco, Consolas, monospace; }
    </style>
  </defs>
  <rect width="1280" height="720" fill="#141417"/>
  ${renderHeader("ATO III · A SOLUÇÃO EM C#", "A Solução em Código: 21 Linhas de C# Substituem 4 Profissões.", `Etapa ${step + 1} de 6`)}

  <!-- Left Panel: LojaDeItens.cs Code Box (w=565, x=50..615 leaves 75px corridor for arrows!) -->
  <rect x="50" y="114" width="565" height="570" rx="12" fill="#18181d" stroke="#3a3a46" stroke-width="1.5"/>

  <!-- Code Header Window Controls -->
  <circle cx="72" cy="134" r="4.5" fill="#ef4444"/>
  <circle cx="88" cy="134" r="4.5" fill="#fbbf24"/>
  <circle cx="104" cy="134" r="4.5" fill="#10b981"/>
  <text x="124" y="138" font-size="12" font-weight="700" fill="#9ca3af">LojaDeItens.cs · C# 9 Unity + Exoforge SDK (21 linhas)</text>
  <line x1="50" y1="154" x2="615" y2="154" stroke="#24242c" stroke-width="1"/>

  <!-- Highlight Bands inside Code Box -->
  <!-- Band 1: Line 01 [ExoService] (DevOps - Step 4) -->
  ${alphaDevops > 0 ? `
  <rect x="52" y="162" width="561" height="21" fill="#f97316" fill-opacity="${0.25 * alphaDevops}"/>
  <line x1="52" y1="162" x2="52" y2="183" stroke="#f97316" stroke-width="4" opacity="${alphaDevops}"/>
  ` : ""}

  <!-- Band 2: Line 04 [ExoAction] (Backend - Step 2) -->
  ${alphaBackend > 0 ? `
  <rect x="52" y="225" width="561" height="21" fill="#38bdf8" fill-opacity="${0.22 * alphaBackend}"/>
  <line x1="52" y1="225" x2="52" y2="246" stroke="#38bdf8" stroke-width="4" opacity="${alphaBackend}"/>
  ` : ""}

  <!-- Band 3: Line 04 Scope = "player" (Segurança - Step 3) -->
  ${alphaSeguranca > 0 ? `
  <rect x="167" y="225" width="104" height="21" fill="#ef4444" fill-opacity="${0.34 * alphaSeguranca}"/>
  <line x1="52" y1="225" x2="52" y2="246" stroke="#ef4444" stroke-width="4" opacity="${alphaSeguranca}"/>
  ` : ""}

  <!-- Band 4: Lines 07-12 Core logic (Core Gameplay - Step 5) -->
  ${alphaCore > 0 ? `
  <rect x="52" y="288" width="561" height="126" fill="#10b981" fill-opacity="${0.20 * alphaCore}"/>
  <line x1="52" y1="288" x2="52" y2="414" stroke="#10b981" stroke-width="4" opacity="${alphaCore}"/>
  ` : ""}

  <!-- Band 5: Lines 15-21 [ExoResource] + struct (DBA - Step 1) -->
  ${alphaDba > 0 ? `
  <rect x="52" y="456" width="561" height="147" fill="#fbbf24" fill-opacity="${0.22 * alphaDba}"/>
  <line x1="52" y1="456" x2="52" y2="603" stroke="#fbbf24" stroke-width="4" opacity="${alphaDba}"/>
  ` : ""}

  <!-- Line Numbers (01..21) -->
  ${Array.from({ length: 21 }, (_, i) => {
    const ln = String(i + 1).padStart(2, "0");
    return `<text class="code" x="60" y="${176 + i * 21}" font-size="10" fill="#4b5563">${ln}</text>`;
  }).join("\n  ")}

  <!-- Exact 21 Valid C# 9 Lines (Exoforge.Plugin.SDK) -->
  <text class="code" x="84" y="176" font-size="10.4" xml:space="preserve"><tspan fill="#f97316">[ExoService</tspan><tspan fill="#9ca3af">(</tspan><tspan fill="#34d399">&quot;loja_itens&quot;</tspan><tspan fill="#9ca3af">)]</tspan></text>
  <text class="code" x="84" y="197" font-size="10.4" fill="#c084fc" xml:space="preserve">public class <tspan fill="#38bdf8">LojaDeItens</tspan></text>
  <text class="code" x="84" y="218" font-size="10.4" fill="#9ca3af">{</text>
  <text class="code" x="84" y="239" font-size="10.4" xml:space="preserve">  <tspan fill="#38bdf8">[ExoAction</tspan><tspan fill="#9ca3af">(</tspan><tspan fill="#fb7185" font-weight="700">Scope = </tspan><tspan fill="#fde68a">&quot;player&quot;</tspan><tspan fill="#38bdf8">)]</tspan></text>
  <text class="code" x="84" y="260" font-size="10.4" xml:space="preserve">  <tspan fill="#c084fc">public </tspan><tspan fill="#38bdf8">Inventario </tspan><tspan fill="#34d399">ComprarEspada</tspan><tspan fill="#9ca3af">()</tspan></text>
  <text class="code" x="84" y="281" font-size="10.4" fill="#9ca3af" xml:space="preserve">  {</text>
  <text class="code" x="84" y="302" font-size="10.4" fill="#cbd5e1" xml:space="preserve">    <tspan fill="#c084fc">var</tspan> inv = <tspan fill="#34d399">Exo.Database.Get</tspan>&lt;<tspan fill="#38bdf8">Inventario</tspan>&gt;(<tspan fill="#fb923c">Exo.Context.CallerPlayerId</tspan>);</text>
  <text class="code" x="84" y="323" font-size="10.4" fill="#cbd5e1" xml:space="preserve">    <tspan fill="#c084fc">if</tspan> (inv.Ouro &lt; <tspan fill="#34d399">500</tspan>) <tspan fill="#c084fc">throw new </tspan><tspan fill="#38bdf8">ExoActionException</tspan>(<tspan fill="#fde68a">&quot;Sem ouro!&quot;</tspan>);</text>
  <text class="code" x="84" y="344" font-size="10.4" fill="#cbd5e1" xml:space="preserve">    inv.Ouro -= <tspan fill="#34d399">500</tspan>;</text>
  <text class="code" x="84" y="365" font-size="10.4" fill="#cbd5e1" xml:space="preserve">    inv.Itens.Add(<tspan fill="#fde68a">&quot;espada_lendaria&quot;</tspan>);</text>
  <text class="code" x="84" y="386" font-size="10.4" fill="#cbd5e1" xml:space="preserve">    <tspan fill="#34d399">Exo.Database.Put</tspan>(inv);</text>
  <text class="code" x="84" y="407" font-size="10.4" fill="#cbd5e1" xml:space="preserve">    <tspan fill="#c084fc">return</tspan> inv;</text>
  <text class="code" x="84" y="428" font-size="10.4" fill="#9ca3af" xml:space="preserve">  }</text>
  <text class="code" x="84" y="449" font-size="10.4" fill="#9ca3af">}</text>
  <text class="code" x="84" y="470" font-size="10.4" xml:space="preserve"><tspan fill="#fbbf24">[ExoResource]</tspan></text>
  <text class="code" x="84" y="491" font-size="10.4" fill="#c084fc" xml:space="preserve">public struct <tspan fill="#38bdf8">Inventario</tspan></text>
  <text class="code" x="84" y="512" font-size="10.4" fill="#9ca3af">{</text>
  <text class="code" x="84" y="533" font-size="10.4" fill="#cbd5e1" xml:space="preserve">  <tspan fill="#c084fc">public </tspan><tspan fill="#38bdf8">string </tspan>Id;</text>
  <text class="code" x="84" y="554" font-size="10.4" fill="#cbd5e1" xml:space="preserve">  <tspan fill="#c084fc">public </tspan><tspan fill="#38bdf8">int </tspan>Ouro;</text>
  <text class="code" x="84" y="575" font-size="10.4" fill="#cbd5e1" xml:space="preserve">  <tspan fill="#c084fc">public </tspan><tspan fill="#38bdf8">List</tspan>&lt;<tspan fill="#38bdf8">string</tspan>&gt; Itens;</text>
  <text class="code" x="84" y="596" font-size="10.4" fill="#9ca3af">}</text>

  <!-- Left Code Summary Pill -->
  <rect x="66" y="626" width="533" height="38" rx="6" fill="#141417" stroke="#3a3a46"/>
  <text x="332" y="${pillTextY(626, 38, 10.8)}" font-size="10.8" font-weight="700" fill="#34d399" text-anchor="middle">21 Linhas (vs. ~180 manuais) · Code Red (2022): código enxuto evita 15x mais bugs</text>

  <!-- Wide 75px Orthogonal Stepped Connectors (615 -> 690) -->
  ${renderConnector(172, 162, 660, "#f97316", alphaDevops)}
  ${renderConnector(232, 274, 652, "#38bdf8", alphaBackend)}
  ${renderConnector(240, 386, 638, "#ef4444", alphaSeguranca)}
  ${renderConnector(351, 504, 652, "#10b981", alphaCore)}
  ${renderConnector(528, 629, 660, "#fbbf24", alphaDba)}

  <!-- Right Panel: 5 Stacked Callout Cards (Top-to-Bottom matching code lines 1..21) -->
  <!-- Card 1: ELIMINA PAPEL DEVOPS (y=114..210) -->
  <rect x="690" y="114" width="540" height="96" rx="10" fill="#1e1e24" stroke="${isDevopsActive ? '#f97316' : '#262630'}" stroke-width="${isDevopsActive ? '2' : '1'}" opacity="${isDevopsActive ? 1 : 0.4}"/>
  <rect x="710" y="128" width="168" height="20" rx="4" fill="#18181d" stroke="#f97316"/>
  <text x="794" y="${pillTextY(128, 20, 9.5)}" font-size="9.5" font-weight="700" fill="#f97316" text-anchor="middle">ELIMINA PAPEL DEVOPS</text>
  <text x="890" y="${pillTextY(128, 20, 11)}" font-size="11" font-weight="600" fill="#9ca3af">[ExoService] · Linha 1</text>
  <text x="710" y="172" font-size="14.5" font-weight="700" fill="#f3f4f6">Publicação na Nuvem em 1 Clique</text>
  <text x="710" y="194" font-size="11.5" fill="#9ca3af">Publica direto da Unity, sem containers ou pipelines.</text>

  <!-- Card 2: ELIMINA PAPEL BACKEND (y=226..322) -->
  <rect x="690" y="226" width="540" height="96" rx="10" fill="#1e1e24" stroke="${isBackendActive ? '#38bdf8' : '#262630'}" stroke-width="${isBackendActive ? '2' : '1'}" opacity="${isBackendActive ? 1 : 0.4}"/>
  <rect x="710" y="240" width="178" height="20" rx="4" fill="#18181d" stroke="#38bdf8"/>
  <text x="799" y="${pillTextY(240, 20, 9.5)}" font-size="9.5" font-weight="700" fill="#38bdf8" text-anchor="middle">ELIMINA PAPEL BACKEND</text>
  <text x="900" y="${pillTextY(240, 20, 11)}" font-size="11" font-weight="600" fill="#9ca3af">[ExoAction] · Linha 4 · Nome inferido</text>
  <text x="710" y="284" font-size="14.5" font-weight="700" fill="#f3f4f6">Conexão Automática com a Unity</text>
  <text x="710" y="306" font-size="11.5" fill="#9ca3af">Expõe a ação para a Unity sem rotas manuais.</text>

  <!-- Card 3: ELIMINA PAPEL SEGURANÇA (y=338..434) -->
  <rect x="690" y="338" width="540" height="96" rx="10" fill="#1e1e24" stroke="${isSegurancaActive ? '#ef4444' : '#262630'}" stroke-width="${isSegurancaActive ? '2' : '1'}" opacity="${isSegurancaActive ? 1 : 0.4}"/>
  <rect x="710" y="352" width="190" height="20" rx="4" fill="#18181d" stroke="#ef4444"/>
  <text x="805" y="${pillTextY(352, 20, 9.5)}" font-size="9.5" font-weight="700" fill="#ef4444" text-anchor="middle">ELIMINA PAPEL SEGURANÇA</text>
  <text x="912" y="${pillTextY(352, 20, 10.2)}" font-size="10.2" font-weight="600" fill="#9ca3af">Scope = &quot;player&quot; · Irdeto/Forbes: 77% largam cheats</text>
  <text x="710" y="396" font-size="14.5" font-weight="700" fill="#f3f4f6">Proteção Anti-Cheat por Padrão</text>
  <text x="710" y="418" font-size="11.5" fill="#9ca3af">Só o jogador autenticado altera seu saldo.</text>

  <!-- Card 4: CORE GAMEPLAY · C# 9 (y=450..558) -->
  <rect x="690" y="450" width="540" height="108" rx="10" fill="#1e1e24" stroke="${isCoreActive ? '#10b981' : '#262630'}" stroke-width="${isCoreActive ? '2' : '1'}" opacity="${isCoreActive ? 1 : 0.4}"/>
  <rect x="710" y="464" width="165" height="20" rx="4" fill="#18181d" stroke="#10b981"/>
  <text x="792" y="${pillTextY(464, 20, 9.5)}" font-size="9.5" font-weight="700" fill="#10b981" text-anchor="middle">CORE GAMEPLAY · C# 9</text>
  <text x="885" y="${pillTextY(464, 20, 10.2)}" font-size="10.2" font-weight="600" fill="#34d399">Linhas 7–12 · Code Red 2022 (39 empresas)</text>
  <text x="710" y="506" font-size="15.5" font-weight="800" fill="#f3f4f6">Foco 100% no Gameplay</text>
  <text x="710" y="528" font-size="11" fill="#d1d5db">Código enxuto só no jogo evita 15x mais bugs e +124% de atraso.</text>
  <text x="710" y="546" font-size="10.5" font-weight="600" fill="#34d399">Apenas a regra do ouro e da espada — o resto é gerenciado pelo Exoforge.</text>

  <!-- Card 5: ELIMINA PAPEL DBA (y=574..684) -->
  <rect x="690" y="574" width="540" height="110" rx="10" fill="#1e1e24" stroke="${isDbaActive ? '#fbbf24' : '#262630'}" stroke-width="${isDbaActive ? '2' : '1'}" opacity="${isDbaActive ? 1 : 0.4}"/>
  <rect x="710" y="590" width="150" height="20" rx="4" fill="#18181d" stroke="#fbbf24"/>
  <text x="785" y="${pillTextY(590, 20, 9.5)}" font-size="9.5" font-weight="700" fill="#fbbf24" text-anchor="middle">ELIMINA PAPEL DBA</text>
  <text x="872" y="${pillTextY(590, 20, 11)}" font-size="11" font-weight="600" fill="#9ca3af">[ExoResource] · Linhas 15–21</text>
  <text x="710" y="636" font-size="14.5" font-weight="700" fill="#f3f4f6">Persistência Segura Sem SQL</text>
  <text x="710" y="658" font-size="11.5" fill="#9ca3af">Salva ouro e itens em banco transacional, sem SQL.</text>
</svg>`;
}

// ==========================================
// SLIDE 7: Operação Gerenciada pelo Exoforge (4 Beats)
// ==========================================
function renderSlide7(step, t) {
  const e = easeOutCubic(t);

  const isCard2Active = step >= 1;
  const isCard3Active = step >= 2;
  const isCard4Active = step >= 3;

  const alpha2 = step === 1 ? e : (step > 1 ? 1 : 0.35);
  const alpha3 = step === 2 ? e : (step > 2 ? 1 : 0.35);
  const alpha4 = step === 3 ? e : (step > 3 ? 1 : 0.35);

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="720" viewBox="0 0 1280 720">
  <defs>
    <style>
      text { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif; }
    </style>
  </defs>
  <rect width="1280" height="720" fill="#141417"/>
  ${renderHeader("ATO III · OPERAÇÃO GERENCIADA", "Operação Enterprise: Painel, Logs e Escala sem Escrever Infra.", `Etapa ${step + 1} de 4`)}

  <!-- Card 1: Top-Left (Beat 19 / Step 0) -> Producer Studio -->
  <g>
    <rect x="50" y="114" width="575" height="270" rx="10" fill="#1e1e24" stroke="#8b5cf6" stroke-width="2"/>
    <rect x="70" y="128" width="165" height="22" rx="4" fill="#18181d" stroke="#8b5cf6"/>
    <text x="152" y="${pillTextY(128, 22, 10)}" font-size="10" font-weight="700" fill="#a78bfa" text-anchor="middle">INTERFACE PRONTA · DIA 1</text>
    <text x="70" y="172" font-size="15.5" font-weight="700" fill="#f3f4f6">Painel Ao Vivo (Producer Studio)</text>

    <rect x="475" y="128" width="130" height="22" rx="11" fill="rgba(139, 92, 246, 0.2)" stroke="#8b5cf6"/>
    <text x="540" y="${pillTextY(128, 22, 10.5)}" font-size="10.5" font-weight="700" fill="#ddd6fe" text-anchor="middle">Painel Nativo</text>

    <!-- Mini SVG Table Preview -->
    <rect x="70" y="188" width="535" height="134" rx="6" fill="#141417" stroke="#2e2e38"/>
    <text x="85" y="207" font-size="10" font-weight="700" fill="#9ca3af">ITEM DO JOGO</text>
    <text x="235" y="207" font-size="10" font-weight="700" fill="#9ca3af">CATEGORIA</text>
    <text x="360" y="207" font-size="10" font-weight="700" fill="#9ca3af">PREÇO</text>
    <text x="490" y="207" font-size="10" font-weight="700" fill="#9ca3af">STATUS</text>
    <line x1="70" y1="216" x2="605" y2="216" stroke="#24242c" stroke-width="1"/>

    <text x="85" y="${pillTextY(226, 18, 11)}" font-size="11" font-weight="600" fill="#f3f4f6">espada_lendaria</text>
    <text x="235" y="${pillTextY(226, 18, 11)}" font-size="11" fill="#9ca3af">Armas</text>
    <text x="360" y="${pillTextY(226, 18, 11)}" font-size="11" font-weight="700" fill="#fbbf24">500 Ouro</text>
    <rect x="490" y="226" width="60" height="18" rx="9" fill="rgba(16, 185, 129, 0.2)"/>
    <text x="520" y="${pillTextY(226, 18, 9.5)}" font-size="9.5" font-weight="700" fill="#34d399" text-anchor="middle">Ativo</text>

    <text x="85" y="${pillTextY(254, 18, 11)}" font-size="11" font-weight="600" fill="#f3f4f6">escudo_guardiao</text>
    <text x="235" y="${pillTextY(254, 18, 11)}" font-size="11" fill="#9ca3af">Defesa</text>
    <text x="360" y="${pillTextY(254, 18, 11)}" font-size="11" font-weight="700" fill="#fbbf24">350 Ouro</text>
    <rect x="490" y="254" width="60" height="18" rx="9" fill="rgba(16, 185, 129, 0.2)"/>
    <text x="520" y="${pillTextY(254, 18, 9.5)}" font-size="9.5" font-weight="700" fill="#34d399" text-anchor="middle">Ativo</text>

    <text x="85" y="${pillTextY(282, 18, 11)}" font-size="11" font-weight="600" fill="#f3f4f6">pocao_vida_gg</text>
    <text x="235" y="${pillTextY(282, 18, 11)}" font-size="11" fill="#9ca3af">Poções</text>
    <text x="360" y="${pillTextY(282, 18, 11)}" font-size="11" font-weight="700" fill="#fbbf24">50 Ouro</text>
    <rect x="490" y="282" width="60" height="18" rx="9" fill="rgba(16, 185, 129, 0.2)"/>
    <text x="520" y="${pillTextY(282, 18, 9.5)}" font-size="9.5" font-weight="700" fill="#34d399" text-anchor="middle">Ativo</text>

    <text x="70" y="346" font-size="11" fill="#a78bfa">Game designers consultam itens e saldos sem construir painel interno.</text>
    <text x="70" y="366" font-size="9.2" font-weight="600" fill="#9ca3af"><tspan fill="#ddd6fe">Team Topologies (Skelton &amp; Pais, 2019):</tspan> plataforma pronta evita sobrecarga do time.</text>
  </g>

  <!-- Card 2: Top-Right (Beat 20 / Step 1) -> Tabela Simplificada de Logs Seguindo o Fluxo -->
  <g opacity="${alpha2}">
    <rect x="655" y="114" width="575" height="270" rx="10" fill="#1e1e24" stroke="${isCard2Active ? '#10b981' : '#262630'}" stroke-width="${isCard2Active ? '2' : '1'}"/>
    <rect x="675" y="128" width="150" height="22" rx="4" fill="#18181d" stroke="#10b981"/>
    <text x="750" y="${pillTextY(128, 22, 10)}" font-size="10" font-weight="700" fill="#34d399" text-anchor="middle">LOGS EM FLUXO</text>
    <text x="675" y="172" font-size="15.5" font-weight="700" fill="#f3f4f6">Tabela de Logs Seguindo o Fluxo</text>

    <rect x="1065" y="128" width="145" height="22" rx="11" fill="rgba(16, 185, 129, 0.2)" stroke="#10b981"/>
    <text x="1137" y="${pillTextY(128, 22, 10.5)}" font-size="10.5" font-weight="700" fill="#34d399" text-anchor="middle">Replay 1 Clique</text>

    <!-- Flow Log Table Box -->
    <rect x="675" y="188" width="535" height="140" rx="6" fill="#141417" stroke="#2e2e38"/>
    <text x="692" y="207" font-size="9.5" font-weight="700" fill="#9ca3af">ETAPA DO FLUXO</text>
    <text x="815" y="207" font-size="9.5" font-weight="700" fill="#9ca3af">O QUE ACONTECEU</text>
    <text x="1110" y="207" font-size="9.5" font-weight="700" fill="#9ca3af">RESULTADO</text>
    <line x1="675" y1="215" x2="1210" y2="215" stroke="#24242c" stroke-width="1"/>

    <!-- Flow Row 1 (y=222..250) -->
    <rect x="685" y="222" width="515" height="28" rx="4" fill="#1e1e24" stroke="#2e2e38"/>
    <text x="695" y="${pillTextY(222, 28, 10.5)}" font-size="10.5" font-weight="700" fill="#93c5fd">1. Pedido →</text>
    <text x="815" y="${pillTextY(222, 28, 10.5)}" font-size="10.5" fill="#f3f4f6">Lucas clicou &quot;Comprar Espada&quot;</text>
    <text x="1110" y="${pillTextY(222, 28, 10.5)}" font-size="10.5" font-weight="700" fill="#34d399">✓ Recebido</text>

    <!-- Flow Row 2 (y=256..284) -->
    <rect x="685" y="256" width="515" height="28" rx="4" fill="#1e1e24" stroke="#2e2e38"/>
    <text x="695" y="${pillTextY(256, 28, 10.5)}" font-size="10.5" font-weight="700" fill="#fde68a">2. Saldo ↓</text>
    <text x="815" y="${pillTextY(256, 28, 10.5)}" font-size="10.5" fill="#f3f4f6">Carteira: 500 Ouro descontados</text>
    <text x="1110" y="${pillTextY(256, 28, 10.5)}" font-size="10.5" font-weight="700" fill="#34d399">✓ Validado</text>

    <!-- Flow Row 3 (y=290..318) -->
    <rect x="685" y="290" width="515" height="28" rx="4" fill="#1e1e24" stroke="#10b981" stroke-opacity="0.6"/>
    <text x="695" y="${pillTextY(290, 28, 10.5)}" font-size="10.5" font-weight="700" fill="#6ee7b7">3. Entrega ✓</text>
    <text x="815" y="${pillTextY(290, 28, 10.5)}" font-size="10.5" fill="#f3f4f6">Espada salva no inventário</text>
    <rect x="1095" y="294" width="96" height="20" rx="10" fill="#10b981"/>
    ${iconReplay(1115, 298, 12, "#ffffff")}
    <text x="1133" y="${pillTextY(294, 20, 9.5)}" font-size="9.5" font-weight="700" fill="#ffffff">Replay</text>

    <text x="675" y="346" font-size="11" fill="#34d399">Cada passo do jogador vira um log legível, com reexecução em 1 clique.</text>
    <text x="675" y="366" font-size="9.2" font-weight="600" fill="#9ca3af"><tspan fill="#ddd6fe">DevEx (Noda et al., ACM Queue 2023):</tspan> feedback rápido mantém produtividade do time.</text>
  </g>

  <!-- Card 3: Bottom-Left (Beat 21 / Step 2) -> Grafo de Escalabilidade -->
  <g opacity="${alpha3}">
    <rect x="50" y="406" width="575" height="278" rx="10" fill="#1e1e24" stroke="${isCard3Active ? '#38bdf8' : '#262630'}" stroke-width="${isCard3Active ? '2' : '1'}"/>
    <rect x="70" y="420" width="160" height="22" rx="4" fill="#18181d" stroke="#38bdf8"/>
    <text x="150" y="${pillTextY(420, 22, 10)}" font-size="10" font-weight="700" fill="#38bdf8" text-anchor="middle">ESCALA AUTOMÁTICA</text>
    <text x="70" y="464" font-size="15.5" font-weight="700" fill="#f3f4f6">Escalabilidade do Dia 1 ao Pico de Acesso</text>

    <rect x="465" y="420" width="140" height="22" rx="11" fill="rgba(56, 189, 248, 0.2)" stroke="#38bdf8"/>
    <text x="535" y="${pillTextY(420, 22, 10.5)}" font-size="10.5" font-weight="700" fill="#38bdf8" text-anchor="middle">Sem Config Manual</text>

    <!-- Scalability Graph Box -->
    <rect x="70" y="480" width="535" height="136" rx="6" fill="#111116" stroke="#2e2e38"/>

    <!-- Graph Axes and Gridlines -->
    <line x1="118" y1="588" x2="582" y2="588" stroke="#2e2e38" stroke-width="1.5"/>
    <line x1="118" y1="494" x2="118" y2="588" stroke="#2e2e38" stroke-width="1.5"/>
    <text x="95" y="544" font-size="9.5" fill="#9ca3af" text-anchor="middle" transform="rotate(-90 95 544)">Capacidade</text>

    <!-- Red Failing Line: Servidor comum cai no pico -->
    <path d="M 134 578 L 245 562 L 350 544 L 385 582" fill="none" stroke="#ef4444" stroke-width="2.2" stroke-dasharray="5,4"/>
    <circle cx="385" cy="582" r="4" fill="#ef4444"/>
    <text x="394" y="584" font-size="10" font-weight="700" fill="#fca5a5">✕ Servidor comum cai no pico</text>

    <!-- Connected Scaling Graph: Exoforge cresce junto -->
    <path d="M 134 578 L 260 554 L 405 530 L 555 504" fill="none" stroke="#10b981" stroke-width="2.8"/>
    <circle cx="134" cy="578" r="5" fill="#38bdf8" stroke="#111116" stroke-width="1.5"/>
    <circle cx="260" cy="554" r="5.5" fill="#8b5cf6" stroke="#111116" stroke-width="1.5"/>
    <circle cx="405" cy="530" r="6" fill="#10b981" stroke="#111116" stroke-width="1.5"/>
    <circle cx="555" cy="504" r="6.5" fill="#34d399" stroke="#ffffff" stroke-width="1.8"/>

    <text x="142" y="605" font-size="9.5" font-weight="600" fill="#93c5fd" text-anchor="middle">100</text>
    <text x="260" y="605" font-size="9.5" font-weight="600" fill="#ddd6fe" text-anchor="middle">10 mil</text>
    <text x="405" y="605" font-size="9.5" font-weight="600" fill="#6ee7b7" text-anchor="middle">50 mil</text>
    <text x="535" y="605" font-size="9.5" font-weight="700" fill="#34d399" text-anchor="middle">100 mil+ online ✓</text>
    <text x="560" y="498" font-size="9.8" font-weight="700" fill="#6ee7b7" text-anchor="end">Exoforge: Auto-scale (100 a 100k+ online)</text>

    <text x="70" y="638" font-size="11" fill="#38bdf8">Se o jogo viralizar no lançamento, a estrutura cresce sem derrubar jogadores.</text>
    <text x="70" y="658" font-size="9.2" font-weight="600" fill="#9ca3af"><tspan fill="#ddd6fe">Unity Gaming Report (2024):</tspan> 68% dos estúdios criam multiplayer; 37% travam ao integrar.</text>
  </g>

  <!-- Card 4: Bottom-Right (Beat 22 / Step 3) -> Downtime para leigos -->
  <g opacity="${alpha4}">
    <rect x="655" y="406" width="575" height="278" rx="10" fill="#1e1e24" stroke="${isCard4Active ? '#fbbf24' : '#262630'}" stroke-width="${isCard4Active ? '2' : '1'}"/>
    <rect x="675" y="420" width="140" height="22" rx="4" fill="#18181d" stroke="#fbbf24"/>
    <text x="745" y="${pillTextY(420, 22, 10)}" font-size="10" font-weight="700" fill="#fbbf24" text-anchor="middle">SEM QUEDAS</text>
    <text x="675" y="464" font-size="15.5" font-weight="700" fill="#f3f4f6">Atualização Sem Derrubar Quem Joga</text>

    <rect x="1065" y="420" width="145" height="22" rx="11" fill="rgba(16, 185, 129, 0.2)" stroke="#10b981"/>
    <text x="1137" y="${pillTextY(420, 22, 10.5)}" font-size="10.5" font-weight="700" fill="#34d399" text-anchor="middle">Upload &lt; 1 seg</text>

    <!-- Visual Comparison Box -->
    <rect x="675" y="480" width="535" height="136" rx="6" fill="#141417" stroke="#2e2e38"/>
    <text x="692" y="502" font-size="11" font-weight="700" fill="#fde68a">Downtime = tempo em que o jogo precisa fechar para atualizar.</text>

    <!-- Comparison 1: Upload time -->
    <rect x="692" y="516" width="500" height="40" rx="5" fill="#1e1e24" stroke="#2e2e38"/>
    <text x="706" y="534" font-size="11" font-weight="700" fill="#f3f4f6">Tempo de Upload</text>
    <text x="706" y="549" font-size="9.5" fill="#9ca3af">Enviar correção para produção</text>
    <text x="1032" y="${pillTextY(523, 26, 10.5)}" font-size="10.5" fill="#fca5a5" text-anchor="end">Comum: horas subindo servidor</text>
    <rect x="1044" y="523" width="136" height="26" rx="13" fill="rgba(16, 185, 129, 0.18)" stroke="#10b981"/>
    <text x="1112" y="${pillTextY(523, 26, 10.5)}" font-size="10.5" font-weight="700" fill="#34d399" text-anchor="middle">Exoforge: &lt; 1 seg</text>

    <!-- Comparison 2: Time offline -->
    <rect x="692" y="564" width="500" height="40" rx="5" fill="#1e1e24" stroke="#2e2e38"/>
    <text x="706" y="582" font-size="11" font-weight="700" fill="#f3f4f6">Tempo Fora do Ar</text>
    <text x="706" y="597" font-size="9.5" fill="#9ca3af">Partida interrompida por manutenção</text>
    <text x="1032" y="${pillTextY(571, 26, 10.5)}" font-size="10.5" fill="#fca5a5" text-anchor="end">Comum: derruba quem joga</text>
    <rect x="1044" y="571" width="136" height="26" rx="13" fill="rgba(16, 185, 129, 0.18)" stroke="#10b981"/>
    <text x="1112" y="${pillTextY(571, 26, 10.5)}" font-size="10.5" font-weight="700" fill="#34d399" text-anchor="middle">0s · Ninguém cai</text>

    <text x="675" y="642" font-size="11" fill="#fbbf24">Zero Downtime: atualizações ao vivo sem derrubar jogadores.</text>
    <text x="675" y="662" font-size="9.2" font-weight="600" fill="#9ca3af"><tspan fill="#ddd6fe">Tornhill &amp; Borg (2022 · 39 sistemas):</tspan> código enxuto sem infra complexa reduz falhas em 15x.</text>
  </g>
</svg>`;
}

// ==========================================
// SLIDE 8: Impacto no Negócio (2 Beats)
// ==========================================
function renderSlide8(step, t) {
  const e = easeOutCubic(t);
  const heroOpacity = step >= 1 ? (step === 1 ? e : 1) : 0;
  const heroY = step >= 1 ? Math.round(544 - 20 * (1 - e)) : 544;

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="720" viewBox="0 0 1280 720">
  <defs>
    <style>
      text { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif; }
    </style>
  </defs>
  <rect width="1280" height="720" fill="#141417"/>
  ${renderHeader("ATO III · IMPACTO NO NEGÓCIO", "O Retorno Econômico: De Semanas Perdidas para Lançamento no Mesmo Dia.", `Etapa ${step + 1} de 2`)}

  <!-- Left: Traditional Scorecard Column -->
  <rect x="50" y="114" width="575" height="395" rx="10" fill="#1e1e24" stroke="#ef4444" stroke-width="1.5"/>
  <text x="80" y="152" font-size="20" font-weight="700" fill="#f87171">Jeito Tradicional</text>
  <rect x="420" y="132" width="185" height="26" rx="4" fill="rgba(239, 68, 68, 0.2)"/>
  <text x="512" y="${pillTextY(132, 26, 11)}" font-size="11" font-weight="700" fill="#f87171" text-anchor="middle">ALTO ATRITO &amp; CUSTO</text>

  <!-- Item 1 -->
  ${iconUsers(80, 186, 22, "#f87171")}
  <text x="115" y="196" font-size="14.5" font-weight="700" fill="#f3f4f6">4 papéis extras fora do jogo</text>
  <text x="115" y="218" font-size="11" fill="#9ca3af">DBA, Backend, Segurança e DevOps (<tspan fill="#ddd6fe">GDC 2024:</tspan> só 16% fazem live-service).</text>

  <!-- Item 2 -->
  ${iconAlert(80, 252, 22, "#f87171")}
  <text x="115" y="262" font-size="14.5" font-weight="700" fill="#f3f4f6">~180 linhas de infra e troca de contexto</text>
  <text x="115" y="284" font-size="11" fill="#9ca3af">Cada interrupção leva <tspan fill="#ddd6fe">25m26s</tspan> para retomar (<tspan fill="#ddd6fe">Mark et al., ACM CHI 2005</tspan>).</text>

  <!-- Item 3 -->
  ${iconClock(80, 318, 22, "#f87171")}
  <text x="115" y="328" font-size="14.5" font-weight="700" fill="#f3f4f6">15x mais bugs e +124% de atraso</text>
  <text x="115" y="350" font-size="11" fill="#9ca3af">Manter ~180 linhas extras gera código inchado (<tspan fill="#ddd6fe">Code Red 2022 · 39 sistemas</tspan>).</text>

  <line x1="80" y1="380" x2="595" y2="380" stroke="#2e2e38" stroke-width="1"/>
  <rect x="75" y="394" width="525" height="98" rx="8" fill="#18181d" stroke="#2e2e38"/>
  <text x="92" y="416" font-size="11.5" font-weight="700" fill="#9ca3af">Prazo Reportado no Setor (sem plataforma):</text>
  <text x="92" y="435" font-size="10.2" fill="#ddd6fe">Unity Report (2024): ciclos +39% (218 → 304d); case Triangle Factory: semanas → dias</text>
  <text x="337" y="479" font-size="30" font-weight="800" fill="#ef4444" text-anchor="middle">Dias a Semanas</text>

  <!-- Right: Exoforge Scorecard Column -->
  <rect x="655" y="114" width="575" height="395" rx="10" fill="#1e1e24" stroke="#10b981" stroke-width="2"/>
  <text x="685" y="152" font-size="20" font-weight="700" fill="#34d399">Com Exoforge</text>
  <rect x="1035" y="132" width="175" height="26" rx="4" fill="rgba(16, 185, 129, 0.2)"/>
  <text x="1122" y="${pillTextY(132, 26, 11)}" font-size="11" font-weight="700" fill="#34d399" text-anchor="middle">FOCO TOTAL NO JOGO</text>

  <!-- Item 1 -->
  ${iconCheck(685, 186, 22, "#34d399")}
  <text x="720" y="196" font-size="14.5" font-weight="700" fill="#f3f4f6">Operação de infra gerenciada pelo Exoforge</text>
  <text x="720" y="218" font-size="11.5" fill="#9ca3af">Banco, API, proteção anti-cheat e nuvem operados desde o Dia 1.</text>

  <!-- Item 2 -->
  ${iconBolt(685, 252, 22, "#34d399")}
  <text x="720" y="262" font-size="14.5" font-weight="700" fill="#f3f4f6">21 linhas em 1 arquivo (C# na Unity)</text>
  <text x="720" y="284" font-size="11" fill="#9ca3af">89% menos código mantido · fluxo contínuo (<tspan fill="#ddd6fe">DevEx, ACM Queue 2023</tspan>).</text>

  <!-- Item 3 -->
  ${iconGamepad(685, 318, 22, "#34d399")}
  <text x="720" y="328" font-size="14.5" font-weight="700" fill="#f3f4f6">Equipe extra de infraestrutura: Zero</text>
  <text x="720" y="350" font-size="11" fill="#9ca3af">Time enxuto focado só em diversão (<tspan fill="#ddd6fe">Team Topologies, 2019</tspan>).</text>

  <line x1="685" y1="380" x2="1200" y2="380" stroke="#2e2e38" stroke-width="1"/>
  <rect x="680" y="394" width="525" height="98" rx="8" fill="rgba(139, 92, 246, 0.14)" stroke="#8b5cf6"/>
  <text x="697" y="416" font-size="11.5" font-weight="700" fill="#9ca3af">Da Regra de Gameplay à Produção:</text>
  <text x="697" y="435" font-size="10.2" fill="#ddd6fe">Código enxuto no jogo + infra em plataforma evitam +124% de atraso e 15x mais bugs (Code Red &apos;22)</text>
  <text x="942" y="479" font-size="30" font-weight="800" fill="#10b981" text-anchor="middle">No Mesmo Dia</text>

  <!-- Hero CTA Banner (Beat 24) -->
  ${heroOpacity > 0 ? `
  <g transform="translate(0, ${heroY - 524})" opacity="${heroOpacity}">
    <rect x="50" y="524" width="1180" height="160" rx="12" fill="#18181d" stroke="#8b5cf6" stroke-width="2"/>
    ${renderPortrait("p_s5_shipping", IMG_SHIPPING, 70, 540, 128, 128, 10, "#8b5cf6")}

    <text x="220" y="570" font-size="20" font-weight="800" fill="#ffffff">EXOFORGE — Você descreve a sua ideia. Nós forjamos o resto.</text>
    <text x="220" y="596" font-size="13.5" fill="#9ca3af">Da regra da Loja de Itens ao jogo no ar — com operação de infra gerenciada pelo Exoforge.</text>

    <!-- 3 Executive Badges -->
    <rect x="220" y="620" width="210" height="32" rx="16" fill="#262630" stroke="#10b981"/>
    <text x="325" y="${pillTextY(620, 32, 12)}" font-size="12" font-weight="700" fill="#34d399" text-anchor="middle">Escala Automática</text>

    <rect x="445" y="620" width="220" height="32" rx="16" fill="#262630" stroke="#8b5cf6"/>
    <text x="555" y="${pillTextY(620, 32, 12)}" font-size="12" font-weight="700" fill="#ddd6fe" text-anchor="middle">Zero Tempo Fora do Ar</text>

    <rect x="680" y="620" width="185" height="32" rx="16" fill="#262630" stroke="#38bdf8"/>
    <text x="772" y="${pillTextY(620, 32, 12)}" font-size="12" font-weight="700" fill="#93c5fd" text-anchor="middle">Devs de Infra: Zero</text>
  </g>` : ""}
</svg>`;
}

// ==========================================
// SLIDE 9: Bibliografia & Fontes (1 Beat)
// ==========================================
function renderSlide9(step, t) {
  const e = easeOutCubic(t);

  const industryRefs = [
    { tag: "Slides 3, 4, 8, 9", title: "1. Unity Gaming Report (2024)", desc: "68% multiplayer; ciclos +39% (218→304d); 37% travam integrando; semanas → dias.", url: "create.unity.com/gaming-report-2024" },
    { tag: "Slides 3, 9", title: "2. GDC State of the Game Industry (2024)", desc: "Custo e complexidade restringem live-service a apenas 16% dos estúdios.", url: "reg.gdconf.com/state-of-game-industry-2024" },
    { tag: "Slides 3, 7", title: "3. Irdeto Global Gaming Survey / Forbes (2018)", desc: "77% abandonam jogos multiplayer com cheats e 48% compram menos itens.", url: "forbes.com/sites/panosmourdoukoutas/report-cheating-online-gaming" },
    { tag: "Base Histórica", title: "4. Stripe &amp; Harris Poll (2018)", desc: "17,3h/sem (42% da semana) gastas em manutenção e dívida técnica.", url: "stripe.com/reports/the-developer-coefficient.pdf" },
    { tag: "Base Histórica", title: "5. GitLab Global DevSecOps (2024)", desc: "76%–79% do ciclo fora de escrita de código novo (+5.300 devs).", url: "about.gitlab.com/developer-survey/" },
  ];

  const academicRefs = [
    { tag: "Slides 3, 4", title: "6. Politowski et al. (2021 · 200 Jogos)", desc: "927 problemas em postmortems reais de jogos (produção e sobrecarga).", url: "arxiv.org/abs/2009.02440" },
    { tag: "Slides 7, 8, 9", title: "7. Tornhill &amp; Borg — Code Red ('22)", desc: "Código inchado e complexo gera 15x mais bugs e +124% de atraso (39 sistemas).", url: "arxiv.org/abs/2203.04374" },
    { tag: "Slides 3, 9", title: "8. Mark, Gonzalez &amp; Harris (CHI '05/'08)", desc: "25m26s para retomar tarefa após interrupção (+ estresse medido).", url: "ics.uci.edu/~gmark/CHI2005.pdf" },
    { tag: "Slide 3", title: "9. Parnin &amp; Rugaber (2011 · SQJ)", desc: "Só 10% retomam código em &lt; 1m (10.000 sessões gravadas).", url: "link.springer.com/article/10.1007/s11219-010-9104-9" },
    { tag: "Slides 2, 8, 9", title: "10. Noda ('23), Leroy ('09) &amp; Team Topologies", desc: "DevEx (fluxo + feedback), resíduo de atenção e plataforma pronta.", url: "queue.acm.org/detail.cfm?id=3595878" },
  ];

  function renderRefList(items, xStart, accent) {
    return items.map((item, idx) => {
      const y = 168 + idx * 98;
      const urlFontSize = item.url.length > 55 ? "9.2" : "9.5";
      return `
      <rect x="${xStart}" y="${y}" width="535" height="86" rx="8" fill="#18181d" stroke="#2e2e38"/>
      <text x="${xStart + 14}" y="${y + 23}" font-size="11.8" font-weight="700" fill="#f3f4f6">${item.title}</text>
      <rect x="${xStart + 408}" y="${y + 10}" width="114" height="20" rx="10" fill="#262630" stroke="${accent}"/>
      <text x="${xStart + 465}" y="${pillTextY(y + 10, 20, 9.2)}" font-size="9.2" font-weight="700" fill="${accent}" text-anchor="middle">${item.tag}</text>
      <text x="${xStart + 14}" y="${y + 47}" font-size="10.4" fill="#cbd5e1">${item.desc}</text>
      <text x="${xStart + 14}" y="${y + 70}" font-family="Menlo, Monaco, Consolas, monospace" font-size="${urlFontSize}" fill="#93c5fd">${item.url}</text>`;
    }).join("");
  }

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="720" viewBox="0 0 1280 720">
  <defs>
    <style>
      text { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif; }
    </style>
  </defs>
  <rect width="1280" height="720" fill="#141417"/>
  ${renderHeader("APÊNDICE · FONTES VERIFICÁVEIS", "Bibliografia & Fontes Verificáveis", "Slide 10 de 10")}

  <g opacity="${e}">
    <!-- Left Column: Relatórios de Jogos & Indústria -->
    <rect x="50" y="114" width="575" height="570" rx="12" fill="#1e1e24" stroke="#38bdf8" stroke-width="1.5"/>
    <text x="70" y="146" font-size="13.5" font-weight="800" fill="#38bdf8" letter-spacing="0.5">RELATÓRIOS DE JOGOS &amp; INDÚSTRIA (5)</text>
    ${renderRefList(industryRefs, 70, "#38bdf8")}

    <!-- Right Column: Artigos Científicos -->
    <rect x="655" y="114" width="575" height="570" rx="12" fill="#1e1e24" stroke="#8b5cf6" stroke-width="1.5"/>
    <text x="675" y="146" font-size="13.5" font-weight="800" fill="#a78bfa" letter-spacing="0.5">ARTIGOS CIENTÍFICOS &amp; ENGENHARIA (5)</text>
    ${renderRefList(academicRefs, 675, "#a78bfa")}
  </g>
</svg>`;
}

// ==========================================
// Main Dispatcher
// ==========================================
export function renderBeat(beatIdx, t = 1.0) {
  if (beatIdx < 0 || beatIdx >= BEATS.length) {
    throw new Error(`Invalid beat index: ${beatIdx}`);
  }
  const { slide, step } = BEATS[beatIdx];
  switch (slide) {
    case 0: return renderSlide0(step, t);
    case 1: return renderSlide1(step, t);
    case 2: return renderSlide2(step, t);
    case 3: return renderSlide3(step, t);
    case 4: return renderSlide4(step, t);
    case 5: return renderSlide5(step, t);
    case 6: return renderSlide6(step, t);
    case 7: return renderSlide7(step, t);
    case 8: return renderSlide8(step, t);
    case 9: return renderSlide9(step, t);
    default: throw new Error(`Unknown slide index: ${slide}`);
  }
}
