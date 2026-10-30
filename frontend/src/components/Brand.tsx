/** The product's mark: a read-back loop drawn as an ECG tick inside a ring. Decorative; the name beside it is the label. */
export function Brand() {
  return (
    <div className="brand">
      <svg className="brand-mark" width="34" height="34" viewBox="0 0 34 34" aria-hidden="true" focusable="false">
        <circle cx="17" cy="17" r="15" fill="none" stroke="currentColor" strokeWidth="2" />
        <path d="M5 18h6l2.5-6 4 11 2.5-5H29" fill="none" stroke="var(--sev-critical)" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      <div>
        <span className="brand-name">Readback</span>
        <span className="brand-sub">Critical-result read-back</span>
      </div>
    </div>
  );
}
