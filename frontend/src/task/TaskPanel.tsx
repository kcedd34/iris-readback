import { useEffect, useRef } from "react";
import { signOut } from "../api/session";
import { useSessionUser } from "../api/useSession";
import { SignIn } from "./SignIn";
import { TaskScreen } from "./TaskScreen";

/** The side panel of one read-back task. A native dialog: focus is kept inside, Escape closes it, the opener gets the focus back. */
export default function TaskPanel({ decisionId, onClose }: { decisionId: number; onClose: () => void }) {
  const user = useSessionUser();
  const ref = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = ref.current;
    if (dialog && !dialog.open) dialog.showModal();
    return () => {
      if (dialog?.open) dialog.close();
    };
  }, []);

  return (
    <dialog ref={ref} className="drawer" aria-labelledby="task-title" onClose={onClose}>
      <header className="drawer-head">
        <h2 id="task-title">Read-back task</h2>
        <button type="button" onClick={onClose}>Close</button>
      </header>
      {user ? (
        <>
          <p className="drawer-user">Signed in as <strong className="num">{user}</strong> <button type="button" onClick={() => signOut()}>Sign out</button></p>
          <TaskScreen decisionId={decisionId} />
        </>
      ) : (
        <SignIn />
      )}
    </dialog>
  );
}
