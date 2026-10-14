/**
 * Pure helpers for analytics aggregation (unit-testable).
 *
 * Student engagement is written as append-only `events/{id}` docs; a Firestore
 * trigger folds each into per-resource (`resourceMetrics`) and per-day
 * (`metricsDaily`) counters the CMS can actually query — Firebase Analytics
 * events themselves are NOT queryable from Firestore/CMS.
 *
 * Sponsor reporting adds:
 *  - `impression` (a card/banner was shown in a feed),
 *  - unique reach / viewers / clickers (one marker doc per user),
 *  - per-item daily buckets for date-ranged campaign reports,
 *  - banner metrics (`bannerMetrics`).
 */

/** Canonical event → counter field. Unknown events return null (ignored). */
const FIELDS = {
  impression: "impressions",
  view: "views",
  click: "clicks",
  apply: "applies",
  save: "saves",
  share: "shares",
};

export const METRIC_FIELDS = [
  "impressions",
  "views",
  "clicks",
  "applies",
  "saves",
  "shares",
];

/** Events a banner can record (banners have no detail page). */
const BANNER_EVENTS = new Set(["impression", "click"]);

export function metricField(event) {
  return FIELDS[event] || null;
}

export function isBannerEvent(event) {
  return BANNER_EVENTS.has(event);
}

/**
 * Which unique-user markers an event should try to create. Each marker is a
 * doc `<item>/<marker>/{uid}`; the first time it is created the matching
 * unique counter is incremented.
 *  - reach:    saw it anywhere (feed impression or detail view)
 *  - viewers:  opened the detail page
 *  - clickers: tapped through to the sponsor link
 */
export function uniqueMarkersFor(event) {
  switch (event) {
    case "impression":
      return [{ marker: "reached", field: "reach" }];
    case "view":
      return [
        { marker: "reached", field: "reach" },
        { marker: "viewers", field: "uniqueViewers" },
      ];
    case "click":
      return [{ marker: "clickers", field: "uniqueClickers" }];
    default:
      return [];
  }
}

/** Safe map key for a country name (bounded, never empty). */
export function countryKey(country) {
  if (typeof country !== "string") return "Unknown";
  const c = country.trim().slice(0, 60);
  return c || "Unknown";
}

/** UTC day bucket id, e.g. 20260808. */
export function dayId(date) {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, "0");
  const d = String(date.getUTCDate()).padStart(2, "0");
  return `${y}${m}${d}`;
}
