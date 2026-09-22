import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { google } from "googleapis";
import * as crypto from "crypto";
import { db, FieldValue, Timestamp, REGION, requireAuth, rateLimit, str, int, oneOf, applyXp, todayKey } from "./lib/common";
import { notify } from "./lib/notify";

// ====================================================================
// COIN PURCHASES (real money) - server-side receipt verification.
// ====================================================================
interface Package { productId: string; coins: number; bonus?: number; priceUsd: number }

async function loadPackage(productId: string): Promise<Package> {
  const snap = await db.doc("settings/coin_packages").get();
  const pkg = ((snap.data()?.packages ?? []) as Package[]).find((p) => p.productId === productId);
  if (!pkg) throw new HttpsError("not-found", "الباقة غير موجودة");
  return pkg;
}

/**
 * Google Play: uses the Cloud Functions runtime service account.
 * SETUP: Play Console > Users & permissions > invite the functions service account
 * (PROJECT_ID@appspot.gserviceaccount.com) with "View financial data" + "Manage orders".
 * Env: ANDROID_PACKAGE_NAME in functions/.env.
 */
async function verifyGooglePlay(productId: string, purchaseToken: string): Promise<string> {
  const packageName = process.env.ANDROID_PACKAGE_NAME;
  if (!packageName) throw new HttpsError("failed-precondition", "ANDROID_PACKAGE_NAME غير مضبوط");
  const client = await google.auth.getClient({ scopes: ["https://www.googleapis.com/auth/androidpublisher"] });
  const publisher = google.androidpublisher({ version: "v3", auth: client as never });
  const res = await publisher.purchases.products.get({ packageName, productId, token: purchaseToken });
  if (res.data.purchaseState !== 0) throw new HttpsError("failed-precondition", "عملية الشراء غير مكتملة");
  const orderId = res.data.orderId ?? purchaseToken.slice(0, 40);
  if (res.data.acknowledgementState !== 1) {
    await publisher.purchases.products.acknowledge({ packageName, productId, token: purchaseToken });
  }
  return orderId;
}

/**
 * Apple App Store: NOT implemented here because it needs YOUR credentials.
 * SETUP: App Store Connect > Users and Access > Integrations > In-App Purchase key.
 * Store the key as a Functions secret (APPLE_IAP_KEY, APPLE_KEY_ID, APPLE_ISSUER_ID) and call the
 * App Store Server API (GET /inApps/v1/transactions/{transactionId}) with a signed JWT,
 * or use the official `@apple/app-store-server-library` package. Return the transactionId.
 */
async function verifyAppStore(_productId: string, _receipt: string): Promise<string> {
  throw new HttpsError("unimplemented", "تحقق App Store غير مفعّل بعد. راجع التعليمات في functions/src/economy.ts");
}

export const verifyPurchase = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  await rateLimit(uid, "verifyPurchase", 20, 3600);
  const platform = oneOf(req.data?.platform, "platform", ["android", "ios"] as const);
  const productId = str(req.data?.productId, "productId", 100);
  const proof = str(req.data?.proof, "proof", 20000); // purchaseToken (android) or receipt/transactionId (ios)
  const pkg = await loadPackage(productId);

  const orderId = platform === "android" ? await verifyGooglePlay(productId, proof) : await verifyAppStore(productId, proof);
  const safeId = crypto.createHash("sha256").update(`${platform}:${orderId}`).digest("hex");
  const purchaseRef = db.doc(`purchases/${safeId}`);
  const coins = pkg.coins + (pkg.bonus ?? 0);

  return await db.runTransaction(async (tx) => {
    const [p, wallet] = await Promise.all([tx.get(purchaseRef), tx.get(db.doc(`wallets/${uid}`))]);
    if (p.exists) return { ok: true, duplicate: true, coins: 0, balance: wallet.data()?.coins ?? 0 };
    const balance = ((wallet.data()?.coins ?? 0) as number) + coins;
    tx.update(wallet.ref, { coins: balance, updatedAt: FieldValue.serverTimestamp() });
    tx.set(purchaseRef, { uid, platform, productId, orderId, coins, priceUsd: pkg.priceUsd, createdAt: FieldValue.serverTimestamp() });
    tx.set(db.collection(`wallets/${uid}/transactions`).doc(), {
      type: "purchase", currency: "coins", amount: coins, balanceAfter: balance, refId: safeId, createdAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, duplicate: false, coins, balance };
  });
});

// ====================================================================
// VIP
// ====================================================================
export const purchaseVip = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  await rateLimit(uid, "purchaseVip", 10, 3600);
  const level = int(req.data?.level, "level", 1, 10);
  const result = await db.runTransaction(async (tx) => {
    const [lvl, wallet, vip] = await Promise.all([
      tx.get(db.doc(`vip_levels/${level}`)), tx.get(db.doc(`wallets/${uid}`)), tx.get(db.doc(`user_vip/${uid}`)),
    ]);
    if (!lvl.exists || lvl.data()!.enabled === false) throw new HttpsError("not-found", "مستوى VIP غير متاح");
    const price = lvl.data()!.price as number;
    const days = (lvl.data()!.durationDays ?? 30) as number;
    const coins = (wallet.data()?.coins ?? 0) as number;
    if (coins < price) throw new HttpsError("failed-precondition", "رصيدك غير كافٍ");
    const current = vip.data();
    const base = current?.level === level && current.expiresAt.toMillis() > Date.now() ? current.expiresAt.toMillis() : Date.now();
    const expiresAt = Timestamp.fromMillis(base + days * 86400000);
    const bal = coins - price;
    tx.update(wallet.ref, { coins: bal, updatedAt: FieldValue.serverTimestamp() });
    tx.set(vip.ref, { level, expiresAt, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.update(db.doc(`users/${uid}`), { vipLevel: level });
    tx.set(db.collection(`wallets/${uid}/transactions`).doc(), {
      type: "vip", currency: "coins", amount: -price, balanceAfter: bal, refId: `vip_${level}`, createdAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, balance: bal, expiresAt: expiresAt.toMillis() };
  });
  notify(uid, "vip", { level }, { title: "VIP", body: `تم تفعيل VIP ${level}` }).catch(() => undefined);
  return result;
});

export const expireVip = onSchedule({ schedule: "every 24 hours", region: REGION }, async () => {
  const expired = await db.collection("user_vip").where("expiresAt", "<", Timestamp.now()).where("level", ">", 0).limit(400).get();
  const batch = db.batch();
  expired.docs.forEach((d) => {
    batch.update(d.ref, { level: 0 });
    batch.update(db.doc(`users/${d.id}`), { vipLevel: 0 });
  });
  await batch.commit();
});

// ====================================================================
// GAMES - the RNG lives here. The client only sends a choice and a bet.
// Winnings are COINS only and can never be converted to diamonds/cash.
// ====================================================================
const GAME_IDS = ["dice", "wheel", "rps", "guess"] as const;
const WHEEL = [{ m: 0, w: 30 }, { m: 0.5, w: 25 }, { m: 1, w: 20 }, { m: 1.5, w: 12 }, { m: 2, w: 10 }, { m: 5, w: 3 }];

function playRound(game: typeof GAME_IDS[number], choice: string): { multiplier: number; detail: Record<string, unknown> } {
  switch (game) {
    case "dice": {
      const c = oneOf(choice, "choice", ["high", "low"] as const);
      const roll = crypto.randomInt(1, 7);
      const win = (c === "high") === (roll >= 4);
      return { multiplier: win ? 1.9 : 0, detail: { roll } };
    }
    case "wheel": {
      const total = WHEEL.reduce((a, b) => a + b.w, 0);
      let r = crypto.randomInt(0, total);
      const idx = WHEEL.findIndex((s) => (r -= s.w) < 0);
      return { multiplier: WHEEL[idx].m, detail: { segment: idx } };
    }
    case "rps": {
      const opts = ["rock", "paper", "scissors"] as const;
      const c = oneOf(choice, "choice", opts);
      const house = opts[crypto.randomInt(0, 3)];
      const beats: Record<string, string> = { rock: "scissors", paper: "rock", scissors: "paper" };
      const m = c === house ? 1 : beats[c] === house ? 1.9 : 0;
      return { multiplier: m, detail: { house } };
    }
    case "guess": {
      const n = Number(choice);
      if (!Number.isInteger(n) || n < 1 || n > 10) throw new HttpsError("invalid-argument", "اختر رقماً من 1 إلى 10");
      const secret = crypto.randomInt(1, 11);
      return { multiplier: n === secret ? 8 : 0, detail: { secret } };
    }
  }
}

export const playGame = onCall({ region: REGION }, async (req) => {
  const uid = requireAuth(req);
  await rateLimit(uid, "playGame", 30, 60);
  const gameId = oneOf(req.data?.gameId, "gameId", GAME_IDS);
  const choice = str(String(req.data?.choice ?? ""), "choice", 20);
  const bet = int(req.data?.bet, "bet", 1, 1_000_000);
  const key = str(req.data?.idempotencyKey, "idempotencyKey", 64, 8);
  const idemRef = db.doc(`idempotency/game_${uid}_${key}`);

  return await db.runTransaction(async (tx) => {
    const lvlRef = db.doc(`user_levels/${uid}`);
    const [idem, gameCfg, wallet, econ, lvl] = await Promise.all([
      tx.get(idemRef), tx.get(db.doc(`games/${gameId}`)), tx.get(db.doc(`wallets/${uid}`)),
      tx.get(db.doc("settings/economy")), tx.get(lvlRef),
    ]);
    if (idem.exists) return idem.data()!.result;
    const cfg = gameCfg.data() ?? {};
    if (cfg.enabled === false) throw new HttpsError("failed-precondition", "اللعبة متوقفة حالياً");
    const minBet = cfg.minBet ?? 10, maxBet = cfg.maxBet ?? 10000;
    if (bet < minBet || bet > maxBet) throw new HttpsError("invalid-argument", `الرهان بين ${minBet} و ${maxBet}`);
    const w = wallet.data() ?? {};
    if ((w.coins ?? 0) < bet) throw new HttpsError("failed-precondition", "رصيدك غير كافٍ");

    const day = todayKey();
    const lossToday = w.gameLossDay === day ? (w.gameLossToday ?? 0) : 0;
    const dailyLimit = econ.data()?.dailyGameLossLimit ?? 50000;
    if (lossToday + bet > dailyLimit) throw new HttpsError("resource-exhausted", "وصلت للحد اليومي للألعاب");

    const { multiplier, detail } = playRound(gameId, choice);
    const payout = Math.floor(bet * multiplier);
    const net = payout - bet;
    const balance = (w.coins as number) + net;
    tx.update(wallet.ref, {
      coins: balance, updatedAt: FieldValue.serverTimestamp(),
      gameLossDay: day, gameLossToday: lossToday + Math.max(0, -net),
    });
    const sessionRef = db.collection("game_sessions").doc();
    tx.set(sessionRef, { userId: uid, gameId, bet, choice, multiplier, payout, detail, createdAt: FieldValue.serverTimestamp() });
    tx.set(db.collection(`wallets/${uid}/transactions`).doc(), {
      type: "game", currency: "coins", amount: net, balanceAfter: balance, refId: sessionRef.id, createdAt: FieldValue.serverTimestamp(),
    });
    const xp = applyXp(lvl.data(), 2);
    tx.set(lvlRef, { xp: xp.xp, level: xp.level, dayKey: xp.dayKey, dayXp: xp.dayXp }, { merge: true });
    const out = { ok: true, won: payout > bet, draw: payout === bet, payout, multiplier, balance, detail };
    tx.set(idemRef, { result: out, createdAt: FieldValue.serverTimestamp() });
    return out;
  });
});
