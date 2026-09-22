import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import * as crypto from "crypto";
import {
  db, FieldValue, REGION, requireAuth, rateLimit, str, optStr, int, oneOf,
  rankOf, Role, audit, roleOf, applyXp,
} from "./lib/common";
import {
  livekitSecrets, LIVEKIT_URL, mintToken, setCanPublish, removeParticipant, webhookReceiver,
} from "./lib/livekit";
import { notify } from "./lib/notify";

type RoomRole = "owner" | "admin" | "mod" | "speaker" | "listener";
const RR_RANK: Record<RoomRole, number> = { listener: 0, speaker: 1, mod: 2, admin: 3, owner: 4 };
const CATEGORIES = ["chat", "music", "games", "friends", "entertainment", "private", "arabic", "yemen", "gulf", "international"] as const;

function hashPassword(pw: string, salt = crypto.randomBytes(16).toString("hex")): string {
  return `${salt}:${crypto.scryptSync(pw, salt, 32).toString("hex")}`;
}
function checkPassword(pw: string, stored: string): boolean {
  const [salt, hash] = stored.split(":");
  const test = crypto.scryptSync(pw, salt, 32);
  const ref = Buffer.from(hash, "hex");
  return ref.length === test.length && crypto.timingSafeEqual(ref, test);
}

async function systemMessage(roomId: string, text: string, type = "system", extra: Record<string, unknown> = {}) {
  await db.collection(`rooms/${roomId}/messages`).add({
    senderId: "system", text, type, ...extra, createdAt: FieldValue.serverTimestamp(),
  });
}

async function memberRole(roomId: string, uid: string): Promise<RoomRole | null> {
  const snap = await db.doc(`rooms/${roomId}/members/${uid}`).get();
  if (!snap.exists || snap.data()?.left === true) return null;
  return snap.data()?.role as RoomRole;
}

// ---------------------------------------------------------------- create
export const createRoom = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  await rateLimit(uid, "createRoom", 5, 3600);
  const d = req.data ?? {};
  const name = str(d.name, "name", 40, 2);
  const category = oneOf(d.category, "category", CATEGORIES);
  const type = oneOf(d.type, "type", ["public", "private"] as const);
  const seatCount = int(d.seatCount ?? 8, "seatCount", 4, 12);
  const maxUsers = int(d.maxUsers ?? 200, "maxUsers", 10, 1000);
  const coverUrl = optStr(d.coverUrl, "coverUrl", 500) ?? "";
  const password = optStr(d.password, "password", 32);
  if (type === "private" && !password) throw new HttpsError("invalid-argument", "الغرفة الخاصة تحتاج كلمة سر");

  const existing = await db.collection("rooms").where("ownerId", "==", uid).where("status", "==", "live").count().get();
  if (existing.data().count >= 3) throw new HttpsError("failed-precondition", "لا يمكنك امتلاك أكثر من 3 غرف نشطة");

  const user = (await db.doc(`users/${uid}`).get()).data() ?? {};
  const roomRef = db.collection("rooms").doc();
  const batch = db.batch();
  batch.set(roomRef, {
    name, nameLower: name.toLowerCase(), coverUrl, category, type, maxUsers, seatCount,
    description: optStr(d.description, "description", 200) ?? "",
    ownerId: uid, ownerName: user.displayName ?? "", ownerAvatar: user.avatarUrl ?? "",
    country: user.country ?? "", status: "live", featured: false,
    memberCount: 0, giftsTotal: 0, createdAt: FieldValue.serverTimestamp(),
  });
  for (let i = 1; i <= seatCount; i++) {
    batch.set(roomRef.collection("seats").doc(String(i)), { userId: null, locked: false, micMuted: false, updatedAt: FieldValue.serverTimestamp() });
  }
  if (password) batch.set(db.doc(`rooms_private/${roomRef.id}`), { passwordHash: hashPassword(password) });
  await batch.commit();
  return { roomId: roomRef.id };
});

// ---------------------------------------------------------------- join / leave
export const joinRoom = onCall({ region: REGION, secrets: livekitSecrets }, async (req) => {
  const uid = requireAuth(req);
  await rateLimit(uid, "joinRoom", 30, 60);
  const roomId = str(req.data?.roomId, "roomId", 64);
  const password = optStr(req.data?.password, "password", 32);

  const roomRef = db.doc(`rooms/${roomId}`);
  const [roomSnap, userSnap] = await Promise.all([roomRef.get(), db.doc(`users/${uid}`).get()]);
  if (!roomSnap.exists || roomSnap.data()?.status !== "live") throw new HttpsError("not-found", "الغرفة غير متاحة");
  const room = roomSnap.data()!;
  const user = userSnap.data() ?? {};
  const isOwner = room.ownerId === uid;
  const memberRef = db.doc(`rooms/${roomId}/members/${uid}`);

  const role = await db.runTransaction(async (tx) => {
    const member = await tx.get(memberRef);
    const m = member.data();
    if (m?.bannedUntil && m.bannedUntil.toMillis() > Date.now()) {
      throw new HttpsError("permission-denied", "تم حظرك من هذه الغرفة");
    }
    const alreadyIn = member.exists && m?.left !== true;
    if (!alreadyIn && !isOwner && rankOf(roleOf(req)) < rankOf("moderator")) {
      if (room.type === "private") {
        const priv = await tx.get(db.doc(`rooms_private/${roomId}`));
        const stored = priv.data()?.passwordHash as string | undefined;
        if (!stored || !password || !checkPassword(password, stored)) {
          throw new HttpsError("permission-denied", "كلمة سر الغرفة غير صحيحة");
        }
      }
      if ((room.memberCount ?? 0) >= room.maxUsers) throw new HttpsError("resource-exhausted", "الغرفة ممتلئة");
    }
    const newRole: RoomRole = (m?.role as RoomRole) ?? (isOwner ? "owner" : "listener");
    tx.set(memberRef, {
      role: newRole, left: false, joinedAt: alreadyIn ? m?.joinedAt : FieldValue.serverTimestamp(),
      username: user.username ?? "", displayName: user.displayName ?? "", avatarUrl: user.avatarUrl ?? "",
      level: user.level ?? 1, vipLevel: user.vipLevel ?? 0,
      mutedUntil: m?.mutedUntil ?? null, bannedUntil: null,
    }, { merge: true });
    if (!alreadyIn) tx.update(roomRef, { memberCount: FieldValue.increment(1) });
    return newRole;
  });

  const canPublish = RR_RANK[role] >= RR_RANK.speaker;
  const token = await mintToken({ roomId, uid, name: user.displayName ?? uid, canPublish });
  await systemMessage(roomId, user.displayName ?? "", "join", { userId: uid, vipLevel: user.vipLevel ?? 0 });
  return { token, url: LIVEKIT_URL.value(), role };
});

/** Shared by leaveRoom, kick/ban and the LiveKit webhook. */
export async function removeMemberInternal(roomId: string, uid: string): Promise<void> {
  const roomRef = db.doc(`rooms/${roomId}`);
  const memberRef = db.doc(`rooms/${roomId}/members/${uid}`);
  const minutes = await db.runTransaction(async (tx) => {
    const [member, seats] = await Promise.all([
      tx.get(memberRef), tx.get(db.collection(`rooms/${roomId}/seats`).where("userId", "==", uid)),
    ]);
    if (!member.exists || member.data()?.left === true) return 0;
    seats.docs.forEach((s) => tx.update(s.ref, { userId: null, micMuted: false, updatedAt: FieldValue.serverTimestamp() }));
    const role = member.data()?.role as RoomRole;
    tx.update(memberRef, { left: true, role: role === "speaker" ? "listener" : role });
    tx.update(roomRef, { memberCount: FieldValue.increment(-1) });
    const joined = member.data()?.joinedAt?.toMillis?.() ?? Date.now();
    return Math.max(0, Math.floor((Date.now() - joined) / 60000));
  });
  if (minutes > 0) await grantVoiceXp(roomId, uid, minutes);
}

async function grantVoiceXp(roomId: string, uid: string, minutes: number): Promise<void> {
  const lvlRef = db.doc(`user_levels/${uid}`);
  const hostRef = db.doc(`hosts/${uid}`);
  await db.runTransaction(async (tx) => {
    const [lvl, host] = await Promise.all([tx.get(lvlRef), tx.get(hostRef)]);
    const xp = applyXp(lvl.data(), Math.min(minutes, 120)); // 1 XP per minute, max 120 per session
    tx.set(lvlRef, { xp: xp.xp, level: xp.level, dayKey: xp.dayKey, dayXp: xp.dayXp }, { merge: true });
    tx.set(db.doc(`users/${uid}`), { level: xp.level }, { merge: true });
    if (host.exists) tx.update(hostRef, { totalHours: FieldValue.increment(minutes / 60) });
  });
}

export const leaveRoom = onCall({ region: REGION, secrets: livekitSecrets }, async (req) => {
  const uid = requireAuth(req);
  const roomId = str(req.data?.roomId, "roomId", 64);
  await removeMemberInternal(roomId, uid);
  await removeParticipant(roomId, uid);
  return { ok: true };
});

/** LiveKit -> this endpoint. Configure in the LiveKit dashboard: https://<region>-<project>.cloudfunctions.net/livekitWebhook */
export const livekitWebhook = onRequest({ region: REGION, secrets: livekitSecrets }, async (req, res) => {
  try {
    const event = await webhookReceiver().receive(JSON.stringify(req.body), req.get("Authorization") ?? "");
    if (event.event === "participant_left" && event.room?.name && event.participant?.identity) {
      await removeMemberInternal(event.room.name, event.participant.identity);
    }
    res.status(200).send("ok");
  } catch (e) {
    res.status(401).send("invalid");
  }
});

// ---------------------------------------------------------------- seats
const SEAT_ACTIONS = ["take", "leave", "invite", "remove", "mute", "unmute", "lock", "unlock", "move"] as const;

export const manageSeat = onCall({ region: REGION, secrets: livekitSecrets }, async (req) => {
  const uid = requireAuth(req);
  await rateLimit(uid, "manageSeat", 60, 60);
  const roomId = str(req.data?.roomId, "roomId", 64);
  const action = oneOf(req.data?.action, "action", SEAT_ACTIONS);
  const seat = req.data?.seat === undefined ? 0 : int(req.data.seat, "seat", 1, 12);
  const targetUid = optStr(req.data?.targetUid, "targetUid", 64);
  const toSeat = req.data?.toSeat === undefined ? 0 : int(req.data.toSeat, "toSeat", 1, 12);

  const myRole = await memberRole(roomId, uid);
  if (!myRole) throw new HttpsError("failed-precondition", "انضم للغرفة أولاً");
  const isManager = RR_RANK[myRole] >= RR_RANK.mod;
  const seatRef = (n: number) => db.doc(`rooms/${roomId}/seats/${n}`);

  let publishChange: { uid: string; canPublish: boolean } | null = null;

  await db.runTransaction(async (tx) => {
    const roomSnap = await tx.get(db.doc(`rooms/${roomId}`));
    if (!roomSnap.exists) throw new HttpsError("not-found", "الغرفة غير موجودة");
    const seatCount = roomSnap.data()!.seatCount as number;
    const need = (n: number) => { if (n < 1 || n > seatCount) throw new HttpsError("invalid-argument", "مقعد غير صالح"); };

    if (action === "take") {
      need(seat);
      const [s, mine] = await Promise.all([tx.get(seatRef(seat)), tx.get(db.collection(`rooms/${roomId}/seats`).where("userId", "==", uid))]);
      if (!mine.empty) throw new HttpsError("failed-precondition", "أنت على مقعد بالفعل");
      if (s.data()?.userId) throw new HttpsError("failed-precondition", "المقعد مشغول");
      if (s.data()?.locked && !isManager) throw new HttpsError("permission-denied", "المقعد مقفل");
      tx.update(seatRef(seat), { userId: uid, micMuted: false, updatedAt: FieldValue.serverTimestamp() });
      if (RR_RANK[myRole] < RR_RANK.speaker) tx.update(db.doc(`rooms/${roomId}/members/${uid}`), { role: "speaker" });
      publishChange = { uid, canPublish: true };
      return;
    }
    if (action === "leave") {
      const mine = await tx.get(db.collection(`rooms/${roomId}/seats`).where("userId", "==", uid));
      mine.docs.forEach((d) => tx.update(d.ref, { userId: null, micMuted: false, updatedAt: FieldValue.serverTimestamp() }));
      if (myRole === "speaker") tx.update(db.doc(`rooms/${roomId}/members/${uid}`), { role: "listener" });
      publishChange = { uid, canPublish: RR_RANK[myRole] >= RR_RANK.admin ? true : false };
      return;
    }
    if (!isManager) throw new HttpsError("permission-denied", "ليست لديك صلاحية إدارة المقاعد");

    if (action === "lock" || action === "unlock") {
      need(seat);
      tx.update(seatRef(seat), { locked: action === "lock", updatedAt: FieldValue.serverTimestamp() });
      return;
    }
    // Actions below act on a seat occupant.
    need(seat);
    const s = await tx.get(seatRef(seat));
    const occupant = s.data()?.userId as string | null;

    if (action === "invite") {
      if (!targetUid) throw new HttpsError("invalid-argument", "حدد المستخدم");
      if (occupant) throw new HttpsError("failed-precondition", "المقعد مشغول");
      const [tm, mine] = await Promise.all([tx.get(db.doc(`rooms/${roomId}/members/${targetUid}`)), tx.get(db.collection(`rooms/${roomId}/seats`).where("userId", "==", targetUid))]);
      if (!tm.exists || tm.data()?.left) throw new HttpsError("failed-precondition", "المستخدم ليس في الغرفة");
      if (!mine.empty) throw new HttpsError("failed-precondition", "المستخدم على مقعد بالفعل");
      tx.update(seatRef(seat), { userId: targetUid, micMuted: false, updatedAt: FieldValue.serverTimestamp() });
      if (RR_RANK[tm.data()!.role as RoomRole] < RR_RANK.speaker) tx.update(tm.ref, { role: "speaker" });
      publishChange = { uid: targetUid, canPublish: true };
      return;
    }
    if (!occupant) throw new HttpsError("failed-precondition", "المقعد فارغ");
    const occRole = ((await tx.get(db.doc(`rooms/${roomId}/members/${occupant}`))).data()?.role ?? "listener") as RoomRole;
    if (occupant !== uid && RR_RANK[occRole] >= RR_RANK[myRole]) throw new HttpsError("permission-denied", "لا يمكنك إدارة هذا المستخدم");

    if (action === "remove") {
      tx.update(seatRef(seat), { userId: null, micMuted: false, updatedAt: FieldValue.serverTimestamp() });
      if (occRole === "speaker") tx.update(db.doc(`rooms/${roomId}/members/${occupant}`), { role: "listener" });
      publishChange = { uid: occupant, canPublish: RR_RANK[occRole] >= RR_RANK.mod };
    } else if (action === "mute" || action === "unmute") {
      tx.update(seatRef(seat), { micMuted: action === "mute", updatedAt: FieldValue.serverTimestamp() });
      publishChange = { uid: occupant, canPublish: action === "unmute" };
    } else if (action === "move") {
      need(toSeat);
      const dest = await tx.get(seatRef(toSeat));
      if (dest.data()?.userId) throw new HttpsError("failed-precondition", "المقعد الهدف مشغول");
      tx.update(seatRef(seat), { userId: null, micMuted: false, updatedAt: FieldValue.serverTimestamp() });
      tx.update(seatRef(toSeat), { userId: occupant, micMuted: s.data()?.micMuted ?? false, updatedAt: FieldValue.serverTimestamp() });
    }
  });

  if (publishChange) {
    const pc = publishChange as { uid: string; canPublish: boolean };
    await setCanPublish(roomId, pc.uid, pc.canPublish);
    if (action === "invite") {
      await notify(pc.uid, "room_invitation", { roomId }, { title: "دعوة للتحدث", body: "تمت دعوتك للتحدث في الغرفة" });
    }
  }
  return { ok: true };
});

// ---------------------------------------------------------------- moderation
export const roomModeration = onCall({ region: REGION, secrets: livekitSecrets }, async (req) => {
  const uid = requireAuth(req);
  await rateLimit(uid, "roomModeration", 40, 60);
  const roomId = str(req.data?.roomId, "roomId", 64);
  const action = oneOf(req.data?.action, "action", ["muteChat", "unmuteChat", "kick", "ban", "deleteMessage", "setRole"] as const);
  const myRole = await memberRole(roomId, uid);
  const staff = rankOf(roleOf(req)) >= rankOf("moderator");
  if (!myRole && !staff) throw new HttpsError("permission-denied", "غير مسموح");
  if (!staff && RR_RANK[myRole!] < RR_RANK.mod) throw new HttpsError("permission-denied", "ليست لديك صلاحية الإشراف");

  if (action === "deleteMessage") {
    const messageId = str(req.data?.messageId, "messageId", 64);
    await db.doc(`rooms/${roomId}/messages/${messageId}`).delete();
    return { ok: true };
  }
  const targetUid = str(req.data?.targetUid, "targetUid", 64);
  const targetRole = (await memberRole(roomId, targetUid)) ?? "listener";
  if (!staff && RR_RANK[targetRole] >= RR_RANK[myRole!]) throw new HttpsError("permission-denied", "لا يمكنك إدارة هذا المستخدم");
  const memberRef = db.doc(`rooms/${roomId}/members/${targetUid}`);
  const minutes = req.data?.minutes === undefined ? 10 : int(req.data.minutes, "minutes", 1, 60 * 24 * 30);

  switch (action) {
    case "muteChat":
      await memberRef.set({ mutedUntil: new Date(Date.now() + minutes * 60000) }, { merge: true }); break;
    case "unmuteChat":
      await memberRef.set({ mutedUntil: null }, { merge: true }); break;
    case "kick":
      await removeMemberInternal(roomId, targetUid); await removeParticipant(roomId, targetUid); break;
    case "ban":
      await removeMemberInternal(roomId, targetUid);
      await memberRef.set({ bannedUntil: new Date(Date.now() + minutes * 60000) }, { merge: true });
      await removeParticipant(roomId, targetUid);
      await audit(uid, "room_ban", targetUid, { roomId, minutes });
      break;
    case "setRole": {
      const newRole = oneOf(req.data?.role, "role", ["admin", "mod", "listener"] as const);
      if (!staff && myRole !== "owner") throw new HttpsError("permission-denied", "المالك فقط يعيّن المشرفين");
      await memberRef.set({ role: newRole }, { merge: true });
      await setCanPublish(roomId, targetUid, newRole !== "listener");
      break;
    }
  }
  return { ok: true };
});

export const setRoomPassword = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const roomId = str(req.data?.roomId, "roomId", 64);
  const password = optStr(req.data?.password, "password", 32);
  const room = await db.doc(`rooms/${roomId}`).get();
  if (room.data()?.ownerId !== uid) throw new HttpsError("permission-denied", "المالك فقط");
  if (password) {
    await db.doc(`rooms_private/${roomId}`).set({ passwordHash: hashPassword(password) });
    await room.ref.update({ type: "private" });
  } else {
    await db.doc(`rooms_private/${roomId}`).delete();
    await room.ref.update({ type: "public" });
  }
  return { ok: true };
});

export const closeRoom = onCall({ region: REGION, secrets: livekitSecrets }, async (req) => {
  const uid = requireAuth(req);
  const roomId = str(req.data?.roomId, "roomId", 64);
  const room = await db.doc(`rooms/${roomId}`).get();
  const staff = rankOf(roleOf(req) as Role) >= rankOf("moderator");
  if (room.data()?.ownerId !== uid && !staff) throw new HttpsError("permission-denied", "غير مسموح");
  await room.ref.update({ status: "closed", memberCount: 0, closedAt: FieldValue.serverTimestamp() });
  if (staff && room.data()?.ownerId !== uid) await audit(uid, "room_close", roomId);
  return { ok: true };
});
