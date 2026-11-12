/**
 * Sync service — orchestrates push/pull with the Cloudflare Worker API.
 * Now also manages real-time WebSocket connection for live sync.
 *
 * Dev:  http://localhost:8787 (wrangler dev)
 * Prod: https://wimg-sync.komiljonmaksudov.com
 */

import {
  getChanges,
  applyChanges,
  opfsSave,
  setOnMutate,
  deriveEncryptionKey,
  encryptField,
  decryptRows,
  type SyncRow,
} from "./wasm";
import { devtoolsEnabled } from "./devtools.svelte";
import { accountStore } from "./account.svelte";
import { data } from "./data.svelte";
import { syncWS } from "./sync-ws.svelte";
import { SYNC_API_URL, LS_SYNC_KEY, LS_SYNC_LAST_TS } from "./config";

// Cached encryption key — derived once from sync key
let encryptionKey: Uint8Array | null = null;

function getEncryptionKey(syncKey: string): Uint8Array {
  if (!encryptionKey) {
    encryptionKey = deriveEncryptionKey(syncKey);
  }
  return encryptionKey;
}

function encryptRows(rows: SyncRow[], key: Uint8Array): SyncRow[] {
  return rows.map((row) => ({
    ...row,
    data: encryptField(JSON.stringify(row.data), key) as unknown as Record<string, unknown>,
  }));
}

export function getSyncKey(): string | null {
  return localStorage.getItem(LS_SYNC_KEY);
}

// Sync keys are UUID v4. Both `crypto.randomUUID()` and the local fallback
// generator emit exactly this shape — accepting anything else just creates
// an unreachable Durable Object on the server with the user's typo.
const UUID_V4_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function isValidSyncKey(key: string): boolean {
  return UUID_V4_RE.test(key.trim());
}

export function setSyncKey(key: string): void {
  localStorage.setItem(LS_SYNC_KEY, key);
  // Clear stale timestamp so next pull fetches ALL data (since=0)
  localStorage.removeItem(LS_SYNC_LAST_TS);
}

export function clearSyncKey(): void {
  localStorage.removeItem(LS_SYNC_KEY);
  localStorage.removeItem(LS_SYNC_LAST_TS);
  encryptionKey = null;
  disconnectSync();
}

export function getLastSyncTimestamp(): number {
  return Number(localStorage.getItem(LS_SYNC_LAST_TS) || "0");
}

function setLastSyncTimestamp(ts: number): void {
  localStorage.setItem(LS_SYNC_LAST_TS, String(ts));
}

export function isSyncEnabled(): boolean {
  return !!getSyncKey();
}

export async function syncPush(syncKey: string): Promise<number> {
  const start = devtoolsEnabled ? performance.now() : 0;
  const lastSync = getLastSyncTimestamp();
  const changes: SyncRow[] = getChanges(lastSync);
  console.log(`[wimg-sync] Push: ${changes.length} changes since ${lastSync}`);
  if (changes.length === 0) return 0;

  // Encrypt data fields before pushing
  const key = getEncryptionKey(syncKey);
  const encrypted = encryptRows(changes, key);

  // Suppress echo: the DO will broadcast our push back to us via WS
  syncWS.suppressEcho();

  const res = await fetch(`${SYNC_API_URL}/sync/${syncKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ rows: encrypted }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Sync push failed: ${res.status} ${body}`);
  }

  const result = (await res.json()) as { merged: number };
  console.log(`[wimg-sync] Push result: ${result.merged} merged`);

  // DO's HTTP push handler already broadcasts to all WS clients
  // No need to also push via WS — that would cause duplicate broadcasts

  setLastSyncTimestamp(Date.now());

  if (devtoolsEnabled) {
    const duration = performance.now() - start;
    import("./devtools.svelte").then((m) => {
      m.devtoolsStore.logSyncEvent("push", `${changes.length} rows, ${duration.toFixed(0)}ms`);
      m.devtoolsStore.logSyncDiff(
        "push",
        changes.map((r) => ({
          table: r.table,
          id: r.id,
          fields: typeof r.data === "object" && r.data ? Object.keys(r.data) : [],
        })),
      );
    });
  }

  return result.merged;
}

export async function syncPull(syncKey: string): Promise<number> {
  const start = devtoolsEnabled ? performance.now() : 0;
  const lastSync = getLastSyncTimestamp();
  console.log(`[wimg-sync] Pull: since=${lastSync}`);

  const res = await fetch(`${SYNC_API_URL}/sync/${syncKey}?since=${lastSync}`);
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Sync pull failed: ${res.status} ${body}`);
  }

  const { rows } = (await res.json()) as { rows: SyncRow[] };
  console.log(`[wimg-sync] Pull: received ${rows.length} rows from server`);
  if (!rows.length) return 0;

  // Decrypt data fields (handles both encrypted strings and plaintext objects)
  const key = getEncryptionKey(syncKey);
  const decrypted = decryptRows(rows, key);

  const applied = applyChanges(decrypted);
  console.log(`[wimg-sync] Pull: applied ${applied} of ${rows.length} rows`);
  await opfsSave();
  setLastSyncTimestamp(Date.now());
  accountStore.reload();
  data.bump();

  if (devtoolsEnabled) {
    const duration = performance.now() - start;
    import("./devtools.svelte").then((m) => {
      m.devtoolsStore.logSyncEvent("pull", `${rows.length} rows, ${duration.toFixed(0)}ms`);
      m.devtoolsStore.logSyncDiff(
        "pull",
        decrypted.map((r) => ({
          table: r.table,
          id: r.id,
          fields:
            typeof r.data === "object" && r.data
              ? Object.keys(r.data as Record<string, unknown>)
              : [],
        })),
      );
    });
  }

  return applied;
}

export async function syncFull(syncKey: string): Promise<{ pushed: number; pulled: number }> {
  const pushed = await syncPush(syncKey);
  const pulled = await syncPull(syncKey);
  setLastSyncTimestamp(Date.now());
  return { pushed, pulled };
}

/** Connect WebSocket for real-time sync + register onMutate callback */
export function connectSync(): void {
  const key = getSyncKey();
  if (!key) return;

  syncWS.connect(key);

  // Catch-up sync on every (re)connect — push local changes + pull remote changes
  syncWS.setOnReconnect(() => {
    const syncKey = getSyncKey();
    if (syncKey) {
      syncPush(syncKey)
        .then(() => syncPull(syncKey))
        .catch((err) => {
          console.error("[wimg-sync] Catch-up sync failed:", err);
        });
    }
  });

  // Auto-push on every local mutation
  setOnMutate(() => {
    const syncKey = getSyncKey();
    if (syncKey) {
      syncPush(syncKey).catch((err) => {
        console.error("[wimg-sync] Auto-push failed:", err);
      });
    }
  });
}

/** Disconnect WebSocket and remove onMutate callback */
export function disconnectSync(): void {
  syncWS.disconnect();
  setOnMutate(null);
}
