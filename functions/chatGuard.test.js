import { test } from "node:test";
import assert from "node:assert/strict";
import { containsCode, guardChatReply, CODE_REFUSAL } from "./chatGuard.js";

test("fenced python code is blocked", () => {
  const r = "Sure!\n```python\ndef add(a, b):\n    return a + b\n```";
  assert.equal(containsCode(r), true);
  assert.equal(guardChatReply(r), CODE_REFUSAL);
});

test("unfenced JavaScript is blocked", () => {
  const r = [
    "Here you go:",
    "function sum(arr) {",
    "  let total = 0;",
    "  for (const x of arr) {",
    "    total += x;",
    "  }",
    "  return total;",
    "}",
  ].join("\n");
  assert.equal(containsCode(r), true);
});

test("unfenced SQL is blocked", () => {
  const r = "SELECT name FROM students\nWHERE age > 18;\nINSERT INTO t VALUES (1);\nDELETE FROM t WHERE id = 1;";
  assert.equal(containsCode(r), true);
});

test("app actions and schedule blocks are allowed", () => {
  const r =
    'Done — logged ₹20 for food.\n```actions\n{ "actions": [ { "type": "expense", "title": "food", "amount": 20, "category": "food" } ] }\n```';
  assert.equal(containsCode(r), false);
  const s =
    'Here is your timetable.\n```schedule\n{ "subjects": [], "confidence": "low" }\n```';
  assert.equal(containsCode(s), false);
  assert.equal(guardChatReply(s), s);
});

test("actions mislabelled as json are still allowed", () => {
  const r = 'Okay.\n```json\n{ "actions": [ { "type": "delete", "entity": "task", "all": true } ] }\n```';
  assert.equal(containsCode(r), false);
});

test("learning-planner JSON (fenced or bare, pretty-printed) is allowed", () => {
  const arr = JSON.stringify(
    [{ title: "Loops", unit: "Basics", estMinutes: 30, sections: [{ title: "for", points: ["a", "b"] }] }],
    null,
    2
  );
  assert.equal(containsCode(arr), false);
  assert.equal(containsCode("```json\n" + arr + "\n```"), false);
  assert.equal(containsCode("Here you go:\n" + arr), false);
});

test("normal study answers are not flagged", () => {
  const r = [
    "Here is a quick plan for Data Structures:",
    "",
    "• Class 10 starts at 9 (room 4).",
    "• Let me know (anytime) if you want more.",
    "• Return the library book by Friday; it's due then.",
    "• A for loop repeats steps; a while loop repeats until a condition is false.",
    "",
    "Public holiday on Monday: no classes.",
  ].join("\n");
  assert.equal(containsCode(r), false);
});
