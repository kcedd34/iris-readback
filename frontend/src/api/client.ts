import { authorizationHeader } from "./session";

/** A failure of a request, in words a person can read. Never carries a header, a body or a stack. */
export class ApiError extends Error {
  readonly kind: "connection" | "http";
  readonly status: number;

  constructor(kind: "connection" | "http", message: string, status = 0) {
    super(message);
    this.kind = kind;
    this.status = status;
  }
}

interface Options {
  /** Send the signed-in person's own credentials. Only the person's own paths use this; the proxy supplies the read-only account for the rest. */
  auth?: boolean;
  /** An explicit Authorization value (used to check a sign-in before the session is set). Wins over auth. */
  authorization?: string;
  signal?: AbortSignal;
}

const CONNECTION_LOST = "Connection to the product lost.";
const GENERIC = "The product could not complete the request.";

async function errorText(response: Response): Promise<string> {
  try {
    const body: unknown = await response.json();
    if (body && typeof body === "object" && "error" in body && typeof (body as { error: unknown }).error === "string") {
      return (body as { error: string }).error;
    }
  } catch {
    /* not JSON: fall through */
  }
  return GENERIC;
}

async function request<T>(method: string, path: string, body: unknown, options: Options): Promise<T> {
  const headers: Record<string, string> = { Accept: "application/json" };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (options.authorization) headers.Authorization = options.authorization;
  else if (options.auth) {
    const header = authorizationHeader();
    if (header) headers.Authorization = header;
  }
  let response: Response;
  try {
    response = await fetch(path, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      credentials: "omit",
      signal: options.signal,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") throw error;
    throw new ApiError("connection", CONNECTION_LOST);
  }
  if (!response.ok) throw new ApiError("http", await errorText(response), response.status);
  const text = await response.text();
  return (text ? JSON.parse(text) : undefined) as T;
}

export function getJson<T>(path: string, options: Options = {}): Promise<T> {
  return request<T>("GET", path, undefined, options);
}

export function postJson<T>(path: string, body: unknown, options: Options = {}): Promise<T> {
  return request<T>("POST", path, body, options);
}
