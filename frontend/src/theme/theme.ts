export type ThemeChoice = "system" | "dark" | "light";

const KEY = "readback-theme";

function read(): ThemeChoice {
  try {
    const value = window.localStorage.getItem(KEY);
    return value === "dark" || value === "light" ? value : "system";
  } catch {
    return "system";
  }
}

/** Applies a choice to the document. "system" removes the override so the system preference decides. */
export function applyTheme(choice: ThemeChoice): void {
  const root = document.documentElement;
  if (choice === "system") root.removeAttribute("data-theme");
  else root.setAttribute("data-theme", choice);
}

export function loadTheme(): ThemeChoice {
  const choice = read();
  applyTheme(choice);
  return choice;
}

/** Stores a choice when storage is available; the page works the same without it. */
export function saveTheme(choice: ThemeChoice): void {
  applyTheme(choice);
  try {
    if (choice === "system") window.localStorage.removeItem(KEY);
    else window.localStorage.setItem(KEY, choice);
  } catch {
    /* storage can be blocked or full: the choice still applies for this page view */
  }
}
