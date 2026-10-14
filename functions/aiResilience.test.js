import { test } from "node:test";
import assert from "node:assert/strict";
import {
  aiErrorStatus,
  isRateLimitError,
  isRetryableAiError,
  backoffDelayMs,
  remainingMs,
} from "./aiResilience.js";

test("status is read from the SDK error or its message", () => {
  assert.equal(aiErrorStatus({ status: 429 }), 429);
  assert.equal(
    aiErrorStatus(new Error("[GoogleGenerativeAI Error]: Error fetching ...: [503 Service Unavailable] overloaded")),
    503
  );
  assert.equal(aiErrorStatus(new Error("boom")), null);
});

test("rate limits and overload are retryable; bad requests are not", () => {
  assert.equal(isRateLimitError({ status: 429, message: "" }), true);
  assert.equal(isRateLimitError(new Error("RESOURCE_EXHAUSTED: quota")), true);
  assert.equal(isRetryableAiError({ status: 429 }), true);
  assert.equal(isRetryableAiError({ status: 503 }), true);
  assert.equal(isRetryableAiError({ status: 500 }), true);
  const abort = new Error("aborted");
  abort.name = "AbortError";
  assert.equal(isRetryableAiError(abort), true);
  assert.equal(isRetryableAiError(new Error("fetch failed")), true);
  assert.equal(isRetryableAiError({ status: 400, message: "invalid argument" }), false);
  assert.equal(isRetryableAiError({ status: 404, message: "model not found" }), false);
  assert.equal(isRetryableAiError(null), false);
});

test("back-off grows exponentially, is capped, and is jittered", () => {
  const max = () => 0.999999;
  assert.equal(backoffDelayMs(0, { baseMs: 800, capMs: 8000, rand: max }), 799);
  assert.equal(backoffDelayMs(2, { baseMs: 800, capMs: 8000, rand: max }), 3199);
  assert.equal(backoffDelayMs(10, { baseMs: 800, capMs: 8000, rand: max }), 7999);
  assert.equal(backoffDelayMs(3, { rand: () => 0 }), 0);
});

test("remaining time never goes negative", () => {
  assert.equal(remainingMs(1000, 400), 600);
  assert.equal(remainingMs(1000, 5000), 0);
});
