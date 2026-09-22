import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import {
  db, FieldValue, REGION, requireAuth, rateLimit, str, int, applyXp, periodIds,
} from "./lib/common";
import { notify } from "./lib/notify";

const DEFAULT_DIAMOND_RATE = 0.5; // receiver earns 50% of the gift's list price in diamonds

/**
 * Sends a gift. Everything (balance check, debit, credit, ledger, XP, host/agency
 * earnings, room event) happens in ONE Firestore transaction, guarded by an
 * idempotency key so client retries can never double-charge.
 */
export const sendGift = onCall({ region: REGION }, async (req) => {
  const senderId = requireAuth(req);
  await rateLimit(senderId, "sendGift", 60, 60);
  const d = req.data ?? {};
  const roomId = str(d.roomId, "roomId", 64);
  const receiverId = str(d.receiverId, "receiverId", 64);
  const giftId = str(d.giftId, "giftId", 64);
  const qty = int(d.qty ?? 1, "qty", 1, 999);
  const key = str(d.idempotencyKey, "idempotencyKey", 64, 8);
  if (senderId === receiverId) throw new HttpsError("invalid-argument", "لا يمكنك إهداء نفسك");

  const idemRef = db.doc(`idempotency/gift_${senderId}_${key}`);
  const result = await db.runTransaction(async (tx) => {
    const refs = {
      idem: idemRef,
      gift: db.doc(`gifts/${giftId}`),
      sWallet: db.doc(`wallets/${senderId}`),
      rWallet: db.doc(`wallets/${receiverId}`),
      sUser: db.doc(`users/${senderId}`),
      rUser: db.doc(`users/${receiverId}`),
      sLvl: db.doc(`user_levels/${senderId}`),
      rLvl: db.doc(`user_levels/${receiverId}`),
      sVip: db.doc(`user_vip/${senderId}`),
      host: db.doc(`hosts/${receiverId}`),
      block: db.doc(`blocks/${receiverId}_${senderId}`),
      room: db.doc(`rooms/${roomId}`),
      econ: db.doc("settings/economy"),
    };
    // ---- all reads first ----
    const s = Object.fromEntries(await Promise.all(Object.entries(refs).map(async ([k, r]) => [k, await tx.get(r)]))) as Record<keyof typeof refs, FirebaseFirestore.DocumentSnapshot>;
    if (s.idem.exists) return s.idem.data()!.result as Record<string, unknown>; // retry: return same result
    if (!s.gift.exists || s.gift.data()!.enabled !== true) throw new HttpsError("not-found", "الهدية غير متاحة");
    if (!s.room.exists) throw new HttpsError("not-found", "الغرفة غير موجودة");
    if (!s.rUser.exists || s.rUser.data()!.status !== "active") throw new HttpsError("not-found", "المستلم غير متاح");
    if (s.block.exists) throw new HttpsError("permission-denied", "لا يمكنك إرسال هدية لهذا المستخدم");

    const gift = s.gift.data()!;
    const listTotal = (gift.price as number) * qty;
    let discountPct = 0;
    const vip = s.sVip.data();
    if (vip && vip.level > 0 && vip.expiresAt?.toMillis?.() > Date.now()) {
      const lvl = await tx.get(db.doc(`vip_levels/${vip.level}`));
      discountPct = Math.min(50, lvl.data()?.perks?.giftDiscountPct ?? 0);
    }
    const cost = Math.ceil(listTotal * (100 - discountPct) / 100);
    const senderCoins = (s.sWallet.data()?.coins ?? 0) as number;
    if (senderCoins < cost) throw new HttpsError("failed-precondition", "رصيدك غير كافٍ");

    const rate = (s.econ.data()?.diamondRate ?? DEFAULT_DIAMOND_RATE) as number;
    const diamonds = Math.floor(listTotal * rate);

    // Host / agency split
    let hostShare = diamonds;
    let agencyId: string | null = null;
    let agencySnap: FirebaseFirestore.DocumentSnapshot | null = null;
    if (s.host.exists && s.host.data()!.agencyId) {
      agencyId = s.host.data()!.agencyId as string;
      agencySnap = await tx.get(db.doc(`agencies/${agencyId}`));
      const pct = Math.min(90, Math.max(0, agencySnap.data()?.commissionPct ?? 0));
      hostShare = diamonds - Math.floor(diamonds * pct / 100);
    }
    const agencyShare = diamonds - hostShare;

    const sXp = applyXp(s.sLvl.data(), Math.max(1, Math.floor(cost / 10)));
    const rXp = applyXp(s.rLvl.data(), Math.floor(diamonds / 20));

    // ---- writes ----
    const sBal = senderCoins - cost;
    const rBal = ((s.rWallet.data()?.diamonds ?? 0) as number) + hostShare;
    tx.update(refs.sWallet, { coins: sBal, updatedAt: FieldValue.serverTimestamp() });
    tx.update(refs.rWallet, { diamonds: rBal, updatedAt: FieldValue.serverTimestamp() });
    const giftTxRef = db.collection("gift_transactions").doc();
    tx.set(giftTxRef, {
      senderId, receiverId, roomId, giftId, qty, giftName: gift.name, totalPrice: cost, listPrice: listTotal,
      diamondsEarned: hostShare, agencyId, agencyShare,
      senderName: s.sUser.data()!.displayName ?? "", senderAvatar: s.sUser.data()!.avatarUrl ?? "",
      receiverName: s.rUser.data()!.displayName ?? "", receiverAvatar: s.rUser.data()!.avatarUrl ?? "",
      roomName: s.room.data()!.name ?? "",
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(db.collection(`wallets/${senderId}/transactions`).doc(), {
      type: "gift", currency: "coins", amount: -cost, balanceAfter: sBal, refId: giftTxRef.id, createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(db.collection(`wallets/${receiverId}/transactions`).doc(), {
      type: "gift", currency: "diamonds", amount: hostShare, balanceAfter: rBal, refId: giftTxRef.id, createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(refs.sLvl, { xp: sXp.xp, level: sXp.level, dayKey: sXp.dayKey, dayXp: sXp.dayXp }, { merge: true });
    tx.set(refs.rLvl, { xp: rXp.xp, level: rXp.level, dayKey: rXp.dayKey, dayXp: rXp.dayXp }, { merge: true });
    tx.update(refs.sUser, { level: sXp.level });
    tx.update(refs.rUser, { level: rXp.level, giftsReceived: FieldValue.increment(qty) });
    if (s.host.exists) {
      tx.update(refs.host, { giftsReceived: FieldValue.increment(qty), earnings: FieldValue.increment(hostShare) });
      if (agencyId) tx.update(db.doc(`agencies/${agencyId}`), { earnings: FieldValue.increment(agencyShare) });
    }
    tx.update(refs.room, { giftsTotal: FieldValue.increment(cost) });
    tx.set(db.collection(`rooms/${roomId}/messages`).doc(), {
      senderId, senderName: s.sUser.data()!.displayName ?? "", senderAvatar: s.sUser.data()!.avatarUrl ?? "",
      receiverId, receiverName: s.rUser.data()!.displayName ?? "",
      type: "gift", giftId, giftName: gift.name, giftIcon: gift.iconUrl ?? "", giftAnimation: gift.animationUrl ?? "",
      giftTier: gift.tier ?? "small", qty, text: "", createdAt: FieldValue.serverTimestamp(),
    });
    const out = { ok: true, cost, balance: sBal, giftTransactionId: giftTxRef.id };
    tx.set(idemRef, { result: out, createdAt: FieldValue.serverTimestamp() });
    return out;
  });

  if (result.giftTransactionId) {
    notify(receiverId, "gift_received", { roomId, giftId, senderId }, { title: "وصلتك هدية 🎁", body: "استلمت هدية جديدة" }).catch(() => undefined);
  }
  return result;
});

/** Async ranking counters (kept outside the money transaction on purpose). */
export const onGiftTransactionCreated = onDocumentCreated({ document: "gift_transactions/{id}", region: REGION }, async (event) => {
  const g = event.data?.data();
  if (!g) return;
  const ids = periodIds();
  const batch = db.batch();
  const bump = (type: string, id: string, name: string, avatar: string, score: number) => {
    for (const [period, pid] of Object.entries(ids)) {
      const ref = db.doc(`rankings/${type}_${period}_${pid}/entries/${id}`);
      batch.set(ref, { score: FieldValue.increment(score), name, avatar, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    }
  };
  bump("hosts", g.receiverId, g.receiverName ?? "", g.receiverAvatar ?? "", g.diamondsEarned ?? 0);
  bump("gifters", g.senderId, g.senderName ?? "", g.senderAvatar ?? "", g.totalPrice ?? 0);
  bump("rooms", g.roomId, g.roomName ?? "", "", g.totalPrice ?? 0);
  if (g.agencyId) {
    const agency = await db.doc(`agencies/${g.agencyId}`).get();
    bump("agencies", g.agencyId, agency.data()?.name ?? "", "", (g.diamondsEarned ?? 0) + (g.agencyShare ?? 0));
  }
  await batch.commit();
});
