// Small inline icons: no icon library, nothing fetched. Each is decorative; the text next to it carries the meaning.
import type { SVGProps } from "react";

type P = SVGProps<SVGSVGElement>;
const base = { width: 16, height: 16, viewBox: "0 0 16 16", fill: "currentColor", "aria-hidden": true, focusable: false } as const;

export const CriticalIcon = (p: P) => (
  <svg {...base} {...p}><path d="M8 1.2 15.2 14H.8L8 1.2Zm-.9 5v3.9h1.8V6.2H7.1Zm0 5v1.8h1.8v-1.8H7.1Z" fillRule="evenodd" /></svg>
);
export const ReviewIcon = (p: P) => (
  <svg {...base} {...p}><path d="M8 3C4.4 3 1.7 5.4.6 8c1.1 2.6 3.8 5 7.4 5s6.3-2.4 7.4-5C14.3 5.4 11.6 3 8 3Zm0 7.8A2.8 2.8 0 1 1 8 5.2a2.8 2.8 0 0 1 0 5.6Z" /></svg>
);
export const RecollectIcon = (p: P) => (
  <svg {...base} {...p}><path d="M8 1.5a6.5 6.5 0 1 0 6.1 8.7l-1.7-.6A4.7 4.7 0 1 1 8 3.3c1 0 1.9.3 2.6.9L9 5.8h5.5V.3l-1.7 1.7A6.4 6.4 0 0 0 8 1.5Z" /></svg>
);
export const NormalIcon = (p: P) => (
  <svg {...base} {...p}><path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1Zm3.3 5.2-4 4.2a.8.8 0 0 1-1.1 0L4.7 8.9l1.1-1.1.9.9 3.5-3.6 1.1 1.1Z" /></svg>
);
export const ConfirmedIcon = NormalIcon;
export const AgentIcon = (p: P) => (
  <svg {...base} {...p}><path d="M7 1h2v2h2.5A2.5 2.5 0 0 1 14 5.5V10a2.5 2.5 0 0 1-2.5 2.5H8.8L6 15v-2.5H4.5A2.5 2.5 0 0 1 2 10V5.5A2.5 2.5 0 0 1 4.5 3H7V1Zm-1.7 5.2a1 1 0 1 0 0 2 1 1 0 0 0 0-2Zm5.4 0a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z" fillRule="evenodd" /></svg>
);
export const InboxIcon = (p: P) => (
  <svg {...base} {...p}><path d="M2.5 2h11L15 8.5V13a1 1 0 0 1-1 1H2a1 1 0 0 1-1-1V8.5L2.5 2ZM3.6 4 2.6 8H5.5l.8 1.6h3.4L10.5 8h2.9l-1-4H3.6Z" fillRule="evenodd" /></svg>
);
export const PersonIcon = (p: P) => (
  <svg {...base} {...p}><path d="M8 1.5A3 3 0 1 0 8 7.5 3 3 0 0 0 8 1.5ZM2.5 14c0-3 2.5-4.8 5.5-4.8s5.5 1.8 5.5 4.8h-11Z" /></svg>
);
export const SunIcon = (p: P) => (
  <svg {...base} {...p}><path d="M8 4.2a3.8 3.8 0 1 0 0 7.6 3.8 3.8 0 0 0 0-7.6ZM7.2.5h1.6v2.2H7.2V.5Zm0 12.8h1.6v2.2H7.2v-2.2ZM.5 7.2h2.2v1.6H.5V7.2Zm12.8 0h2.2v1.6h-2.2V7.2Z" /></svg>
);
export const MoonIcon = (p: P) => (
  <svg {...base} {...p}><path d="M13.8 10.3A6 6 0 0 1 5.7 2.2a6.2 6.2 0 1 0 8.1 8.1Z" /></svg>
);
export const SimulationIcon = (p: P) => (
  <svg {...base} {...p}><path d="M5.5 1h5v1.4L9.3 3.6v3.2l3.9 6.1A1.5 1.5 0 0 1 11.9 15H4.1a1.5 1.5 0 0 1-1.3-2.1l3.9-6.1V3.6L5.5 2.4V1Zm.6 8.3-1.5 2.4h6.8L9.9 9.3H6.1Z" fillRule="evenodd" /></svg>
);
export const HeldIcon = (p: P) => (
  <svg {...base} {...p}><path d="M8 1 2 3.4v4.2c0 3.4 2.4 6 6 7.4 3.6-1.4 6-4 6-7.4V3.4L8 1Zm-.9 4.3h1.8v3.6H7.1V5.3Zm0 4.7h1.8v1.8H7.1V10Z" fillRule="evenodd" /></svg>
);
export const ToolIcon = (p: P) => (
  <svg {...base} {...p}><path d="M11.6 1.2a3.6 3.6 0 0 0-3.3 4.9L1.4 13a1.3 1.3 0 0 0 1.8 1.8l6.9-6.9a3.6 3.6 0 0 0 4.9-3.3c0-.4-.1-.8-.2-1.1L12.4 6.2 10 5.8l-.4-2.4L11.7 1.3c-.03 0-.07-.1-.1-.1Z" /></svg>
);
