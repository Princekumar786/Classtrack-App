/**
 * chatGuard — server-side safety net for the `chat` function.
 *
 * The system prompt already tells Gemini to stay on studies and never write
 * code, but prompts can be jailbroken. This checks the model's REPLY and, if
 * it contains source code, replaces it with a short refusal. The app's own
 * ```schedule``` and ```actions``` blocks are allowed (they are app data, not
 * code shown to the user). Plain JSON data (the learning planner asks this
 * same endpoint for a JSON topic list) is allowed too.
 */

/** The fenced block labels the app itself uses. Anything else is "code". */
const APP_BLOCKS = new Set(["schedule", "actions"]);

export const CODE_REFUSAL =
  "I'm your study assistant, so I can't write or fix code. I can explain the " +
  "idea in plain words, help you plan how to learn it, or add a task or study " +
  "plan for it. Want help with any of those?";

/// Lines that look like real source code (not normal sentences). Kept
/// case-sensitive (code keywords are lowercase) so prose like "Class 10 starts
/// at 9 (room 4)" or "Let me know (…)" is never flagged.
const CODE_LINE = new RegExp(
  [
    String.raw`^\s*(def|fn|func)\s+\w+\s*\(`,
    String.raw`^\s*class\s+\w+[\s(:{<]`,
    String.raw`^\s*(import|package)\s+[\w.'"/:]+;?\s*$`,
    String.raw`^\s*from\s+\S+\s+import\s`,
    String.raw`^\s*#include\s*[<"]`,
    String.raw`^\s*(public|private|protected|static)\s+[\w<>\[\]]+\s+\w+`,
    String.raw`^\s*(async\s+)?function\s*\w*\s*\(`,
    String.raw`^\s*(const|let|var|val|auto|int|float|double|String)\s+\w+\s*=`,
    String.raw`^\s*(struct|interface|enum)\s+\w+\s*\{`,
    String.raw`^\s*(for|while|if|else if|switch|catch)\s*\(.*\)\s*\{?\s*$`,
    String.raw`^\s*(print|printf|console\.log|System\.out\.println|cout\s*<<)`,
    String.raw`^\s*return\s+[\w().\[\]+\-*/ ]*;\s*$`,
    String.raw`^\s*<\/?(html|div|script|body|head|span|style|template)\b[^>]*>`,
    String.raw`^\s*[}\])]+;?\s*$`,
    String.raw`^\s*[\w.\[\]]+\s*(=|\+=|-=)\s*[^=].*;\s*$`,
  ].join("|")
);

/// SQL is often written in capitals, so it gets its own case-insensitive check.
const SQL_LINE =
  /^\s*(SELECT\s+.+\s+FROM\s|INSERT\s+INTO\s|UPDATE\s+\w+\s+SET\s|DELETE\s+FROM\s|CREATE\s+TABLE\s)/i;

/** Removes the app's own fenced blocks so their JSON isn't mistaken for code.
 *  The model sometimes labels an actions/schedule block as ```json (or not at
 *  all), so a json/unlabelled block holding "actions" or "subjects" counts as
 *  app data too. */
function stripAppBlocks(text) {
  return text.replace(/```(\w+)?[^\n]*\n([\s\S]*?)```/g, (block, label, body) => {
    const l = (label || "").toLowerCase();
    if (APP_BLOCKS.has(l)) return "";
    if ((l === "" || l === "json") && isJson(body)) return "";
    return block;
  });
}

function isJson(s) {
  try {
    JSON.parse(s.trim());
    return true;
  } catch {
    return false;
  }
}

/** Removes one bare JSON value (e.g. the learning planner's topic array) so
 *  its brackets aren't counted as code lines. */
function stripBareJson(text) {
  const start = text.search(/[[{]/);
  const end = Math.max(text.lastIndexOf("]"), text.lastIndexOf("}"));
  if (start < 0 || end <= start) return text;
  const candidate = text.slice(start, end + 1);
  return isJson(candidate) ? text.slice(0, start) + text.slice(end + 1) : text;
}

/**
 * True when [text] contains source code: any fenced block that isn't one of
 * the app's own (schedule/actions), or 3+ lines that look like code.
 */
export function containsCode(text) {
  if (typeof text !== "string" || text.length === 0) return false;
  const rest = stripBareJson(stripAppBlocks(text));
  if (/```/.test(rest)) return true;
  let codeLines = 0;
  for (const line of rest.split("\n")) {
    if (CODE_LINE.test(line) || SQL_LINE.test(line)) codeLines += 1;
    if (codeLines >= 3) return true;
  }
  return false;
}

/** Returns the reply to send to the app: the refusal if it contains code. */
export function guardChatReply(text) {
  return containsCode(text) ? CODE_REFUSAL : text;
}
