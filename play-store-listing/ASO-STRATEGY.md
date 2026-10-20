# ClassTrack ASO strategy and measurement plan

## Goal
Increase qualified Play Store impressions and install conversion by matching the listing to problems students actively search for. The main promise is attendance control; the proof is the bunk calculator, timetable, homework, exams and GPA in one app.

This document deliberately does **not** claim search volumes or rankings. Validate demand in Play Console before making decisions.

## Keyword map

| Priority | Search intent / phrase | Where it appears | Why it belongs |
|---|---|---|---|
| Primary | attendance tracker | App name; opening sentence; attendance section | Exact description of the core job the app performs. |
| Primary, India-focused | bunk calculator | Short description; opening sentence; attendance section; screenshot 1 | Specific high-intent reason to choose ClassTrack. |
| Secondary | attendance percentage / attendance target | Opening sentence; attendance section | Matches the outcome students want. |
| Secondary | class timetable / class schedule | Short description; opening sentence; timetable and AI-import sections | Explains the recurring schedule feature. |
| Secondary | student planner | Opening sentence; homework section | Broad category term, supported by real features. |
| Secondary | homework planner / assignments | Short description; homework section | Captures deadline-management intent. |
| Secondary | exam planner / exam countdown | Short description; homework section | Captures time-sensitive academic intent. |
| Secondary | GPA calculator | Short description; GPA section | Exact feature query with strong relevance. |
| Supporting | study planner / study plan | AI assistant and homework sections | Relevant only because the app makes a study plan. |
| Supporting | scholarships / internships | Opportunities section | Feature discovery, not the main acquisition hook. |

Use these phrases in normal sentences only. Google Play does not provide a hidden keyword field, and repeated word lists reduce trust and can violate metadata policy.

## Metadata to publish

**App name (30/30 characters)**
`ClassTrack: Study & Attendance`

**Short description (78/80 characters)**
`Study planner with attendance tracker, bunk calculator, timetable, exams & GPA`

Positioning update (2026-10-15): lead with the broad "study planner" search that competitors win on, and keep attendance + bunk calculator as the unique reason to install.

The full description in `full-description.txt` is the matching production copy. Do not put multiple alternatives into Play Console. Use only the version marked **PUBLISH NOW**.

## Country and language direction

1. **English (India):** Use the main listing. Keep the word `bunk`, because it matches the local student term and is clearly explained by the feature.
2. **English (United States, United Kingdom, Canada, Australia):** If a custom store listing is available and data shows low conversion, test an attendance-led version without relying on `bunk` in the first line. Keep the app name unchanged unless the experiment specifically tests it.
3. **Hindi (India):** Add a native-speaker-reviewed Hindi listing after the English version has a stable baseline. Translate for natural student language; do not translate word by word. Keep feature names such as GPA only if the reviewer confirms students use them that way.
4. **Other locales:** Add them only where Play Console shows meaningful impressions or installs. A small number of accurate local listings is better than many machine-translated ones.

## Experiment sequence

Run only one Play Store experiment at a time. Target the same countries and let it run for at least 14 complete days, including the same weekdays. Do not judge it by a single quiet day.

| Order | Test | Keep fixed | Success measure |
|---|---|---|---|
| 1 | Short description A vs B | App name, description, screenshots, countries | Store listing acquisition conversion and installs, not impressions alone. |
| 2 | Screenshot 1: attendance ring vs bunk-calculator result | All metadata and other screenshots | Store listing acquisition conversion. |
| 3 | Screenshot order: AI import at #2 vs timetable at #2 | Screenshot 1 and metadata | Conversion, especially among search visitors. |
| 4 | Country-specific custom listing | Baseline listing for other countries | Conversion and retained installs in that country. |

Do not change the title unless a short-description or screenshot test has not improved conversion. The existing title is already at the 30-character limit and directly describes the app.

## Why October 7-10 may look empty

The provided Play Console view is a **last 28 days** chart ending on **October 8**. It reports 2.65K device impressions (-49%) and 359 device acquisitions (+202%). It does not prove zero traffic on October 9 or 10: recent daily reporting can lag, and the selected chart has not reached those dates.

Before treating this as a discovery outage, check these items in Play Console:

1. Set the exact date range to October 1-10 after October 12 or later, so the final days can finish reporting.
2. Compare **device impressions**, **store listing visitors**, **device acquisitions** and **store listing acquisition conversion**. A fall in impressions needs a different fix from a fall in conversion.
3. Break the report down by acquisition source (Search, Explore/Browse, Ads if used), country and app version. This shows whether the fall is search-specific or a normal traffic change.
4. Check app availability by country, publishing overview, policy status, managed publishing and production release status. A paused or unavailable release is a real outage.
5. Check Android vitals, crashes, ANRs, ratings and review themes. Poor quality signals can hurt Play distribution and conversion.
6. Compare with the same weekdays and the previous 28 days. Weekends, exam periods and college holidays can cause normal changes.

## Conversion essentials outside text

- Make screenshot 1 show a real attendance percentage plus a clear bunk-calculator result. It must be understandable without reading the description.
- Use readable text at normal phone size, one benefit per image and genuine in-app screens. Do not cover all screenshots with small feature lists.
- Keep the feature graphic focused on attendance, not a generic product collage.
- Request a rating only after a positive action, such as completing a timetable import or reaching an attendance goal. Never gate features or support behind a rating.
- Make onboarding reach the attendance/timetable value quickly. Store conversion is wasted if first opens do not become active users.

## Weekly scorecard

Record the following for each country and acquisition source before and after a single experiment:

- Device impressions
- Store listing visitors
- Device acquisitions
- Store listing acquisition conversion
- First opens
- 7-day retention
- Rating average and number of new ratings
- Crashes and ANRs

A listing change is a win only when it improves qualified installs or conversion without damaging first opens, retention or rating quality.
