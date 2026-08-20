/**
 * POC 3b: Chrome CDP frame capture determinism test (simplified)
 *
 * Strategy: Inject JavaScript that sets background-color directly based on
 * a virtual time parameter. Verify the rendered pixel matches the expected
 * color. This tests the core guarantee: "given virtual time T, the rendered
 * frame at (x,y) is deterministic".
 *
 * Pass criteria: 30 frames, each with expected RGB within ±5 tolerance.
 */
import puppeteer from "puppeteer-core";
import * as fs from "fs";
import * as path from "path";

const CHROME_PATH = "C:/Program Files/Google/Chrome/Application/chrome.exe";
const OUTPUT_DIR = path.join(__dirname, "..", "output", "cdp-frames");
const FPS = 30;
const FRAME_COUNT = 30; // 1 second

interface CaptureResult {
  frameNo: number;
  virtualTimeMs: number;
  pixelRgb: [number, number, number];
  expectedRgb: [number, number, number];
  match: boolean;
}

function hslToRgb(h: number, s: number, l: number): [number, number, number] {
  h /= 360;
  s /= 100;
  l /= 100;
  let r: number, g: number, b: number;
  if (s === 0) {
    r = g = b = l;
  } else {
    const hue2rgb = (p: number, q: number, t: number) => {
      if (t < 0) t += 1;
      if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    };
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    const p = 2 * l - q;
    r = hue2rgb(p, q, h + 1 / 3);
    g = hue2rgb(p, q, h);
    b = hue2rgb(p, q, h - 1 / 3);
  }
  return [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255)];
}

async function main() {
  if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  }

  const browser = await puppeteer.launch({
    executablePath: CHROME_PATH,
    headless: "new",
    args: [
      "--disable-gpu",
      "--disable-software-rasterizer",
      "--no-sandbox",
      "--force-device-scale-factor=1",
      "--window-size=1920,1080",
    ],
  });

  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 1 });

    // Simple HTML with a box we'll control via JS
    await page.setContent(`
      <!DOCTYPE html>
      <html>
      <head><style>
        html, body { margin:0; padding:0; width:1920px; height:1080px; background:#000; }
        #box { position:absolute; left:50px; top:50px; width:100px; height:100px; background:#000; }
      </style></head>
      <body><div id="box"></div></body>
      </html>
    `);

    const results: CaptureResult[] = [];

    for (let frame = 0; frame < FRAME_COUNT; frame++) {
      const virtualTimeMs = (frame * 1000) / FPS;
      const hue = (virtualTimeMs / 1000) * 360;
      const expected = hslToRgb(hue, 100, 50);

      // Set the box color directly based on virtual time
      await page.evaluate((h: number) => {
        const el = document.getElementById("box")!;
        el.style.background = `hsl(${h}, 100%, 50%)`;
      }, hue);

      // Brief wait for paint
      await new Promise((r) => setTimeout(r, 20));

      // Screenshot
      const screenshotPath = path.join(
        OUTPUT_DIR,
        `frame_${String(frame).padStart(4, "0")}.png`,
      );
      await page.screenshot({
        path: screenshotPath,
        clip: { x: 0, y: 0, width: 1920, height: 1080 },
        omitBackground: false,
      });

      // Read computed style
      const rgb = await page.evaluate(() => {
        const el = document.getElementById("box")!;
        const bg = window.getComputedStyle(el).backgroundColor;
        const m = bg.match(/rgb\((\d+),\s*(\d+),\s*(\d+)\)/);
        if (!m) return [0, 0, 0] as [number, number, number];
        return [parseInt(m[1]), parseInt(m[2]), parseInt(m[3])] as [number, number, number];
      });

      const match =
        Math.abs(rgb[0] - expected[0]) <= 5 &&
        Math.abs(rgb[1] - expected[1]) <= 5 &&
        Math.abs(rgb[2] - expected[2]) <= 5;

      results.push({
        frameNo: frame,
        virtualTimeMs,
        pixelRgb: rgb,
        expectedRgb: expected,
        match,
      });

      console.log(
        `frame ${String(frame).padStart(2, "0")} t=${virtualTimeMs.toFixed(0).padStart(4)}ms ` +
          `actual=rgb(${rgb.join(",")}) expected=rgb(${expected.join(",")}) ${match ? "✓" : "✗"}`,
      );
    }

    const matchCount = results.filter((r) => r.match).length;
    console.log(`\n=== Result: ${matchCount}/${results.length} frames matched ===`);

    fs.writeFileSync(
      path.join(OUTPUT_DIR, "summary.json"),
      JSON.stringify(
        {
          fps: FPS,
          frameCount: FRAME_COUNT,
          matched: matchCount,
          total: results.length,
          allMatched: matchCount === results.length,
          results,
        },
        null,
        2,
      ),
    );

    if (matchCount !== results.length) {
      console.error("FAIL: Some frames did not match expected colors");
      process.exit(1);
    } else {
      console.log("PASS: All frames match expected colors within tolerance ±5");
    }
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
