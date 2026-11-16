#!/usr/bin/env node
// ============================================================================
// Exoforge Motion Pitch Video Generator
//
// Renders the 6-slide / 22-beat Exoforge motion-graphics pitch deck into
// docs/pitch/exoforge-pitch.mp4 (1280x720, 15 FPS, H.264 Baseline MP4)
// 100% inside the macOS sandbox using rsvg-convert + self-contained C encoder.
//
// Usage:
//   node scripts/pitch-video.mjs [outputPath]
// ============================================================================

import { execFileSync } from "node:child_process";
import {
  mkdirSync,
  writeFileSync,
  rmSync,
  existsSync,
  statSync,
} from "node:fs";
import { resolve, dirname, join } from "node:path";
import { createHash } from "node:crypto";
import { BEATS, renderBeat } from "./pitch-storyboard.mjs";
import { C_MP4ENC_SOURCE } from "./pitch-encoder-c.mjs";

const WIDTH = 1280;
const HEIGHT = 720;
const FPS = 15;
const HOLD_FRAMES_DEFAULT = 25; // ~1.67 seconds per settled beat
const HOLD_FRAMES_FINAL = 40;   // ~2.67 seconds for the final hero banner

const RSVG_CONVERT = "/opt/homebrew/bin/rsvg-convert";
const DEFAULT_OUTPUT = resolve("docs/pitch/exoforge-pitch.mp4");
const OUTPUT_PATH = process.argv[2] ? resolve(process.argv[2]) : DEFAULT_OUTPUT;

const TEMP_DIR = join("/tmp", `exo-pitch-render-${process.pid}`);

async function main() {
  const startTime = Date.now();
  console.log("============================================================");
  console.log(" Exoforge Motion Pitch Video Generator");
  console.log(` Output:    ${OUTPUT_PATH}`);
  console.log(` Geometry:  ${WIDTH}x${HEIGHT} @ ${FPS} FPS`);
  console.log(` Story:     7 Slides / ${BEATS.length} Beats`);
  console.log(` Workspace: ${TEMP_DIR}`);
  console.log("============================================================\n");

  if (!existsSync(RSVG_CONVERT)) {
    throw new Error(`rsvg-convert not found at ${RSVG_CONVERT}`);
  }

  mkdirSync(TEMP_DIR, { recursive: true });
  mkdirSync(dirname(OUTPUT_PATH), { recursive: true });

  try {
    // 1. Write and compile C H.264 Baseline MP4 encoder
    console.log("[1/4] Compiling self-contained C H.264 Baseline + MP4 muxer...");
    const cSourcePath = join(TEMP_DIR, "mp4enc.c");
    const binaryPath = join(TEMP_DIR, "mp4enc");
    writeFileSync(cSourcePath, C_MP4ENC_SOURCE);

    execFileSync("clang", [
      "-O3",
      "-Wall",
      "-framework", "CoreGraphics",
      "-framework", "ImageIO",
      "-framework", "Foundation",
      "-framework", "CoreFoundation",
      cSourcePath,
      "-o", binaryPath,
    ], { stdio: "pipe" });
    console.log("  ✓ Compiled mp4enc binary with clang -O3\n");

    // 2. Render all beats + eased transitions to SVG and PNG
    console.log(`[2/4] Rendering ${BEATS.length}-beat storyboard frames with rsvg-convert...`);
    const manifestEntries = [];
    const svgHashMap = new Map(); // hash -> pngPath (deduplicate identical frames)
    let uniquePngCount = 0;
    let totalFrameCount = 0;

    function emitFrame(svgString, repeatCount) {
      const hash = createHash("sha1").update(svgString).digest("hex");
      let pngPath = svgHashMap.get(hash);

      if (!pngPath) {
        uniquePngCount++;
        const frameId = String(uniquePngCount).padStart(4, "0");
        const svgPath = join(TEMP_DIR, `frame_${frameId}.svg`);
        pngPath = join(TEMP_DIR, `frame_${frameId}.png`);

        writeFileSync(svgPath, svgString);
        execFileSync(RSVG_CONVERT, [
          "-w", String(WIDTH),
          "-h", String(HEIGHT),
          svgPath,
          "-o", pngPath,
        ], { stdio: "pipe" });

        svgHashMap.set(hash, pngPath);
      }

      manifestEntries.push(`${pngPath} ${repeatCount}`);
      totalFrameCount += repeatCount;
    }

    // Beat 0: Initial settled hold frame
    const beat0Svg = renderBeat(0, 1.0);
    emitFrame(beat0Svg, HOLD_FRAMES_DEFAULT);
    process.stdout.write(`  • Beat  1/${BEATS.length}: ${BEATS[0].name} (hold ${HOLD_FRAMES_DEFAULT}f)\n`);

    // Beats 1 through N-1: Eased transition frames + settled hold frame
    const TRANSITION_STEPS = [0.25, 0.55, 0.85];

    for (let b = 1; b < BEATS.length; b++) {
      const beatMeta = BEATS[b];
      const holdFrames = (b === BEATS.length - 1) ? HOLD_FRAMES_FINAL : HOLD_FRAMES_DEFAULT;

      // 3 fast motion transition frames (1 repeat frame each -> ~0.20s snappy deceleration)
      for (const t of TRANSITION_STEPS) {
        const transSvg = renderBeat(b, t);
        emitFrame(transSvg, 1);
      }

      // Settled hold frame (repeated holdFrames times)
      const settledSvg = renderBeat(b, 1.0);
      emitFrame(settledSvg, holdFrames);

      const beatNum = String(b + 1).padStart(2, " ");
      process.stdout.write(`  • Beat ${beatNum}/${BEATS.length}: ${beatMeta.name} (hold ${holdFrames}f)\n`);
    }

    console.log(`\n  ✓ Generated ${uniquePngCount} unique keyframe PNGs (total video frames: ${totalFrameCount})\n`);

    // 3. Write frames manifest
    console.log("[3/4] Writing frame manifest and encoding H.264 bitstream...");
    const manifestPath = join(TEMP_DIR, "frames_manifest.txt");
    writeFileSync(manifestPath, manifestEntries.join("\n") + "\n");

    // 4. Run mp4enc to produce output MP4
    console.log("[4/4] Encoding AVC1 Baseline MP4...");
    execFileSync(binaryPath, [
      manifestPath,
      OUTPUT_PATH,
      String(WIDTH),
      String(HEIGHT),
      String(FPS),
    ], { stdio: "inherit" });

    if (!existsSync(OUTPUT_PATH)) {
      throw new Error(`Expected output MP4 at ${OUTPUT_PATH} does not exist`);
    }

    const stat = statSync(OUTPUT_PATH);
    const sizeMb = (stat.size / (1024 * 1024)).toFixed(2);
    const durationSec = (totalFrameCount / FPS).toFixed(1);
    const elapsedSec = ((Date.now() - startTime) / 1000).toFixed(1);

    console.log("\n============================================================");
    console.log(" 🎉 Exoforge Pitch Video Successfully Generated!");
    console.log(` File:     ${OUTPUT_PATH}`);
    console.log(` Size:     ${sizeMb} MB (${stat.size.toLocaleString()} bytes)`);
    console.log(` Duration: ${durationSec}s (${totalFrameCount} frames @ ${FPS} FPS)`);
    console.log(` Render:   ${elapsedSec}s elapsed`);
    console.log("============================================================\n");
  } finally {
    try {
      rmSync(TEMP_DIR, { recursive: true, force: true });
    } catch {
      // ignore cleanup errors
    }
  }
}

main().catch((err) => {
  console.error("\n❌ Fatal error in pitch-video.mjs:", err);
  process.exit(1);
});
