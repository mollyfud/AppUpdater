import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { STORE_PALETTE, type StorePalette } from "../src/store-page.ts";

function luminance(hex: string): number {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

const PAIRS: [keyof StorePalette, keyof StorePalette][] = [
  ["text", "bg"],
  ["text", "surface"],
  ["muted", "bg"],
  ["muted", "surface"],
  ["accentText", "accent"],
  ["error", "surface"],
  ["error", "bg"],
];

describe("Store page palette contrast (4.5:1)", () => {
  for (const theme of ["light", "dark"] as const) {
    for (const [fg, bg] of PAIRS) {
      it(`${theme}: ${fg} on ${bg}`, () => {
        const p = STORE_PALETTE[theme];
        const ratio = contrast(p[fg], p[bg]);
        assert.ok(ratio >= 4.5, `${theme} ${fg} ${p[fg]} on ${bg} ${p[bg]} is ${ratio.toFixed(2)}:1`);
      });
    }
  }
});
