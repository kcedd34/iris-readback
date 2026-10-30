// The signed-in person's credentials live in this module's memory and nowhere else: not in storage, not in a
// cookie, not in a URL, not in a log. Reloading the page signs the person out, by design.
export interface Credentials {
  user: string;
  password: string;
}

let current: Credentials | null = null;
const listeners = new Set<() => void>();

export function signIn(credentials: Credentials): void {
  current = { user: credentials.user, password: credentials.password };
  listeners.forEach((fn) => fn());
}

export function signOut(): void {
  current = null;
  listeners.forEach((fn) => fn());
}

export function currentUser(): string | null {
  return current ? current.user : null;
}

/** A Basic Authorization header value for a user name and password. */
export function basicHeader(user: string, password: string): string {
  const bytes = new TextEncoder().encode(`${user}:${password}`);
  let binary = "";
  bytes.forEach((b) => (binary += String.fromCharCode(b)));
  return `Basic ${btoa(binary)}`;
}

/** The Authorization header value for the person's own paths, or null when nobody is signed in. */
export function authorizationHeader(): string | null {
  return current ? basicHeader(current.user, current.password) : null;
}

export function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}
