import { test } from "node:test";
import assert from "node:assert/strict";
import {
  metricField,
  dayId,
  METRIC_FIELDS,
  isBannerEvent,
  uniqueMarkersFor,
  countryKey,
} from "./analytics_agg.js";

test("metricField maps canonical events to counter fields", () => {
  assert.equal(metricField("impression"), "impressions");
  assert.equal(metricField("view"), "views");
  assert.equal(metricField("click"), "clicks");
  assert.equal(metricField("apply"), "applies");
  assert.equal(metricField("save"), "saves");
  assert.equal(metricField("share"), "shares");
  assert.equal(metricField("bogus"), null);
  assert.equal(metricField(undefined), null);
});

test("METRIC_FIELDS covers all mapped fields", () => {
  assert.deepEqual(METRIC_FIELDS, [
    "impressions",
    "views",
    "clicks",
    "applies",
    "saves",
    "shares",
  ]);
});

test("banners only accept impressions and clicks", () => {
  assert.equal(isBannerEvent("impression"), true);
  assert.equal(isBannerEvent("click"), true);
  assert.equal(isBannerEvent("apply"), false);
});

test("uniqueMarkersFor maps events to reach/viewer/clicker markers", () => {
  assert.deepEqual(uniqueMarkersFor("impression").map((m) => m.field), ["reach"]);
  assert.deepEqual(uniqueMarkersFor("view").map((m) => m.field), [
    "reach",
    "uniqueViewers",
  ]);
  assert.deepEqual(uniqueMarkersFor("click").map((m) => m.field), [
    "uniqueClickers",
  ]);
  assert.deepEqual(uniqueMarkersFor("save"), []);
});

test("countryKey is bounded and never empty", () => {
  assert.equal(countryKey(" India "), "India");
  assert.equal(countryKey(""), "Unknown");
  assert.equal(countryKey(null), "Unknown");
  assert.equal(countryKey("x".repeat(100)).length, 60);
});

test("dayId formats a UTC yyyymmdd bucket", () => {
  assert.equal(dayId(new Date(Date.UTC(2026, 7, 8))), "20260808");
  assert.equal(dayId(new Date(Date.UTC(2026, 0, 1))), "20260101");
});
