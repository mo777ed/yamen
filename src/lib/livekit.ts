import { defineSecret, defineString } from "firebase-functions/params";
import { AccessToken, RoomServiceClient, WebhookReceiver } from "livekit-server-sdk";

export const LIVEKIT_API_KEY = defineSecret("LIVEKIT_API_KEY");
export const LIVEKIT_API_SECRET = defineSecret("LIVEKIT_API_SECRET");
export const LIVEKIT_URL = defineString("LIVEKIT_URL");
export const livekitSecrets = [LIVEKIT_API_KEY, LIVEKIT_API_SECRET];

export async function mintToken(opts: {
  roomId: string; uid: string; name: string; canPublish: boolean;
}): Promise<string> {
  const at = new AccessToken(LIVEKIT_API_KEY.value(), LIVEKIT_API_SECRET.value(), {
    identity: opts.uid, name: opts.name, ttl: "6h",
  });
  at.addGrant({
    roomJoin: true, room: opts.roomId,
    canSubscribe: true, canPublish: opts.canPublish, canPublishData: true,
  });
  return await at.toJwt();
}

function httpUrl(): string { return LIVEKIT_URL.value().replace(/^wss:/, "https:").replace(/^ws:/, "http:"); }

export function roomService(): RoomServiceClient {
  return new RoomServiceClient(httpUrl(), LIVEKIT_API_KEY.value(), LIVEKIT_API_SECRET.value());
}

/** Change whether a participant may publish audio. Ignores "participant not found". */
export async function setCanPublish(roomId: string, uid: string, canPublish: boolean): Promise<void> {
  try {
    await roomService().updateParticipant(roomId, uid, undefined, {
      canPublish, canSubscribe: true, canPublishData: true,
    });
  } catch (_) { /* participant may not be connected yet; token grants apply on next join */ }
}

export async function removeParticipant(roomId: string, uid: string): Promise<void> {
  try { await roomService().removeParticipant(roomId, uid); } catch (_) { /* already gone */ }
}

export function webhookReceiver(): WebhookReceiver {
  return new WebhookReceiver(LIVEKIT_API_KEY.value(), LIVEKIT_API_SECRET.value());
}
