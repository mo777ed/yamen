import * as admin from "firebase-admin";
import { HttpsError, CallableRequest } from "firebase-functions/v2/https";

if (admin.apps.length === 0) admin.initializeApp();

export const db = admin.firestore();
export const auth = admin.auth();
export const FieldValue = admin.firestore.FieldValue;
export const Timestamp = admin.firestore.Timestamp;
export const REGION = process.env.FUNCTIONS_REGION || "europe-west1";

export type Role = "user" | "host" | "moderator" | "agency_manager" | "admin" | "super_admin";
const ROLE_RANK: Record<Role, number> = {
  user: 0, host: 1, agency_manager: 2, moderator: 3, admin: 4, super_admin: 5,
};

export function requireAuth(req: CallableRequest): string {
  if (!req.auth) throw new HttpsError("unauthenticated", "سجّل الدخول أولاً");
  if (req.auth.token.banned === true) throw new HttpsError("permission-denied", "حسابك محظور");
  return req.auth.uid;
}

export function roleOf(req: CallableRequest): Role {
  return ((req.auth?.token.role as Role) ?? "user");
}

export function requireRole(req: CallableRequest, min: Role): string {
  const uid = requireAuth(req);
  if (ROLE_RANK[roleOf(req)] < ROLE_RANK[min]) {
    throw new HttpsError("permission-denied", "ليست لديك صلاحية لهذا الإجراء");
  }
  return uid;
}

export function rankOf(role: Role): number { return ROLE_RANK[role] ?? 0; }

// ---------- validation ----------
export function str(v: unknown, name: string, max = 200, min = 1): string {
  if (typeof v !== "string" || v.trim().length < min || v.length > max) {
    throw new HttpsError("invalid-argument", `قيمة غير صالحة: ${name}`);
  }
  return v.trim();
}
export function optStr(v: unknown, name: string, max = 200): string | undefined {
  if (v === undefined || v === null || v === "") return undefined;
  return str(v, name, max, 0);
}
export function int(v: unknown, name: string, min: number, max: number): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < min || v > max) {
    throw new HttpsError("invalid-argument", `قيمة غير صالحة: ${name}`);
  }
  return v;
}
export function oneOf<T extends string>(v: unknown, name: string, allowed: readonly T[]): T {
  if (typeof v !== "string" || !allowed.includes(v as T)) {
    throw new HttpsError("invalid-argument", `قيمة غير صالحة: ${name}`);
  }
  return v as T;
}

// ---------- rate limiting (per user, per key) ----------
export async function rateLimit(uid: string, key: string, max: number, windowSec: number): Promise<void> {
  const ref = db.doc(`rate_limits/${uid}_${key}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const d = snap.data() as { count: number; start: number } | undefined;
    if (!d || now - d.start > windowSec * 1000) {
      tx.set(ref, { count: 1, start: now });
      return;
    }
    if (d.count >= max) throw new HttpsError("resource-exhausted", "محاولات كثيرة، حاول لاحقاً");
    tx.update(ref, { count: d.count + 1 });
  });
}

// ---------- audit ----------
export async function audit(
  actorId: string, action: string, targetId: string | null,
  extra: Record<string, unknown> = {},
): Promise<void> {
  await db.collection("audit_logs").add({
    actorId, action, targetId, ...extra, createdAt: FieldValue.serverTimestamp(),
  });
}

// ---------- levels / XP (formula mirrored in lib/features/levels) ----------
export const DAILY_XP_CAP = 3000;
export function xpForLevel(level: number): number { return 50 * level * (level - 1); }
export function levelFromXp(xp: number): number {
  let l = 1;
  while (xpForLevel(l + 1) <= xp) l++;
  return l;
}
export function todayKey(d = new Date()): string { return d.toISOString().slice(0, 10); }

/** Returns the new user_levels document data after adding [amount] XP (capped daily). */
export function applyXp(
  current: { xp?: number; dayKey?: string; dayXp?: number } | undefined,
  amount: number,
): { xp: number; level: number; dayKey: string; dayXp: number; added: number } {
  const day = todayKey();
  const dayXp = current?.dayKey === day ? (current.dayXp ?? 0) : 0;
  const room = Math.max(0, DAILY_XP_CAP - dayXp);
  const added = Math.max(0, Math.min(amount, room));
  const xp = (current?.xp ?? 0) + added;
  return { xp, level: levelFromXp(xp), dayKey: day, dayXp: dayXp + added, added };
}

// ---------- ranking periods (UTC) ----------
export function periodIds(d = new Date()): { daily: string; weekly: string; monthly: string } {
  const day = todayKey(d);
  const dow = (d.getUTCDay() + 6) % 7; // Monday = 0
  const monday = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - dow));
  return { daily: day, weekly: `w_${todayKey(monday)}`, monthly: day.slice(0, 7) };
}
