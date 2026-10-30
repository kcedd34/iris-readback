import { useState } from "react";
import { loadTheme, saveTheme, type ThemeChoice } from "../theme/theme";

const CHOICES: Array<{ value: ThemeChoice; label: string }> = [
  { value: "system", label: "System" },
  { value: "light", label: "Light" },
  { value: "dark", label: "Dark" },
];

export function ThemeSwitch() {
  const [choice, setChoice] = useState<ThemeChoice>(() => loadTheme());
  return (
    <div className="theme" role="radiogroup" aria-label="Colour theme">
      {CHOICES.map((c) => (
        <button key={c.value} type="button" role="radio" aria-checked={choice === c.value} className={choice === c.value ? "on" : ""} onClick={() => { setChoice(c.value); saveTheme(c.value); }}>
          {c.label}
        </button>
      ))}
    </div>
  );
}
