import { useEffect, useState } from "react";
import { getJson } from "../api/client";
import { basicHeader, signIn } from "../api/session";
import type { UiConfig } from "./types";

/** Signs a person in by asking the workflow layer who they are. The platform answers with a plain refusal when the credentials are not right. */
export function SignIn({ onDone }: { onDone?: () => void }) {
  const [user, setUser] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [config, setConfig] = useState<UiConfig | null>(null);

  useEffect(() => {
    let live = true;
    getJson<UiConfig>("/ui-config.json").then((c) => live && setConfig(c)).catch(() => undefined);
    return () => {
      live = false;
    };
  }, []);

  const attempt = async (name: string, secret: string) => {
    setBusy(true);
    setError("");
    // The credentials are checked first and only kept when the product knows them. A refusal is confirmed once more
    // before it is shown: the platform's workflow layer was seen to answer a correct sign-in with a 404 once in a while
    // (docs/probes.md, feature 5), and a person must not be told their password is wrong because of that.
    let known = false;
    for (let attemptNo = 0; attemptNo < 2 && !known; attemptNo++) {
      try {
        await getJson<{ username: string }>("/workflow/rest/user-info", { authorization: basicHeader(name, secret) });
        known = true;
      } catch {
        if (attemptNo === 0) await new Promise((resolve) => setTimeout(resolve, 400));
      }
    }
    if (!known) {
      setError("Sign-in refused: the user name or the password is not right.");
      setBusy(false);
      return;
    }
    signIn({ user: name, password: secret });
    onDone?.();
  };

  return (
    <form className="signin" onSubmit={(e) => { e.preventDefault(); void attempt(user.trim(), password); }}>
      <h3>Sign in to open the read-back</h3>
      <label htmlFor="signin-user">User name</label>
      <input id="signin-user" value={user} onChange={(e) => setUser(e.target.value)} autoComplete="username" required />
      <label htmlFor="signin-password">Password</label>
      <input id="signin-password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" required />
      <button type="submit" disabled={busy}>{busy ? "Signing in" : "Sign in"}</button>
      {error && <p className="error" role="alert">{error}</p>}
      {config?.publishDemoAccounts && (
        <div className="demo-accounts">
          <p>Demo accounts (published for this demo):</p>
          <ul>
            {config.accounts.map((a) => (
              <li key={a.user}>
                <span className="num">{a.user}</span> {a.canConfirm ? "can confirm read-backs" : "cannot confirm read-backs"}
                <button type="button" onClick={() => void attempt(a.user, a.password)} disabled={busy}>Use</button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </form>
  );
}
