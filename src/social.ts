import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { db, FieldValue, REGION, requireAuth, rateLimit, str } from "./lib/common";
import { notify } from "./lib/notify";


/** Validates a freshly created friend request (client can only create 'pending' docs). */
export const onFriendRequestCreated = onDocumentCreated({ document: "friend_requests/{id}", region: REGION }, async (event) => {
  const snap = event.data;
  if (!snap) return;
  const { from, to } = snap.data() as { from: string; to: string };
  const invalid = async () => { await snap.ref.delete(); };
  if (from === to) return invalid();
  const [toUser, blocked, alreadyFriends, dup, fromUser] = await Promise.all([
    db.doc(`users/${to}`).get(),
    db.doc(`blocks/${to}_${from}`).get(),
    db.doc(`friends/${from}/list/${to}`).get(),
    db.collection("friend_requests").where("from", "==", from).where("to", "==", to).where("status", "==", "pending").limit(2).get(),
    db.doc(`users/${from}`).get(),
  ]);
  if (!toUser.exists || toUser.data()!.status !== "active" || blocked.exists || alreadyFriends.exists || dup.size > 1) return invalid();
  await snap.ref.update({ fromName: fromUser.data()?.displayName ?? "", fromAvatar: fromUser.data()?.avatarUrl ?? "", createdAt: FieldValue.serverTimestamp() });
  await notify(to, "friend_request", { from, requestId: snap.id }, { title: "طلب صداقة", body: `${fromUser.data()?.displayName ?? ""} أرسل لك طلب صداقة` });
});

export const respondFriendRequest = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  await rateLimit(uid, "respondFriend", 60, 60);
  const requestId = str(req.data?.requestId, "requestId", 64);
  const accept = req.data?.accept === true;
  const reqRef = db.doc(`friend_requests/${requestId}`);
  let other = "";
  await db.runTransaction(async (tx) => {
    const r = await tx.get(reqRef);
    if (!r.exists || r.data()!.to !== uid || r.data()!.status !== "pending") throw new HttpsError("not-found", "الطلب غير موجود");
    other = r.data()!.from as string;
    const [a, b] = await Promise.all([tx.get(db.doc(`users/${uid}`)), tx.get(db.doc(`users/${other}`))]);
    tx.update(reqRef, { status: accept ? "accepted" : "rejected", respondedAt: FieldValue.serverTimestamp() });
    if (accept) {
      tx.set(db.doc(`friends/${uid}/list/${other}`), { since: FieldValue.serverTimestamp(), displayName: b.data()?.displayName ?? "", avatarUrl: b.data()?.avatarUrl ?? "" });
      tx.set(db.doc(`friends/${other}/list/${uid}`), { since: FieldValue.serverTimestamp(), displayName: a.data()?.displayName ?? "", avatarUrl: a.data()?.avatarUrl ?? "" });
      tx.update(a.ref, { friendsCount: FieldValue.increment(1) });
      tx.update(b.ref, { friendsCount: FieldValue.increment(1) });
    }
  });
  if (accept) await notify(other, "friend_accepted", { by: uid }, { title: "تم قبول طلبك", body: "أصبحتما صديقين" });
  return { ok: true };
});

export const removeFriend = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const other = str(req.data?.uid, "uid", 64);
  await db.runTransaction(async (tx) => {
    const mine = await tx.get(db.doc(`friends/${uid}/list/${other}`));
    if (!mine.exists) return;
    tx.delete(mine.ref);
    tx.delete(db.doc(`friends/${other}/list/${uid}`));
    tx.update(db.doc(`users/${uid}`), { friendsCount: FieldValue.increment(-1) });
    tx.update(db.doc(`users/${other}`), { friendsCount: FieldValue.increment(-1) });
  });
  return { ok: true };
});

/** Keeps follower counters in sync (the client cannot write them). */
export const onFollowWritten = onDocumentWritten({ document: "follows/{id}", region: REGION }, async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  const delta = after && !before ? 1 : !after && before ? -1 : 0;
  if (delta === 0) return;
  const d = (after ?? before)!;
  await Promise.all([
    db.doc(`users/${d.followeeId}`).update({ followersCount: FieldValue.increment(delta) }),
    db.doc(`users/${d.followerId}`).update({ followingCount: FieldValue.increment(delta) }),
  ]);
  if (delta === 1) {
    const u = await db.doc(`users/${d.followerId}`).get();
    await notify(d.followeeId, "follow", { from: d.followerId }, { title: "متابع جديد", body: `${u.data()?.displayName ?? ""} بدأ بمتابعتك` });
  }
});

/** Updates the chat summary, unread counters and pushes a notification for each new private message. */
export const onPrivateMessageCreated = onDocumentCreated({ document: "chats/{chatId}/messages/{id}", region: REGION }, async (event) => {
  const m = event.data?.data();
  if (!m) return;
  const chatRef = db.doc(`chats/${event.params.chatId}`);
  const chat = await chatRef.get();
  const participants = (chat.data()?.participants ?? []) as string[];
  const other = participants.find((p) => p !== m.senderId);
  if (!other) return;
  const blocked = await db.doc(`blocks/${other}_${m.senderId}`).get();
  if (blocked.exists) { await event.data!.ref.delete(); return; }
  const [rUser, friend] = await Promise.all([db.doc(`users/${other}`).get(), db.doc(`friends/${other}/list/${m.senderId}`).get()]);
  if (rUser.data()?.privacy?.dmFriendsOnly === true && !friend.exists) { await event.data!.ref.delete(); return; }
  const preview = m.imageUrl ? "📷 صورة" : String(m.text ?? "").slice(0, 80);
  await chatRef.update({ lastMessage: preview, lastSender: m.senderId, lastAt: FieldValue.serverTimestamp(), [`unread.${other}`]: FieldValue.increment(1) });
  const sender = await db.doc(`users/${m.senderId}`).get();
  await notify(other, "message", { chatId: event.params.chatId, from: m.senderId }, { title: sender.data()?.displayName ?? "رسالة جديدة", body: preview });
});

export const markChatRead = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  const chatId = str(req.data?.chatId, "chatId", 140);
  const ref = db.doc(`chats/${chatId}`);
  const chat = await ref.get();
  if (!(chat.data()?.participants ?? []).includes(uid)) throw new HttpsError("permission-denied", "غير مسموح");
  await ref.update({ [`unread.${uid}`]: 0 });
  return { ok: true };
});


/** Sends a "mention" notification for @username mentions in room chat. */
export const onRoomMessageCreated = onDocumentCreated({ document: "rooms/{roomId}/messages/{id}", region: REGION }, async (event) => {
  const m = event.data?.data();
  if (!m || m.type !== "text" || !Array.isArray(m.mentions) || m.mentions.length === 0) return;
  const names = (m.mentions as string[]).slice(0, 5);
  const docs = await Promise.all(names.map((n) => db.doc(`usernames/${String(n).toLowerCase()}`).get()));
  await Promise.all(docs.map(async (d) => {
    const uid = d.data()?.uid as string | undefined;
    if (!uid || uid === m.senderId) return;
    const blocked = await db.doc(`blocks/${uid}_${m.senderId}`).get();
    if (blocked.exists) return;
    await notify(uid, "mention", { roomId: event.params.roomId, from: m.senderId },
      { title: `${m.senderName ?? ""} ذكرك في غرفة`, body: String(m.text).slice(0, 80) });
  }));
});
