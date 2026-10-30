import { createContext, useContext } from "react";

/** The panel's clock, shared so a waiting case can show its wait without every component keeping a timer. */
export const NowContext = createContext<number>(Date.now());
export const useClock = () => useContext(NowContext);
