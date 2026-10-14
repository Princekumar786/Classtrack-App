import { test } from "node:test";
import assert from "node:assert/strict";
import { generateText } from "./aiGenerate.js";

const MODELS = ["flash", "flash-latest", "pro", "pro-latest"];

/**
 * Fake Gemini with a per-second rate limit shared by ALL models (like a
 * project quota). Calls over the limit fail with 429, like the real API.
 * Time is scaled: 1 "second" here = [tickMs] real ms, so the test is fast.
 */
function fakeGemini({ perSecond, tickMs, latencyMs = 2 }) {
  let windowStart = Date.now();
  let used = 0;
  const stats = { calls: 0, ok: 0, rejected: 0 };
  const genAI = {
    getGenerativeModel() {
      return {
        async generateContent() {
          stats.calls++;
          const now = Date.now();
          if (now - windowStart >= tickMs) {
            windowStart = now;
            used = 0;
          }
          if (used >= perSecond) {
            stats.rejected++;
            const e = new Error("[429 Too Many Requests] RESOURCE_EXHAUSTED");
            e.status = 429;
            throw e;
          }
          used++;
          await new Promise((r) => setTimeout(r, latencyMs));
          stats.ok++;
          return { response: { text: () => '{"subjects":[]}' } };
        },
      };
    },
  };
  return { genAI, stats };
}

test("spike: 2,000 imports at once against a 100/s quota — none crash, no retry storm", async () => {
  const tickMs = 50; // 1 simulated second
  const { genAI, stats } = fakeGemini({ perSecond: 100, tickMs });
  const N = 2000;
  const opts = {
    models: MODELS,
    jsonOut: true,
    request: [{ text: "x" }],
    minimalThinking: true,
    // Scaled versions of the production timings (165s deadline, 45s budget).
    deadline: Date.now() + 165 * tickMs,
    loadRetryBudgetMs: 45 * tickMs,
    backoffBaseMs: 0.8 * tickMs,
    backoffCapMs: 8 * tickMs,
    minCallMs: 1,
    perCallTimeoutMs: 90 * tickMs,
  };
  const results = await Promise.allSettled(
    Array.from({ length: N }, () =>
      generateText(genAI, { ...opts, deadline: Date.now() + 165 * tickMs })
    )
  );
  const ok = results.filter((r) => r.status === "fulfilled").length;
  const busy = results.filter((r) => r.status === "rejected" && r.reason.busy === true).length;
  const otherErrors = N - ok - busy;
  console.log(`spike: ok=${ok} busy=${busy} other=${otherErrors} ` +
    `gemini calls/request=${(stats.calls / N).toFixed(2)} rejected=${stats.rejected}`);

  // Every request ends cleanly: a result, or a "busy" the app can retry.
  assert.equal(otherErrors, 0, "no unexpected errors");
  // Back-off spreads the burst: most requests succeed within the budget.
  assert.ok(ok / N > 0.9, `expected >90% success, got ${ok}/${N}`);
  // No retry storm: on average far fewer than the old worst case of 16 calls
  // per request (4 models x 2 thinking passes x 2 attempts).
  assert.ok(stats.calls / N < 8, `calls per request ${(stats.calls / N).toFixed(1)}`);
});

test("a rejected request (400) still falls back to the next model, no waiting", async () => {
  let calls = 0;
  const genAI = {
    getGenerativeModel({ model }) {
      return {
        async generateContent() {
          calls++;
          if (model === "flash") {
            const e = new Error("[400 Bad Request] invalid thinkingConfig");
            e.status = 400;
            throw e;
          }
          return { response: { text: () => "ok" } };
        },
      };
    },
  };
  const text = await generateText(genAI, {
    models: MODELS,
    request: [],
    minimalThinking: true,
    sleep: () => assert.fail("must not back off for a 400"),
  });
  assert.equal(text, "ok");
  assert.equal(calls, 2);
});

test("only-load failures are reported as busy", async () => {
  const genAI = {
    getGenerativeModel() {
      return {
        async generateContent() {
          const e = new Error("[503 Service Unavailable] overloaded");
          e.status = 503;
          throw e;
        },
      };
    },
  };
  await assert.rejects(
    generateText(genAI, {
      models: MODELS,
      request: [],
      loadRetryBudgetMs: 30,
      backoffBaseMs: 5,
      backoffCapMs: 10,
      minCallMs: 1,
    }),
    (e) => e.busy === true
  );
});
