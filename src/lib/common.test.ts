import test from "node:test";
import assert from "node:assert/strict";
import { applyXp, DAILY_XP_CAP, levelFromXp, periodIds, rankOf, todayKey, xpForLevel } from "./common";

test("xp curve thresholds match the Dart LevelMath", () => {
  assert.equal(xpForLevel(1), 0);
  assert.equal(xpForLevel(2), 100);
  assert.equal(xpForLevel(3), 300);
  assert.equal(levelFromXp(0), 1);
  assert.equal(levelFromXp(99), 1);
  assert.equal(levelFromXp(100), 2);
  assert.equal(levelFromXp(299), 2);
  assert.equal(levelFromXp(300), 3);
});

test("applyXp adds XP and levels up", () => {
  const r = applyXp({ xp: 90, dayKey: todayKey(), dayXp: 0 }, 20);
  assert.equal(r.xp, 110);
  assert.equal(r.level, 2);
  assert.equal(r.added, 20);
});

test("applyXp enforces the daily cap", () => {
  const near = applyXp({ xp: 0, dayKey: todayKey(), dayXp: DAILY_XP_CAP - 10 }, 50);
  assert.equal(near.added, 10);
  assert.equal(near.dayXp, DAILY_XP_CAP);
  const capped = applyXp({ xp: 500, dayKey: todayKey(), dayXp: DAILY_XP_CAP }, 50);
  assert.equal(capped.added, 0);
  assert.equal(capped.xp, 500);
});

test("applyXp resets the daily counter on a new day", () => {
  const r = applyXp({ xp: 500, dayKey: "2000-01-01", dayXp: DAILY_XP_CAP }, 50);
  assert.equal(r.added, 50);
  assert.equal(r.dayXp, 50);
});

test("applyXp never lets the client-provided amount go negative", () => {
  const r = applyXp({ xp: 10, dayKey: todayKey(), dayXp: 0 }, -500);
  assert.equal(r.xp, 10);
  assert.equal(r.added, 0);
});

test("ranking period ids (UTC) match the Dart RankingPeriod", () => {
  const d = new Date(Date.UTC(2026, 8, 23, 12)); // Wed 2026-09-23
  assert.deepEqual(periodIds(d), { daily: "2026-09-23", weekly: "w_2026-09-21", monthly: "2026-09" });
  const sunday = new Date(Date.UTC(2026, 8, 27, 23));
  assert.equal(periodIds(sunday).weekly, "w_2026-09-21");
  const monday = new Date(Date.UTC(2026, 8, 21, 0, 30));
  assert.equal(periodIds(monday).weekly, "w_2026-09-21");
});

test("role ranking", () => {
  assert.ok(rankOf("super_admin") > rankOf("admin"));
  assert.ok(rankOf("admin") > rankOf("moderator"));
  assert.ok(rankOf("moderator") > rankOf("agency_manager"));
  assert.ok(rankOf("agency_manager") > rankOf("host"));
  assert.ok(rankOf("host") > rankOf("user"));
});
