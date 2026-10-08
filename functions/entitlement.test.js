import { test } from "node:test";
import assert from "node:assert/strict";
import { deriveEntitlement, toMillisMaybe } from "./entitlement.js";

const now = Date.parse("2026-09-24T18:00:00Z");
const inAMonth = "2026-10-24T18:00:00Z";
const lastWeek = "2026-09-17T18:00:00Z";

test("active time-boxed subscription → proUntil, not permanent", () => {
  const sub = { entitlements: { pro: { expires_date: inAMonth } } };
  const r = deriveEntitlement(sub, "pro", now);
  assert.equal(r.active, true);
  assert.equal(r.pro, false);
  assert.equal(r.proUntil, Date.parse(inAMonth));
});

test("non-expiring entitlement (expires_date null) → permanent lifetime", () => {
  const sub = { entitlements: { pro: { expires_date: null } } };
  const r = deriveEntitlement(sub, "pro", now);
  assert.deepEqual(r, { active: true, pro: true, proUntil: null });
});

test("expired entitlement → nothing active", () => {
  const sub = { entitlements: { pro: { expires_date: lastWeek } } };
  const r = deriveEntitlement(sub, "pro", now);
  assert.deepEqual(r, { active: false, pro: false, proUntil: null });
});

test("no subscriber / no entitlements → nothing active", () => {
  assert.deepEqual(deriveEntitlement({}, "pro", now), {
    active: false,
    pro: false,
    proUntil: null,
  });
  assert.deepEqual(deriveEntitlement(undefined, "pro", now), {
    active: false,
    pro: false,
    proUntil: null,
  });
});

test("falls back to ANY active entitlement when configured id is absent", () => {
  const sub = {
    entitlements: { "ClassTrack Pro": { expires_date: inAMonth } },
  };
  const r = deriveEntitlement(sub, "pro", now);
  assert.equal(r.active, true);
  assert.equal(r.proUntil, Date.parse(inAMonth));
});

test("ignores an expired non-configured entitlement", () => {
  const sub = { entitlements: { other: { expires_date: lastWeek } } };
  assert.equal(deriveEntitlement(sub, "pro", now).active, false);
});

test("prefers configured id, but a lifetime elsewhere still wins over nothing", () => {
  const sub = {
    entitlements: {
      pro: { expires_date: lastWeek }, // expired
      legacy: { expires_date: null }, // lifetime
    },
  };
  const r = deriveEntitlement(sub, "pro", now);
  assert.equal(r.pro, true);
  assert.equal(r.active, true);
});

test("toMillisMaybe handles numbers, Timestamps, and junk", () => {
  assert.equal(toMillisMaybe(123), 123);
  assert.equal(toMillisMaybe({ toMillis: () => 456 }), 456);
  assert.equal(toMillisMaybe(null), null);
  assert.equal(toMillisMaybe(undefined), null);
  assert.equal(toMillisMaybe("nope"), null);
});
