import { onCall, HttpsError } from "firebase-functions/v2/https";
import { AggregateField } from "firebase-admin/firestore";
import {
  db, auth, FieldValue, Timestamp, REGION, requireAuth, requireRole, roleOf, rateLimit,
  str, optStr, int, oneOf, audit, rankOf, Role,
} from "./lib/common";
import { notify } from "./lib/notify";

const UPSERT_WHITELIST = ["gifts", "vip_levels", "games", "events", "banners", "settings"] as const;

// ------------------------------------------------------------------ users
export const adminBanUser = onCall({ region: REGION }, async (req) => {
  const actor = requireRole(req, "moderator");
  const uid = str(req.data?.uid, "uid", 64);
  const kind = oneOf(req.data?.kind, "kind", ["temporary", "permanent"] as const);
  const reason = str(req.data?.reason, "reason", 300);
  const days = kind === "temporary" ? int(req.data?.days, "days", 1, 365) : 0;
  const target = await auth.getUser(uid);
  const targetRole = (target.customClaims?.role as Role) ?? "user";
  if (rankOf(targetRole) >= rankOf(roleOf(req))) throw new HttpsError("permission-denied", "لا يمكنك حظر هذا الحساب");
  const bannedUntil = kind === "temporary" ? Timestamp.fromMillis(Date.now() + days * 86400000) : null;
  await db.doc(`users/${uid}`).update({ status: "banned", bannedUntil, banReason: reason, online: false });
  await auth.setCustomUserClaims(uid, { ...target.customClaims, banned: true });
  await auth.revokeRefreshTokens(uid);
  await audit(actor, "ban_user", uid, { kind, days, reason });
  return { ok: true };
});

export const adminUnbanUser = onCall({ region: REGION }, async (req) => {
  const actor = requireRole(req, "moderator");
  const uid = str(req.data?.uid, "uid", 64);
  const target = await auth.getUser(uid);
  const claims = { ...(target.customClaims ?? {}) } as Record<string, unknown>;
  delete claims.banned;
  await auth.setCustomUserClaims(uid, claims);
  await db.doc(`users/${uid}`).update({ status: "active", bannedUntil: null, banReason: FieldValue.delete() });
  await audit(actor, "unban_user", uid);
  return { ok: true };
});

export const adminSetRole = onCall({ region: REGION }, async (req) => {
  const actor = requireRole(req, "admin");
  const uid = str(req.data?.uid, "uid", 64);
  const role = oneOf(req.data?.role, "role", ["user", "host", "moderator", "agency_manager", "admin", "super_admin"] as const);
  if ((role === "admin" || role === "super_admin") && roleOf(req) !== "super_admin") {
    throw new HttpsError("permission-denied", "المدير العام فقط يعيّن المديرين");
  }
  const target = await auth.getUser(uid);
  if (rankOf((target.customClaims?.role as Role) ?? "user") >= rankOf(roleOf(req)) && roleOf(req) !== "super_admin") {
    throw new HttpsError("permission-denied", "لا يمكنك تعديل هذا الحساب");
  }
  await auth.setCustomUserClaims(uid, { ...target.customClaims, role });
  await db.doc(`users/${uid}`).update({ role });
  await audit(actor, "set_role", uid, { role });
  return { ok: true };
});

export const adminSearchUsers = onCall({ region: REGION }, async (req) => {
  requireRole(req, "moderator");
  const q = str(req.data?.q, "q", 40, 2).toLowerCase();
  const snap = await db.collection("users").where("usernameLower", ">=", q).where("usernameLower", "<", q + "\uf8ff").limit(20).get();
  return { users: snap.docs.map((d) => ({ id: d.id, ...pick(d.data(), ["displayName", "username", "avatarUrl", "role", "status", "level", "vipLevel"]) })) };
});

function pick(o: Record<string, unknown>, keys: string[]) {
  return Object.fromEntries(keys.map((k) => [k, o[k] ?? null]));
}

// ------------------------------------------------------------------ economy
export const adminAdjustWallet = onCall({ region: REGION }, async (req) => {
  const actor = requireRole(req, "admin");
  const uid = str(req.data?.uid, "uid", 64);
  const coins = int(req.data?.coins ?? 0, "coins", -10_000_000, 10_000_000);
  const diamonds = int(req.data?.diamonds ?? 0, "diamonds", -10_000_000, 10_000_000);
  const reason = str(req.data?.reason, "reason", 200);
  if (coins === 0 && diamonds === 0) throw new HttpsError("invalid-argument", "أدخل مبلغاً");
  await db.runTransaction(async (tx) => {
    const ref = db.doc(`wallets/${uid}`);
    const w = await tx.get(ref);
    if (!w.exists) throw new HttpsError("not-found", "المحفظة غير موجودة");
    const c = (w.data()!.coins ?? 0) + coins, dm = (w.data()!.diamonds ?? 0) + diamonds;
    if (c < 0 || dm < 0) throw new HttpsError("failed-precondition", "لا يمكن أن يصبح الرصيد سالباً");
    tx.update(ref, { coins: c, diamonds: dm, updatedAt: FieldValue.serverTimestamp() });
    if (coins) tx.set(db.collection(`wallets/${uid}/transactions`).doc(), { type: "admin_adjustment", currency: "coins", amount: coins, balanceAfter: c, refId: reason, createdAt: FieldValue.serverTimestamp() });
    if (diamonds) tx.set(db.collection(`wallets/${uid}/transactions`).doc(), { type: "admin_adjustment", currency: "diamonds", amount: diamonds, balanceAfter: dm, refId: reason, createdAt: FieldValue.serverTimestamp() });
  });
  await audit(actor, "adjust_wallet", uid, { coins, diamonds, reason });
  return { ok: true };
});

// ------------------------------------------------------------------ config editor
export const adminUpsert = onCall({ region: REGION }, async (req) => {
  const actor = requireRole(req, "admin");
  const collection = oneOf(req.data?.collection, "collection", UPSERT_WHITELIST);
  const id = optStr(req.data?.id, "id", 64);
  const data = req.data?.data;
  if (typeof data !== "object" || data === null || Array.isArray(data)) throw new HttpsError("invalid-argument", "بيانات غير صالحة");
  if (JSON.stringify(data).length > 20000) throw new HttpsError("invalid-argument", "البيانات كبيرة جداً");
  // JSON editors send dates as ISO strings; store them as real Timestamps.
  for (const k of ["startsAt", "endsAt"]) {
    const v = (data as Record<string, unknown>)[k];
    if (typeof v === "string") {
      const d = new Date(v);
      if (isNaN(d.getTime())) throw new HttpsError("invalid-argument", `تاريخ غير صالح: ${k}`);
      (data as Record<string, unknown>)[k] = Timestamp.fromDate(d);
    }
  }
  const ref = id ? db.collection(collection).doc(id) : db.collection(collection).doc();
  const before = (await ref.get()).data() ?? null;
  await ref.set({ ...data, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await audit(actor, `upsert_${collection}`, ref.id, { before, after: data });
  return { id: ref.id };
});

export const adminDelete = onCall({ region: REGION }, async (req) => {
  const actor = requireRole(req, "admin");
  const collection = oneOf(req.data?.collection, "collection", UPSERT_WHITELIST);
  const id = str(req.data?.id, "id", 64);
  await db.collection(collection).doc(id).delete();
  await audit(actor, `delete_${collection}`, id);
  return { ok: true };
});

// ------------------------------------------------------------------ reports
export const adminResolveReport = onCall({ region: REGION }, async (req) => {
  const actor = requireRole(req, "moderator");
  const reportId = str(req.data?.reportId, "reportId", 64);
  const resolution = oneOf(req.data?.resolution, "resolution", ["dismissed", "actioned"] as const);
  const note = optStr(req.data?.note, "note", 300) ?? "";
  const ref = db.doc(`reports/${reportId}`);
  const r = await ref.get();
  if (!r.exists) throw new HttpsError("not-found", "البلاغ غير موجود");
  await ref.update({ status: resolution, note, resolvedBy: actor, resolvedAt: FieldValue.serverTimestamp() });
  await audit(actor, "resolve_report", reportId, { resolution, note });
  if (resolution === "actioned") {
    notify(r.data()!.reporterId, "system", { reportId }, { title: "شكراً لبلاغك", body: "تمت مراجعة بلاغك واتخاذ الإجراء المناسب" }).catch(() => undefined);
  }
  return { ok: true };
});

// ------------------------------------------------------------------ dashboard
export const adminStats = onCall({ region: REGION }, async (req) => {
  requireRole(req, "moderator");
  const c = async (q: FirebaseFirestore.Query) => (await q.count().get()).data().count;
  const fiveMin = Timestamp.fromMillis(Date.now() - 5 * 60000);
  const [users, online, rooms, activeRooms, gifts, openReports, bans, hosts, agencies, revenue, coinsInCirculation] = await Promise.all([
    c(db.collection("users")),
    c(db.collection("users").where("lastSeen", ">", fiveMin).where("online", "==", true)),
    c(db.collection("rooms")),
    c(db.collection("rooms").where("status", "==", "live")),
    c(db.collection("gift_transactions")),
    c(db.collection("reports").where("status", "==", "open")),
    c(db.collection("users").where("status", "==", "banned")),
    c(db.collection("hosts")),
    c(db.collection("agencies").where("status", "==", "active")),
    db.collection("purchases").aggregate({ total: AggregateField.sum("priceUsd") }).get(),
    db.collection("wallets").aggregate({ total: AggregateField.sum("coins") }).get(),
  ]);
  return {
    users, online, rooms, activeRooms, gifts, openReports, bans, hosts, agencies,
    revenueUsd: revenue.data().total ?? 0, coinsInCirculation: coinsInCirculation.data().total ?? 0,
  };
});

// ------------------------------------------------------------------ agencies & hosts
export const adminCreateAgency = onCall({ region: REGION }, async (req) => {
  const actor = requireRole(req, "admin");
  const name = str(req.data?.name, "name", 40, 2);
  const ownerUid = str(req.data?.ownerUid, "ownerUid", 64);
  const commissionPct = int(req.data?.commissionPct ?? 10, "commissionPct", 0, 90);
  const owner = await auth.getUser(ownerUid);
  const ref = db.collection("agencies").doc();
  await ref.set({ name, ownerId: ownerUid, status: "pending", commissionPct, earnings: 0, hostsCount: 0, createdAt: FieldValue.serverTimestamp() });
  await db.doc(`agency_members/${ref.id}_${ownerUid}`).set({ agencyId: ref.id, userId: ownerUid, role: "manager", joinedAt: FieldValue.serverTimestamp() });
  if (rankOf((owner.customClaims?.role as Role) ?? "user") < rankOf("agency_manager")) {
    await auth.setCustomUserClaims(ownerUid, { ...owner.customClaims, role: "agency_manager" });
    await db.doc(`users/${ownerUid}`).update({ role: "agency_manager" });
  }
  await audit(actor, "create_agency", ref.id, { name, ownerUid });
  return { id: ref.id };
});

export const adminSetAgencyStatus = onCall({ region: REGION }, async (req) => {
  const actor = requireRole(req, "admin");
  const agencyId = str(req.data?.agencyId, "agencyId", 64);
  const status = oneOf(req.data?.status, "status", ["active", "suspended", "pending"] as const);
  const commission = req.data?.commissionPct === undefined ? undefined : int(req.data.commissionPct, "commissionPct", 0, 90);
  const update: Record<string, unknown> = { status };
  if (commission !== undefined) update.commissionPct = commission;
  await db.doc(`agencies/${agencyId}`).update(update);
  await audit(actor, "agency_status", agencyId, update);
  return { ok: true };
});

export const agencyAddHost = onCall({ region: REGION }, async (req) => {
  const actor = requireAuth(req);
  await rateLimit(actor, "agencyAddHost", 30, 3600);
  const agencyId = str(req.data?.agencyId, "agencyId", 64);
  const hostUid = str(req.data?.uid, "uid", 64);
  const agency = await db.doc(`agencies/${agencyId}`).get();
  if (!agency.exists || agency.data()!.status !== "active") throw new HttpsError("failed-precondition", "الوكالة غير نشطة");
  const isManager = agency.data()!.ownerId === actor || (await db.doc(`agency_members/${agencyId}_${actor}`).get()).data()?.role === "manager";
  if (!isManager && rankOf(roleOf(req)) < rankOf("admin")) throw new HttpsError("permission-denied", "مدير الوكالة فقط");
  const user = await db.doc(`users/${hostUid}`).get();
  if (!user.exists || user.data()!.status !== "active") throw new HttpsError("not-found", "المستخدم غير موجود");
  if ((await db.doc(`hosts/${hostUid}`).get()).exists) throw new HttpsError("already-exists", "المستخدم مضيف بالفعل");
  const batch = db.batch();
  batch.set(db.doc(`hosts/${hostUid}`), {
    agencyId, displayName: user.data()!.displayName ?? "", avatarUrl: user.data()!.avatarUrl ?? "",
    level: 1, totalHours: 0, giftsReceived: 0, earnings: 0, createdAt: FieldValue.serverTimestamp(),
  });
  batch.set(db.doc(`agency_members/${agencyId}_${hostUid}`), { agencyId, userId: hostUid, role: "host", joinedAt: FieldValue.serverTimestamp() });
  batch.update(agency.ref, { hostsCount: FieldValue.increment(1) });
  await batch.commit();
  const target = await auth.getUser(hostUid);
  if (((target.customClaims?.role as Role) ?? "user") === "user") {
    await auth.setCustomUserClaims(hostUid, { ...target.customClaims, role: "host" });
    await db.doc(`users/${hostUid}`).update({ role: "host" });
  }
  await audit(actor, "agency_add_host", hostUid, { agencyId });
  return { ok: true };
});

// ------------------------------------------------------------------ scheduled: lift expired temporary bans
import { onSchedule } from "firebase-functions/v2/scheduler";
export const liftExpiredBans = onSchedule({ schedule: "every 60 minutes", region: REGION }, async () => {
  const snap = await db.collection("users").where("status", "==", "banned").where("bannedUntil", "<=", Timestamp.now()).limit(200).get();
  for (const d of snap.docs) {
    try {
      const u = await auth.getUser(d.id);
      const claims = { ...(u.customClaims ?? {}) } as Record<string, unknown>;
      delete claims.banned;
      await auth.setCustomUserClaims(d.id, claims);
      await d.ref.update({ status: "active", bannedUntil: null });
      await audit("system", "auto_unban", d.id);
    } catch (_) { /* user may have been deleted */ }
  }
});
