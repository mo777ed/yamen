// Security-rules tests. Run with:  npm run test:rules   (needs Java + firebase-tools; starts the emulators)
// NOTE: these were written together with the rules but could not be executed in the authoring sandbox
// (the emulator download is blocked there). Run them once locally before deploying.
const { test, before, after, beforeEach } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const { initializeTestEnvironment, assertSucceeds, assertFails } = require("@firebase/rules-unit-testing");
const { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp, Timestamp } = require("firebase/firestore");

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-yemenchat",
    firestore: { rules: fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8") },
  });
});
after(async () => env && env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/alice"), { displayName: "Alice", role: "user", status: "active" });
    await setDoc(doc(db, "users/bob"), { displayName: "Bob", role: "user", status: "active" });
    await setDoc(doc(db, "wallets/alice"), { coins: 100, diamonds: 0 });
    await setDoc(doc(db, "rooms/r1"), { name: "R", ownerId: "bob", status: "live", memberCount: 1 });
    await setDoc(doc(db, "rooms/r1/members/alice"), { role: "listener", left: false });
    await setDoc(doc(db, "rooms/r1/members/muted"), { role: "listener", left: false, mutedUntil: Timestamp.fromMillis(Date.now() + 3600_000) });
    await setDoc(doc(db, "chats/alice_bob"), { participants: ["alice", "bob"] });
    await setDoc(doc(db, "audit_logs/x"), { action: "ban" });
  });
});

const as = (uid, claims = {}) => env.authenticatedContext(uid, { role: "user", ...claims }).firestore();

test("signed-out users read nothing", async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, "users/alice")));
  await assertFails(getDoc(doc(db, "rooms/r1")));
});

test("users can edit their display name but never role/status", async () => {
  const db = as("alice");
  await assertSucceeds(updateDoc(doc(db, "users/alice"), { displayName: "Alice2" }));
  await assertFails(updateDoc(doc(db, "users/alice"), { role: "admin" }));
  await assertFails(updateDoc(doc(db, "users/alice"), { status: "active", followersCount: 9999 }));
  await assertFails(updateDoc(doc(db, "users/bob"), { displayName: "Hacked" }));
});

test("wallet is read-only for the owner and invisible to others", async () => {
  await assertSucceeds(getDoc(doc(as("alice"), "wallets/alice")));
  await assertFails(getDoc(doc(as("bob"), "wallets/alice")));
  await assertFails(updateDoc(doc(as("alice"), "wallets/alice"), { coins: 1_000_000 }));
  await assertFails(setDoc(doc(as("alice"), "wallets/alice/transactions/t1"), { amount: 1 }));
});

test("economy collections are server-only", async () => {
  const db = as("alice");
  await assertFails(setDoc(doc(db, "gift_transactions/g1"), { senderId: "alice" }));
  await assertFails(setDoc(doc(db, "user_levels/alice"), { xp: 999999 }));
  await assertFails(setDoc(doc(db, "game_sessions/s1"), { userId: "alice", payout: 100000 }));
  await assertFails(setDoc(doc(db, "rankings/hosts_daily_2026-01-01/entries/alice"), { score: 1e9 }));
});

test("room chat: members can post text, others and gift spoofing are rejected", async () => {
  const good = { senderId: "alice", senderName: "Alice", senderAvatar: "", senderLevel: 1, text: "hi", type: "text", mentions: [], createdAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(as("alice"), "rooms/r1/messages/m1"), good));
  await assertFails(setDoc(doc(as("bob"), "rooms/r1/messages/m2"), { ...good, senderId: "bob" })); // bob is not a member doc
  await assertFails(setDoc(doc(as("alice"), "rooms/r1/messages/m3"), { ...good, type: "gift" }));
  await assertFails(setDoc(doc(as("alice"), "rooms/r1/messages/m4"), { ...good, senderId: "bob" }));
  await assertFails(setDoc(doc(as("alice"), "rooms/r1/messages/m5"), { ...good, text: "x".repeat(301) }));
  await assertFails(setDoc(doc(as("muted"), "rooms/r1/messages/m6"), { ...good, senderId: "muted" }));
});

test("banned accounts cannot write", async () => {
  const db = as("alice", { banned: true });
  const msg = { senderId: "alice", senderName: "A", senderAvatar: "", senderLevel: 1, text: "hi", type: "text", mentions: [], createdAt: serverTimestamp() };
  await assertFails(setDoc(doc(db, "rooms/r1/messages/m1"), msg));
  await assertFails(updateDoc(doc(db, "users/alice"), { displayName: "x" }));
});

test("follows need the deterministic id and your own uid", async () => {
  const f = { followerId: "alice", followeeId: "bob", createdAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(as("alice"), "follows/alice_bob"), f));
  await assertFails(setDoc(doc(as("alice"), "follows/random"), f));
  await assertFails(setDoc(doc(as("bob"), "follows/alice_bob"), f));
});

test("reports must be created as open by the reporter", async () => {
  const r = { reporterId: "alice", targetType: "user", targetId: "bob", reason: "spam", status: "open", createdAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(as("alice"), "reports/r1"), r));
  await assertFails(setDoc(doc(as("alice"), "reports/r2"), { ...r, status: "actioned" }));
  await assertFails(setDoc(doc(as("alice"), "reports/r3"), { ...r, reporterId: "bob" }));
  await assertFails(setDoc(doc(as("alice"), "reports/r4"), { ...r, targetType: "wallet" }));
});

test("private chats are visible to participants only", async () => {
  await assertSucceeds(getDoc(doc(as("alice"), "chats/alice_bob")));
  await assertFails(getDoc(doc(as("carol"), "chats/alice_bob")));
});

test("audit log is admin-only", async () => {
  await assertFails(getDoc(doc(as("alice"), "audit_logs/x")));
  await assertFails(getDoc(doc(as("mod", { role: "moderator" }), "audit_logs/x")));
  await assertSucceeds(getDoc(doc(as("boss", { role: "admin" }), "audit_logs/x")));
  await assertFails(deleteDoc(doc(as("boss", { role: "super_admin" }), "audit_logs/x")));
});

test("room password hashes are never readable", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), "rooms_private/r1"), { passwordHash: "abc" }));
  await assertFails(getDoc(doc(as("bob"), "rooms_private/r1")));
});
