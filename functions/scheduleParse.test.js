import { test } from "node:test";
import assert from "node:assert/strict";
import { normalizeDay, normalizeTime, resolveTimes, parseModelJson, sniffMime } from "./scheduleParse.js";

test("normalizeDay: abbreviations and case no longer fall back to Monday", () => {
  assert.equal(normalizeDay("Mon"), "Monday");
  assert.equal(normalizeDay("TUE"), "Tuesday");
  assert.equal(normalizeDay("Thurs."), "Thursday");
  assert.equal(normalizeDay("friday"), "Friday");
  assert.equal(normalizeDay("Sun"), "Sunday");
  assert.equal(normalizeDay("Funday"), null);
  assert.equal(normalizeDay(null), null);
});

test("normalizeTime: every common shape", () => {
  const cases = {
    "9:00": "09:00", "09:00": "09:00", "9:00 AM": "09:00", "9 am": "09:00",
    "9.30pm": "21:30", "1:20 PM": "13:20", "12 PM": "12:00", "12:15 am": "00:15",
    "09:00:00": "09:00", "0930": "09:30", "1340": "13:40", "13:40": "13:40",
    noon: "12:00", "2 p.m.": "14:00",
  };
  for (const [i, o] of Object.entries(cases)) assert.equal(normalizeTime(i), o, i);
  for (const bad of ["", "abc", "25:00", "9", "13 pm", null]) assert.equal(normalizeTime(bad), null, String(bad));
});

test("resolveTimes: missing end, PM slips and AM-read afternoons", () => {
  assert.deepEqual(resolveTimes("14:00", null), { start: "14:00", end: "15:00" });
  assert.deepEqual(resolveTimes("2:00 PM", "garbage"), { start: "14:00", end: "15:00" });
  assert.deepEqual(resolveTimes("11:30", "01:00"), { start: "11:30", end: "13:00" });
  assert.deepEqual(resolveTimes("01:40", "02:30"), { start: "13:40", end: "14:30" });
  assert.deepEqual(resolveTimes("09:30", "10:20"), { start: "09:30", end: "10:20" });
  assert.deepEqual(resolveTimes("07:30", "08:20"), { start: "07:30", end: "08:20" });
  assert.deepEqual(resolveTimes("18:00", "19:30"), { start: "18:00", end: "19:30" });
  assert.equal(resolveTimes("nope", "10:00"), null);
});

test("parseModelJson: fences and truncated replies", () => {
  assert.deepEqual(parseModelJson('```json\n{"subjects":[],"confidence":"high"}\n```'), { subjects: [], confidence: "high" });
  const truncated =
    '{"subjects":[{"name":"Maths","sessions":[{"day":"Monday","start":"09:00","end":"10:00"}]},' +
    '{"name":"Physics {lab}","sessions":[{"day":"Tue","start":"11:00","end":"12:00"}]},' +
    '{"name":"Chem","sessions":[{"day":"Wed","sta';
  const r = parseModelJson(truncated);
  assert.equal(r.subjects.length, 2);
  assert.equal(r.subjects[1].name, "Physics {lab}");
  assert.equal(parseModelJson("total garbage"), null);
});

test("sniffMime: real formats regardless of the claimed type", () => {
  const b64 = (bytes) => Buffer.from(bytes).toString("base64");
  assert.equal(sniffMime(b64([0xff, 0xd8, 0xff, 0xe0]), "x"), "image/jpeg");
  assert.equal(sniffMime(b64([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]), "x"), "image/png");
  assert.equal(sniffMime(b64([...Buffer.from("RIFF"), 0, 0, 0, 0, ...Buffer.from("WEBP")]), "x"), "image/webp");
  assert.equal(sniffMime(b64([0, 0, 0, 0x18, ...Buffer.from("ftypheic")]), "x"), "image/heic");
  assert.equal(sniffMime(b64([...Buffer.from("%PDF-1.7")]), "x"), "application/pdf");
  assert.equal(sniffMime(b64([1, 2, 3, 4]), "image/jpeg"), "image/jpeg");
});
