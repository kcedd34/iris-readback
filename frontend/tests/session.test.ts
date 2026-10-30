import { afterEach, describe, expect, it, vi } from "vitest";
import { authorizationHeader, currentUser, signIn, signOut } from "../src/api/session";
import { ApiError, getJson, postJson } from "../src/api/client";

afterEach(() => {
  signOut();
  vi.restoreAllMocks();
});

describe("session", () => {
  it("keeps the credentials in memory only", () => {
    const local = vi.spyOn(Storage.prototype, "setItem");
    signIn({ user: "communicator1", password: "pw-for-test" });
    expect(currentUser()).toBe("communicator1");
    expect(authorizationHeader()).toBe(`Basic ${btoa("communicator1:pw-for-test")}`);
    expect(local).not.toHaveBeenCalled();
    expect(window.localStorage.length).toBe(0);
    expect(window.sessionStorage.length).toBe(0);
    expect(document.cookie).toBe("");
  });

  it("forgets the credentials on sign-out", () => {
    signIn({ user: "observer", password: "x" });
    signOut();
    expect(currentUser()).toBeNull();
    expect(authorizationHeader()).toBeNull();
  });
});

describe("client", () => {
  it("sends the person's credentials only when asked", async () => {
    const fetchMock = vi.fn(async () => new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    signIn({ user: "communicator1", password: "pw" });
    await getJson("/readback/api/flow");
    await getJson("/readback/api/taskview/X", { auth: true });
    const calls = fetchMock.mock.calls as unknown as Array<[string, RequestInit]>;
    expect((calls[0][1].headers as Record<string, string>).Authorization).toBeUndefined();
    expect((calls[1][1].headers as Record<string, string>).Authorization).toMatch(/^Basic /);
    expect(calls[0][1].credentials).toBe("omit");
  });

  it("shows only the error text of the product, never a body or a header", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ error: "unknown scenario", stack: "secret" }), { status: 400 })));
    await expect(postJson("/readback/api/flow/submit", { scenarioId: "x" })).rejects.toMatchObject({ kind: "http", status: 400, message: "unknown scenario" });
  });

  it("uses a fixed sentence when the body is not the product's error", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("<html>Apache</html>", { status: 500 })));
    await expect(getJson("/x")).rejects.toMatchObject({ message: "The product could not complete the request." });
  });

  it("reports a lost connection", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("network"); }));
    const error: unknown = await getJson("/x").catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect((error as ApiError).kind).toBe("connection");
  });
});
