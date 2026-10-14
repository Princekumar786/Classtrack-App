/**
 * Resilience helpers for Gemini calls under heavy load — pure and unit-tested
 * (`node --test`), no Firebase or network needed.
 *
 * Under a traffic spike (thousands of students importing at once) Gemini
 * starts returning 429 "quota / rate limit" and 503 "overloaded". Retrying
 * instantly — or trying every model back-to-back — multiplies the load and
 * makes the throttling worse (a retry storm). These helpers give:
 *   • a clear "is this worth retrying?" rule,
 *   • exponential back-off with full jitter (spreads retries out in time),
 *   • a deadline so we always answer before the function's own timeout.
 */

/** HTTP status from a @google/generative-ai error (or similar), or null. */
export function aiErrorStatus(err) {
  if (!err || typeof err !== "object") return null;
  const s = err.status ?? err.code ?? err.response?.status;
  if (typeof s === "number") return s;
  const m = /\[(\d{3})[\s\]]/.exec(String(err.message || ""));
  return m ? Number(m[1]) : null;
}

/** True for rate-limit / quota errors (429, RESOURCE_EXHAUSTED). */
export function isRateLimitError(err) {
  if (aiErrorStatus(err) === 429) return true;
  return /RESOURCE_EXHAUSTED|rate limit|quota/i.test(String(err?.message || ""));
}

/**
 * True when the SAME request may succeed if tried again later: rate limits,
 * server overload / 5xx, timeouts and dropped connections. False for problems
 * with the request itself (400 bad request, 403 key, 404 unknown model), which
 * only another model — never a wait — can fix.
 */
export function isRetryableAiError(err) {
  if (!err) return false;
  if (isRateLimitError(err)) return true;
  const status = aiErrorStatus(err);
  if (status !== null && status >= 500) return true;
  if (err.name === "AbortError") return true; // our per-call timeout fired
  const msg = String(err.message || "");
  return /timed? ?out|ETIMEDOUT|ECONNRESET|ECONNREFUSED|EAI_AGAIN|socket hang up|fetch failed|network|overloaded|UNAVAILABLE/i.test(
    msg
  );
}

/**
 * Exponential back-off with FULL jitter: a random wait between 0 and
 * min(cap, base * 2^attempt). Random spread is what stops thousands of
 * clients retrying in lock-step. [rand] is injectable for tests.
 */
export function backoffDelayMs(attempt, { baseMs = 800, capMs = 8000, rand = Math.random } = {}) {
  const ceiling = Math.min(capMs, baseMs * 2 ** Math.max(0, attempt));
  return Math.floor(rand() * ceiling);
}

/** Milliseconds left before [deadline] (epoch ms), never negative. */
export function remainingMs(deadline, now = Date.now()) {
  return Math.max(0, deadline - now);
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
