import { useSyncExternalStore } from "react";
import { currentUser, subscribe } from "./session";

/** The signed-in user name (or null), updated when the session changes. */
export function useSessionUser(): string | null {
  return useSyncExternalStore(subscribe, currentUser, () => null);
}
