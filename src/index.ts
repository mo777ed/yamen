import { setGlobalOptions } from "firebase-functions/v2";
import { REGION } from "./lib/common";

setGlobalOptions({ region: REGION, maxInstances: 50 });

export * from "./auth";
export * from "./rooms";
export * from "./gifts";
export * from "./economy";
export * from "./social";
export * from "./admin";
