/**
 * Gemini text generation with model fallback, back-off and deadlines.
 * Pure apart from the injected `genAI` client, so it can be load-tested
 * with a fake (see aiGenerate.test.js).
 */
import {
  isRetryableAiError,
  backoffDelayMs,
  remainingMs,
  sleep as defaultSleep,
} from "./aiResilience.js";

/// Per-model thinking config for a "keep thinking to a minimum" request.
/// Gemini 2.5 models only understand `thinkingBudget` (2.5 Pro can't go below
/// 128). Gemini 3+ models (what the "-latest" aliases resolve to) use
/// `thinkingLevel`; upcoming models reject `thinkingBudget` with a 400, so it
/// must never be sent to them. "minimal" is Flash-only; Pro supports "low".
export function minimalThinkingConfig(model) {
  if (/^gemini-2\.5-/.test(model)) {
    return { thinkingBudget: model.includes("pro") ? 128 : 0 };
  }
  return { thinkingLevel: model.includes("pro") ? "low" : "minimal" };
}

/// Generate text, trying each model until one works. [request] is whatever
/// generateContent accepts (a parts array or a { contents } object).
/// [models] overrides the default model order; [maxOutputTokens] caps the
/// reply length (both used to keep the chat snappy). [minimalThinking]
/// dials thinking down so it can't eat the output budget.
///
/// Built to survive traffic spikes (thousands of students at once):
///  • Each call has its own timeout ([perCallTimeoutMs]) and the whole thing
///    has a [deadline], so we always answer before the Cloud Function's own
///    timeout instead of the app seeing a vague "deadline exceeded".
///  • On a rate limit (429) or overload (5xx/timeout) we wait with jittered
///    exponential back-off before the next attempt, instead of hammering every
///    model back-to-back (which turned one throttled request into ~16 calls
///    and made the throttling worse for everyone).
///  • The "retry without thinkingConfig" pass only runs when a model actually
///    rejected the request (400), never for load errors.
/// When every attempt failed because of load, the thrown error has
/// `busy = true` so callers can tell the user to retry in a minute.
export async function generateText(
  genAI,
  {
    systemInstruction,
    jsonOut,
    request,
    models,
    maxOutputTokens,
    minimalThinking = false,
    deadline = Date.now() + 100_000,
    perCallTimeoutMs = 90_000,
    // When the ONLY failures are load errors (429/5xx), give up after this
    // long and tell the caller it's busy: the app then retries later with
    // jitter, which is gentler on Gemini than holding the request open.
    loadRetryBudgetMs = 45_000,
    // Injectable for tests.
    sleep = defaultSleep,
    backoffBaseMs = 800,
    backoffCapMs = 8_000,
    minCallMs = 8_000,
  }
) {
  const startedAt = Date.now();
  // Base generation config shared by every attempt. No temperature/topP/topK:
  // they're deprecated and will error on upcoming models.
  const baseConfig = {};
  if (jsonOut) baseConfig.responseMimeType = "application/json";
  if (maxOutputTokens) baseConfig.maxOutputTokens = maxOutputTokens;

  // Don't start a call that can't finish in a useful amount of time.
  const MIN_CALL_MS = minCallMs;
  let loadFailures = 0;
  let otherFailures = 0;
  let retryRound = 0;
  const loadBudgetSpent = () =>
    loadFailures > 0 && otherFailures === 0 &&
    Date.now() - startedAt > loadRetryBudgetMs;

  async function run(withThinking) {
    let lastErr;
    for (const m of models) {
      const left = remainingMs(deadline);
      if (left < MIN_CALL_MS || loadBudgetSpent()) break;
      const generationConfig = { ...baseConfig };
      if (withThinking) {
        generationConfig.thinkingConfig = minimalThinkingConfig(m);
      }
      const hasConfig = Object.keys(generationConfig).length > 0;
      try {
        const model = genAI.getGenerativeModel(
          {
            model: m,
            systemInstruction,
            generationConfig: hasConfig ? generationConfig : undefined,
          },
          { timeout: Math.min(perCallTimeoutMs, left - 1_000) }
        );
        const result = await model.generateContent(request);
        return { text: result.response.text() };
      } catch (e) {
        lastErr = e;
        if (isRetryableAiError(e)) {
          loadFailures++;
          // Spread retries out; never sleep past the deadline.
          const wait = Math.min(
            backoffDelayMs(retryRound++, { baseMs: backoffBaseMs, capMs: backoffCapMs }),
            Math.max(0, remainingMs(deadline) - MIN_CALL_MS)
          );
          if (wait > 0) await sleep(wait);
        } else {
          otherFailures++;
        }
      }
    }
    return { err: lastErr };
  }

  // First pass: with thinkingConfig when minimal thinking was requested.
  let res = await run(minimalThinking);
  if (res.text !== undefined) return res.text;
  // Fallback: retry the list without thinkingConfig, but ONLY if a model
  // rejected the request itself (e.g. an SDK/model that doesn't accept the
  // field) — never as a blind second wave on a throttled backend.
  if (minimalThinking && otherFailures > 0 && remainingMs(deadline) >= MIN_CALL_MS) {
    res = await run(false);
    if (res.text !== undefined) return res.text;
  }
  // Load errors only: one more spaced-out pass if there's still time.
  if (otherFailures === 0 && loadFailures > 0 && !loadBudgetSpent() &&
      remainingMs(deadline) >= MIN_CALL_MS) {
    res = await run(minimalThinking);
    if (res.text !== undefined) return res.text;
  }
  const err = res.err || new Error("All models failed");
  err.busy = otherFailures === 0 && loadFailures > 0;
  throw err;
}

