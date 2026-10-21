// Per-person access grants and store listings (contract app-updater/1 1.1.0, D-0007/D-0008).
// Grants live in R2 at `_grants/<sha256(token) hex>.json`; only the hash is stored.
// Listings live in R2 at `<appId>/listing.json` and are never touched by publish-release.ps1.

export const GRANT_PREFIX = "_grants/";
export const GRANT_TOKEN_PREFIX = "aug_";
const GRANT_TOKEN_PATTERN = /^aug_[A-Za-z0-9_-]{20,100}$/;

export interface AccessGrant {
  /** First 16 hex chars of the token hash; safe to show, used to revoke. */
  id: string;
  name: string;
  /** appIds this person may install, or ["*"] for every shareable app. */
  apps: string[];
  created: string;
  /** ISO-8601 UTC; absent = never expires. */
  expires?: string;
  revoked: boolean;
  revokedAt?: string;
  note?: string;
}

export interface StoreListing {
  appId: string;
  /** Grants only see (and can update) apps with shareable === true. */
  shareable: boolean;
  title?: string;
  summary?: string;
  updated: string;
}

export async function sha256Hex(data: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(data));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export function looksLikeGrantToken(token: string): boolean {
  return GRANT_TOKEN_PATTERN.test(token);
}

export function newGrantToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  const b64url = btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return GRANT_TOKEN_PREFIX + b64url;
}

export function grantKeyForHash(hash: string): string {
  return `${GRANT_PREFIX}${hash}.json`;
}

/** Live = not revoked and not past its expiry. */
export function isGrantLive(grant: AccessGrant, nowMs: number = Date.now()): boolean {
  if (grant.revoked) return false;
  if (grant.expires) {
    const exp = Date.parse(grant.expires);
    if (!Number.isFinite(exp) || nowMs > exp) return false;
  }
  return true;
}

export function grantCovers(grant: AccessGrant, appId: string): boolean {
  return grant.apps.includes("*") || grant.apps.includes(appId);
}
