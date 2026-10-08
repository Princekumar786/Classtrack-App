/**
 * Pure helpers for the parseSchedule function (unit-tested without Firebase).
 * They make the AI's timetable output robust: models write times and days in
 * many shapes ("9:00 AM", "09:00:00", "Mon", "THURS"), sometimes omit end
 * times, and on very large timetables can truncate their JSON.
 */

const DAY_NAMES = [
  "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
];

const DAY_ALIASES = {
  mon: 0, monday: 0, mo: 0,
  tue: 1, tues: 1, tuesday: 1, tu: 1,
  wed: 2, weds: 2, wednesday: 2, we: 2,
  thu: 3, thur: 3, thurs: 3, thursday: 3, th: 3,
  fri: 4, friday: 4, fr: 4,
  sat: 5, saturday: 5, sa: 5,
  sun: 6, sunday: 6, su: 6,
};

/// "MONDAY", "mon", "Thurs." → "Monday"/"Thursday"; null if unrecognisable
/// (callers drop the session rather than misfiling it on Monday).
export function normalizeDay(v) {
  if (typeof v !== "string") return null;
  const k = v.trim().toLowerCase().replace(/[^a-z]/g, "");
  const i = DAY_ALIASES[k];
  return i === undefined ? null : DAY_NAMES[i];
}

/// Accepts "9:00", "09:00", "9:00 AM", "9 am", "9.30pm", "09:00:00", "0930",
/// "13:40" → "HH:MM" (24h). Returns null for anything else.
export function normalizeTime(v) {
  if (typeof v !== "string") return null;
  let t = v.trim().toLowerCase().replace(/\s+/g, " ");
  if (!t) return null;
  if (t === "noon") return "12:00";
  if (t === "midnight") return "00:00";
  const ampm = /(a\.?m\.?|p\.?m\.?)$/.exec(t);
  const suffix = ampm ? (ampm[1].startsWith("p") ? "pm" : "am") : null;
  if (ampm) t = t.slice(0, ampm.index).trim();
  let h, m;
  let mt = /^(\d{1,2})[:.](\d{2})(?::\d{2})?$/.exec(t);
  if (mt) {
    h = Number(mt[1]); m = Number(mt[2]);
  } else if ((mt = /^(\d{3,4})$/.exec(t))) {
    const n = mt[1].padStart(4, "0");
    h = Number(n.slice(0, 2)); m = Number(n.slice(2));
  } else if ((mt = /^(\d{1,2})$/.exec(t)) && suffix) {
    h = Number(mt[1]); m = 0;
  } else {
    return null;
  }
  if (suffix) {
    if (h < 1 || h > 12) return null;
    if (suffix === "am") h = h === 12 ? 0 : h;
    else h = h === 12 ? 12 : h + 12;
  }
  if (h > 23 || m > 59) return null;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

function toMin(hhmm) {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + m;
}
function fromMin(n) {
  const c = Math.max(0, Math.min(n, 23 * 60 + 59));
  return `${String(Math.floor(c / 60)).padStart(2, "0")}:${String(c % 60).padStart(2, "0")}`;
}

/// Final (start, end) for a class. Mirrors the app's fix for afternoon times
/// read without PM (a printed "1:40–2:30" → 13:40–14:30): a start between
/// 01:00 and 06:59 is moved to the afternoon — no real class starts then.
/// Missing/invalid end → start + 60 min; an end at/before the start that
/// becomes valid +12h is bumped (11:30–01:00 → 11:30–13:00); otherwise +60.
export function resolveTimes(startRaw, endRaw) {
  const start = normalizeTime(startRaw);
  if (!start) return null;
  let s = toMin(start);
  const endN = normalizeTime(endRaw);
  let e = endN ? toMin(endN) : null;
  if (s >= 60 && s < 7 * 60) {
    s += 12 * 60;
    if (e !== null && e < 12 * 60) e += 12 * 60;
  }
  if (e === null) e = s + 60;
  if (e <= s) {
    e = e + 12 * 60 > s && e + 12 * 60 < 24 * 60 ? e + 12 * 60 : s + 60;
  }
  return { start: fromMin(s), end: fromMin(e) };
}

/// Parses model JSON, tolerating markdown fences and — for very large
/// timetables — a reply truncated mid-way: it keeps every COMPLETE subject
/// object before the cut. Returns null when nothing usable is recoverable.
export function parseModelJson(raw) {
  if (typeof raw !== "string") return null;
  const text = raw.replace(/```(?:json)?/gi, "").trim();
  try {
    return JSON.parse(text);
  } catch (_) { /* try salvage below */ }
  const startIdx = text.indexOf("[", text.indexOf('"subjects"'));
  if (startIdx < 0) return null;
  // Walk the subjects array, recording the end of each complete top-level
  // object (string-aware so braces inside names don't confuse it).
  let depth = 0, inStr = false, esc = false, lastComplete = -1;
  for (let i = startIdx + 1; i < text.length; i++) {
    const ch = text[i];
    if (inStr) {
      if (esc) esc = false;
      else if (ch === "\\") esc = true;
      else if (ch === '"') inStr = false;
      continue;
    }
    if (ch === '"') inStr = true;
    else if (ch === "{") depth++;
    else if (ch === "}") { depth--; if (depth === 0) lastComplete = i; }
    else if (ch === "]" && depth === 0) break;
  }
  if (lastComplete < 0) return null;
  try {
    const subjects = JSON.parse(text.slice(startIdx, lastComplete + 1) + "]");
    return { subjects, confidence: "low" };
  } catch (_) {
    return null;
  }
}

/// Real MIME type from the file's first bytes. The client used to label every
/// photo image/jpeg, but galleries also return PNG, WebP and HEIC.
export function sniffMime(base64, fallback) {
  try {
    const b = Buffer.from(String(base64).slice(0, 64), "base64");
    if (b[0] === 0xff && b[1] === 0xd8) return "image/jpeg";
    if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
    if (b.slice(0, 4).toString("ascii") === "RIFF" && b.slice(8, 12).toString("ascii") === "WEBP") return "image/webp";
    if (b.slice(0, 4).toString("ascii") === "%PDF") return "application/pdf";
    const ftyp = b.slice(4, 12).toString("ascii");
    if (ftyp.startsWith("ftyp")) {
      const brand = ftyp.slice(4);
      if (/^(heic|heix|hevc|hevx)/.test(brand)) return "image/heic";
      if (/^(mif1|msf1|heif)/.test(brand)) return "image/heif";
    }
  } catch (_) { /* fall through */ }
  return fallback;
}

export const SUPPORTED_MIME = new Set([
  "image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "application/pdf",
]);
