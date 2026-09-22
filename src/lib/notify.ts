import * as admin from "firebase-admin";
import { db, FieldValue } from "./common";

export type NotifType =
  | "friend_request" | "friend_accepted" | "gift_received" | "room_invitation"
  | "message" | "mention" | "vip" | "system" | "follow";

export async function notify(
  uid: string, type: NotifType, payload: Record<string, unknown>,
  push?: { title: string; body: string },
): Promise<void> {
  await db.collection(`notifications/${uid}/items`).add({
    type, payload, read: false, createdAt: FieldValue.serverTimestamp(),
  });
  if (!push) return;
  const devices = await db.collection(`users/${uid}/devices`).get();
  const tokens = devices.docs.map((d) => d.id);
  if (tokens.length === 0) return;
  const res = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title: push.title, body: push.body },
    data: Object.fromEntries(Object.entries({ type, ...payload }).map(([k, v]) => [k, String(v)])),
  });
  // Clean up dead tokens.
  const dead: string[] = [];
  res.responses.forEach((r, i) => {
    const code = r.error?.code;
    if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") {
      dead.push(tokens[i]);
    }
  });
  await Promise.all(dead.map((t) => db.doc(`users/${uid}/devices/${t}`).delete()));
}
