// bench/liveview_diffs.mjs
//
// Measures LiveView WebSocket diff sizes by joining the game,
// hooking the live WebSocket, performing moves, and reporting
// message sizes.
//
// Expects the Phoenix server to already be running on the given port.
// Usage: node bench/liveview_diffs.mjs [--port 4000] [--moves 20] [--username benchplayer]

import { execSync } from "child_process";
import { createRequire } from "module";

// resolve playwright-core: try NODE_PATH first, then scan nix store
function findPlaywrightCorePath() {
  const require = createRequire(import.meta.url);
  try {
    return require.resolve("playwright-core");
  } catch (_) {
    const nixPath = execSync(
      'ls -d /nix/store/*-playwright-core-*/index.mjs 2>/dev/null | tail -1',
      { encoding: "utf-8" }
    ).trim();
    if (nixPath) return nixPath;
    throw new Error("playwright-core not found -- install via nix or set NODE_PATH");
  }
}

const playwrightCorePath = findPlaywrightCorePath();
const { chromium } = await import(playwrightCorePath);

// find a chromium binary that matches the loaded playwright-core version.
// reads browsers.json from playwright-core to get the expected revision,
// then finds a nix store path tagged with that revision.
function findChromium() {
  // try nix: read expected revision from playwright-core's browsers.json
  try {
    const dir = playwrightCorePath.replace(/\/index\.(mjs|js)$/, "");
    const browsers = JSON.parse(
      execSync(`cat "${dir}/browsers.json"`, { encoding: "utf-8" })
    );
    const entry = browsers.browsers.find(
      (b) => b.name === "chromium-headless-shell"
    );
    if (entry) {
      const shell = execSync(
        `{ ls -d /nix/store/*-playwright-chromium-headless-shell/chromium_headless_shell-${entry.revision}/chrome-headless-shell-linux64/headless_shell 2>/dev/null || ` +
        `ls -d /nix/store/*-playwright-chromium-headless-shell/chrome-linux/headless_shell 2>/dev/null; } | tail -1`,
        { encoding: "utf-8" }
      ).trim();
      if (shell) return shell;
    }
  } catch (_) {
    // fall through
  }
  // fall back to system chromium
  try {
    return execSync("which chromium", { encoding: "utf-8" }).trim();
  } catch (_) {
    return null;
  }
}

function parseArgs(argv) {
  const args = { port: 4000, moves: 20, username: "benchplayer" };
  for (let i = 2; i < argv.length; i += 2) {
    if (argv[i] === "--port") args.port = parseInt(argv[i + 1], 10);
    if (argv[i] === "--moves") args.moves = parseInt(argv[i + 1], 10);
    if (argv[i] === "--username") args.username = argv[i + 1];
  }
  return args;
}

async function run() {
  const args = parseArgs(process.argv);
  const base = `http://localhost:${args.port}`;

  const executablePath = process.env.CHROMIUM_PATH || findChromium() || undefined;
  const browser = await chromium.launch({ executablePath });
  const page = await browser.newPage();

  try {
    // join the game
    await page.goto(`${base}/game`);
    const input = page.getByRole("textbox", { name: "Username" });
    await input.click();
    await input.pressSequentially(args.username, { delay: 20 });
    await page.getByRole("button", { name: "Join World" }).click();
    await page.waitForURL(/\/world\?user_id=/, { timeout: 10000 });

    // hook into the existing LiveView WebSocket.
    // waitForFunction polls until the socket is connected, avoiding a race
    // where liveSocket.socket.conn is still null right after navigation.
    await page.waitForFunction(() => {
      const ls = window.liveSocket;
      if (!ls || !ls.socket || !ls.socket.conn) return false;

      window.__wsMessages = [];
      ls.socket.conn.addEventListener("message", (event) => {
        // parse type eagerly so we don't store full payloads in memory.
        // phoenix channel wire format: [join_ref, ref, topic, event, payload]
        let type = "unknown";
        try {
          const parsed = JSON.parse(event.data);
          if (Array.isArray(parsed) && parsed.length >= 4) type = parsed[3];
        } catch (_) {
          // binary or malformed
        }
        window.__wsMessages.push({ ts: Date.now(), size: event.data.length, type });
      });
      return true;
    }, { timeout: 5000 });

    // read map dimensions
    const mapInfo = await page.evaluate(() => {
      const mapDiv = document.querySelector(".font-mono.text-sm");
      const rows = mapDiv
        ? mapDiv.querySelectorAll(":scope > div").length
        : 0;
      const firstRow = mapDiv
        ? mapDiv.querySelector(":scope > div")
        : null;
      const cols = firstRow
        ? firstRow.querySelectorAll("span").length
        : 0;
      const mobs = document.querySelectorAll('[data-entity="mob"]').length;
      return { rows, cols, totalSpans: rows * cols, mobs };
    });

    // clear and measure idle traffic for 3 seconds
    await page.evaluate(() => {
      window.__wsMessages = [];
    });
    await page.waitForTimeout(3000);
    const idleFrames = await page.evaluate(() =>
      window.__wsMessages.map((f) => ({ size: f.size }))
    );

    // clear and perform moves
    await page.evaluate(() => {
      window.__wsMessages = [];
    });
    const pattern = ["d", "d", "s", "s", "a", "a", "w", "w", "d", "s"];
    for (let i = 0; i < args.moves; i++) {
      await page.keyboard.press(pattern[i % pattern.length]);
      await page.waitForTimeout(200);
    }
    // wait for trailing diffs
    await page.waitForTimeout(500);

    const moveFrames = await page.evaluate(() =>
      window.__wsMessages.map((f) => ({ size: f.size, type: f.type }))
    );

    // compute results
    const diffs = moveFrames.filter((f) => f.type === "diff");
    const replies = moveFrames.filter((f) => f.type === "phx_reply");
    const diffSizes = diffs.map((d) => d.size);
    const replySizes = replies.map((r) => r.size);

    const sum = (arr) => arr.reduce((a, b) => a + b, 0);
    const avg = (arr) => (arr.length ? Math.round(sum(arr) / arr.length) : 0);

    const results = {
      map: mapInfo,
      moves: args.moves,
      idle: {
        duration_s: 3,
        messages: idleFrames.length,
        bytes_per_s: Math.round(sum(idleFrames.map((f) => f.size)) / 3),
      },
      replies: {
        count: replies.length,
        avg_bytes: avg(replySizes),
      },
      diffs: {
        count: diffs.length,
        min_bytes: diffSizes.length ? Math.min(...diffSizes) : 0,
        max_bytes: diffSizes.length ? Math.max(...diffSizes) : 0,
        avg_bytes: avg(diffSizes),
        total_bytes: sum(diffSizes),
        per_move: (diffs.length / args.moves).toFixed(1),
      },
    };

    console.log(JSON.stringify(results));
  } finally {
    await browser.close();
  }
}

run().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
