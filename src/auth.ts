import * as functionsV1 from "firebase-functions/v1";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onValueWritten } from "firebase-functions/v2/database";
import {
  db, auth, FieldValue, REGION, requireAuth, rateLimit, str, optStr, oneOf, applyXp, todayKey,
} from "./lib/common";

/** Creates the server-owned documents for every new account. */
export const onUserCreated = functionsV1.region(REGION).auth.user().onCreate(async (user) => {
  const uid = user.uid;
  const batch = db.batch();
  batch.set(db.doc(`users/${uid}`), {
    displayName: user.displayName ?? "",
    avatarUrl: user.photoURL ?? "",
    bio: "", country: "", lang: "ar", gender: null,
    role: "user", status: "active", profileComplete: false,
    level: 1, vipLevel: 0,
    followersCount: 0, followingCount: 0, friendsCount: 0, giftsReceived: 0,
    online: false, createdAt: FieldValue.serverTimestamp(), lastSeen: FieldValue.serverTimestamp(),
    privacy: { hideOnline: false, dmFriendsOnly: false },
  });
  batch.set(db.doc(`wallets/${uid}`), { coins: 0, diamonds: 0, updatedAt: FieldValue.serverTimestamp() });
  batch.set(db.doc(`user_levels/${uid}`), { xp: 0, level: 1, dayKey: todayKey(), dayXp: 0 });
  batch.set(db.doc(`users/${uid}/private/profile`), {
    email: user.email ?? null, phone: user.phoneNumber ?? null, dob: null,
  });
  await batch.commit();
  await auth.setCustomUserClaims(uid, { role: "user" });
});

/** One-time profile completion. Enforces unique usernames and a minimum age. */
export const completeProfile = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  await rateLimit(uid, "completeProfile", 10, 3600);
  const d = req.data ?? {};
  const username = str(d.username, "username", 20, 3).toLowerCase();
  if (!/^[a-z0-9_]{3,20}$/.test(username)) {
    throw new HttpsError("invalid-argument", "اسم المستخدم: أحرف إنجليزية وأرقام و _ فقط (3-20)");
  }
  const displayName = str(d.displayName, "displayName", 40, 2);
  const country = str(d.country, "country", 2, 2).toUpperCase();
  const lang = oneOf(d.lang, "lang", ["ar", "en"] as const);
  const gender = d.gender ? oneOf(d.gender, "gender", ["male", "female"] as const) : null;
  const dob = str(d.dob, "dob", 10, 10); // YYYY-MM-DD
  const dobDate = new Date(`${dob}T00:00:00Z`);
  if (isNaN(dobDate.getTime())) throw new HttpsError("invalid-argument", "تاريخ الميلاد غير صالح");
  const ageYears = (Date.now() - dobDate.getTime()) / (365.25 * 24 * 3600 * 1000);
  if (ageYears < 13) throw new HttpsError("failed-precondition", "العمر الأدنى لاستخدام التطبيق 13 سنة");
  const bio = optStr(d.bio, "bio", 160) ?? "";
  const avatarUrl = optStr(d.avatarUrl, "avatarUrl", 500);
  const phone = optStr(d.phone, "phone", 20);

  await db.runTransaction(async (tx) => {
    const userRef = db.doc(`users/${uid}`);
    const user = await tx.get(userRef);
    const oldName = user.data()?.username as string | undefined;
    const nameRef = db.doc(`usernames/${username}`);
    const nameSnap = await tx.get(nameRef);
    if (nameSnap.exists && nameSnap.data()?.uid !== uid) {
      throw new HttpsError("already-exists", "اسم المستخدم مستخدم بالفعل");
    }
    if (oldName && oldName !== username) tx.delete(db.doc(`usernames/${oldName}`));
    tx.set(nameRef, { uid });
    const update: Record<string, unknown> = {
      username, usernameLower: username, displayName, displayNameLower: displayName.toLowerCase(),
      country, lang, gender, bio, profileComplete: true,
    };
    if (avatarUrl) update.avatarUrl = avatarUrl;
    tx.update(userRef, update);
    tx.set(db.doc(`users/${uid}/private/profile`), { dob, ...(phone ? { phone } : {}) }, { merge: true });
  });
  return { ok: true };
});

/** Daily login reward (XP + small coin bonus), once per UTC day. */
export const claimDailyLogin = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const day = todayKey();
  return await db.runTransaction(async (tx) => {
    const lvlRef = db.doc(`user_levels/${uid}`);
    const walletRef = db.doc(`wallets/${uid}`);
    const [lvl, wallet] = await Promise.all([tx.get(lvlRef), tx.get(walletRef)]);
    const d = lvl.data() ?? {};
    if (d.lastDailyLogin === day) return { claimed: false };
    const yesterday = todayKey(new Date(Date.now() - 86400000));
    const streak = d.lastDailyLogin === yesterday ? Math.min((d.streak ?? 0) + 1, 7) : 1;
    const coins = 10 * streak;
    const xp = applyXp(d, 20 + 5 * streak);
    tx.set(lvlRef, { ...d, xp: xp.xp, level: xp.level, dayKey: xp.dayKey, dayXp: xp.dayXp, lastDailyLogin: day, streak }, { merge: true });
    tx.update(db.doc(`users/${uid}`), { level: xp.level });
    const balance = (wallet.data()?.coins ?? 0) + coins;
    tx.update(walletRef, { coins: balance, updatedAt: FieldValue.serverTimestamp() });
    tx.set(db.collection(`wallets/${uid}/transactions`).doc(), {
      type: "reward", currency: "coins", amount: coins, balanceAfter: balance,
      refId: `daily_${day}`, createdAt: FieldValue.serverTimestamp(),
    });
    return { claimed: true, coins, streak };
  });
});

/** Soft-deletes the account: anonymises public data, frees the username, removes the auth user. */
export const deleteAccount = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  await rateLimit(uid, "deleteAccount", 3, 3600);
  const user = await db.doc(`users/${uid}`).get();
  const username = user.data()?.username as string | undefined;
  const batch = db.batch();
  if (username) batch.delete(db.doc(`usernames/${username}`));
  batch.update(db.doc(`users/${uid}`), {
    status: "deleted", displayName: "مستخدم محذوف", username: FieldValue.delete(), usernameLower: FieldValue.delete(),
    avatarUrl: "", bio: "", online: false,
  });
  batch.delete(db.doc(`users/${uid}/private/profile`));
  await batch.commit();
  // Wallet transactions are retained for accounting/audit purposes.
  await auth.deleteUser(uid);
  return { ok: true };
});

/** Mirrors Realtime Database presence into the users collection (for "active users" lists). */
export const onPresenceChanged = onValueWritten({ ref: "/presence/{uid}", region: REGION }, async (event) => {
  const uid = event.params.uid;
  const val = event.data.after.val() as { online?: boolean } | null;
  await db.doc(`users/${uid}`).set({
    online: val?.online === true, lastSeen: FieldValue.serverTimestamp(),
  }, { merge: true });
});
