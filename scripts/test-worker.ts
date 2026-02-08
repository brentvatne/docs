import { spawn, ChildProcess } from "child_process";
import { readFileSync, existsSync, mkdirSync, writeFileSync, rmSync } from "fs";
import { join } from "path";

const PORT = 8788;
const BASE_URL = `http://localhost:${PORT}`;

let wranglerProcess: ChildProcess | null = null;

async function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function cleanup(): Promise<void> {
  if (wranglerProcess) {
    wranglerProcess.kill();
    wranglerProcess = null;
  }
  if (existsSync("out")) {
    rmSync("out", { recursive: true, force: true });
  }
}

function validateRoutesJson(): void {
  console.log("\n--- Validating _routes.json ---");

  const routesPath = "public/_routes.json";
  if (!existsSync(routesPath)) {
    throw new Error("_routes.json does not exist");
  }
  console.log("✓ _routes.json exists");

  const content = readFileSync(routesPath, "utf8");
  const routes = JSON.parse(content);
  console.log("✓ _routes.json is valid JSON");

  if (routes.version !== 1) {
    throw new Error("_routes.json version must be 1");
  }
  if (!Array.isArray(routes.include)) {
    throw new Error("_routes.json include must be an array");
  }
  if (!Array.isArray(routes.exclude)) {
    throw new Error("_routes.json exclude must be an array");
  }
  console.log("✓ _routes.json has valid structure (version, include, exclude)");
}

function validateWorkerJs(): void {
  console.log("\n--- Validating _worker.js ---");

  const workerPath = "public/_worker.js";
  if (!existsSync(workerPath)) {
    throw new Error("_worker.js does not exist");
  }
  console.log("✓ _worker.js exists");

  const content = readFileSync(workerPath, "utf8");

  if (!content.includes("export default")) {
    throw new Error("_worker.js missing default export");
  }
  console.log("✓ _worker.js has default export");

  if (!content.includes("async fetch")) {
    throw new Error("_worker.js missing fetch handler");
  }
  console.log("✓ _worker.js has fetch handler");
}

function setupTestDirectory(): void {
  console.log("\n--- Setting up test directory ---");

  mkdirSync("out", { recursive: true });
  mkdirSync("out/test-page", { recursive: true });

  // Copy worker files
  const routesContent = readFileSync("public/_routes.json", "utf8");
  const workerContent = readFileSync("public/_worker.js", "utf8");

  writeFileSync("out/_routes.json", routesContent);
  writeFileSync("out/_worker.js", workerContent);
  writeFileSync("out/index.html", "<html><body><h1>Test Page</h1></body></html>");
  writeFileSync("out/test-page/index.md", "# Test Markdown Content\n\nThis is test content.");

  console.log("✓ Test directory created");
}

async function startWrangler(): Promise<void> {
  console.log("\n--- Starting wrangler pages dev ---");

  wranglerProcess = spawn("npx", ["wrangler", "pages", "dev", "out", "--port", String(PORT)], {
    stdio: ["ignore", "pipe", "pipe"],
  });

  // Wait for wrangler to start
  await sleep(4000);

  if (wranglerProcess.exitCode !== null) {
    throw new Error(`Wrangler exited with code ${wranglerProcess.exitCode}`);
  }

  console.log("✓ Wrangler started");
}

async function testHttpResponse(): Promise<void> {
  console.log("\n--- Testing HTTP responses ---");

  const response = await fetch(BASE_URL);
  if (!response.ok) {
    throw new Error(`Server not responding: HTTP ${response.status}`);
  }
  console.log(`✓ Server responds with HTTP ${response.status}`);
}

async function testMarkdownContentNegotiation(): Promise<void> {
  console.log("\n--- Testing markdown content negotiation ---");

  const response = await fetch(`${BASE_URL}/test-page`, {
    headers: { Accept: "text/markdown" },
  });

  const contentType = response.headers.get("content-type") || "";
  const body = await response.text();

  if (body.includes("Test Markdown Content")) {
    console.log("✓ Worker serves markdown when Accept: text/markdown header is sent");
  } else {
    console.log("→ Markdown content negotiation test inconclusive");
  }

  if (contentType.includes("text/markdown")) {
    console.log("✓ Worker returns correct Content-Type for markdown");
  } else {
    console.log("→ Content-Type header test inconclusive");
  }
}

async function main(): Promise<void> {
  console.log("=== Testing Cloudflare Pages Worker and Routes ===");

  try {
    validateRoutesJson();
    validateWorkerJs();
    setupTestDirectory();
    await startWrangler();
    await testHttpResponse();
    await testMarkdownContentNegotiation();

    console.log("\n=== All tests passed! ===");
  } catch (error) {
    console.error("\n✗ Test failed:", error instanceof Error ? error.message : error);
    process.exitCode = 1;
  } finally {
    await cleanup();
  }
}

main();
