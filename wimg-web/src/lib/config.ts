/**
 * Centralized configuration — all URLs, keys, and constants in one place.
 */

// --- Sync API ---
export const SYNC_API_URL = (() => {
  if (typeof window === "undefined") return "https://wimg-sync.komiljonmaksudov.com";
  const host = window.location.hostname;
  // Local dev: localhost or private network IPs (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
  if (
    host === "localhost" ||
    host === "127.0.0.1" ||
    host.startsWith("192.168.") ||
    host.startsWith("10.") ||
    /^172\.(1[6-9]|2\d|3[01])\./.test(host)
  ) {
    return `http://${host}:8787`;
  }
  return "https://wimg-sync.komiljonmaksudov.com";
})();

// --- GitHub ---
export const RELEASES_URL = "https://github.com/milimyname/wimg/releases";

// --- LocalStorage keys ---
export const LS_SYNC_KEY = "wimg_sync_key";
export const LS_SYNC_LAST_TS = "wimg_sync_last_ts";
export const LS_LAST_VERSION = "wimg-last-version";
export const LS_ONBOARDING_COMPLETED = "wimg_onboarding_completed";
export const LS_DEMO_LOADED = "wimg_demo_loaded";
export const LS_LAST_SNAPSHOT_MONTH = "wimg_last_snapshot_month";
export const LS_LOCALE = "wimg_locale";
