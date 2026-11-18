#!/usr/bin/env bun
// Uploads the signed bundle to a Google Play track, with the "What's new" text.
//
//   bun scripts/play-upload.ts <app-release.aab> [track]      (track: alpha)
//   bun scripts/play-upload.ts --check     sign in, list the tracks, change nothing
//
// Env: PLAY_SERVICE_ACCOUNT_JSON — the service account key (JSON text). The
// account has no Google Cloud roles; Play Console gives it "Release apps to
// testing tracks" for wimg only, so it can't touch production or the listing.
//
// Release notes: docs/play-whats-new/<lang>.txt. The first line is "# <version>".
// When it names the version being uploaded, the release goes to review
// ("completed"). Otherwise it is uploaded as a draft, so testers never get an
// update with last time's notes; finish it in Play Console.
//
// Plain Play Developer API calls (edits.insert → bundles.upload →
// tracks.update → edits.commit); no third-party Action, which would see the key.

import { createSign } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";

const PKG = "com.wimg.app";
const API = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PKG}`;
const UPLOAD = `https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${PKG}`;

const check = process.argv.includes("--check");
const [bundlePath, track = "alpha"] = process.argv.slice(2).filter((a) => a !== "--check");
if (!bundlePath && !check) throw new Error("usage: bun scripts/play-upload.ts <app-release.aab> [track]");
const keyJson = process.env.PLAY_SERVICE_ACCOUNT_JSON;
if (!keyJson) throw new Error("PLAY_SERVICE_ACCOUNT_JSON is not set");
const key = JSON.parse(keyJson) as { client_email: string; private_key: string; token_uri?: string };

const root = new URL("..", import.meta.url).pathname;
const gradle = readFileSync(`${root}wimg-android/app/build.gradle.kts`, "utf8");
const version = gradle.match(/versionName = "([^"]+)"/)?.[1];
if (!version) throw new Error("versionName not found in build.gradle.kts");

// Release notes per language; stale ones (another version's header) make a draft.
const notesDir = `${root}docs/play-whats-new`;
let fresh = true;
const releaseNotes = readdirSync(notesDir)
  .filter((f) => f.endsWith(".txt"))
  .map((f) => {
    const [head, ...rest] = readFileSync(`${notesDir}/${f}`, "utf8").split("\n");
    if (head.trim() !== `# ${version}`) fresh = false;
    const text = rest.join("\n").trim();
    if (text.length > 500) throw new Error(`${f}: ${text.length} characters, Play allows 500`);
    return { language: f.replace(/\.txt$/, ""), text };
  });
if (releaseNotes.length === 0) throw new Error(`no release notes in ${notesDir}`);

async function token(): Promise<string> {
  const aud = key.token_uri ?? "https://oauth2.googleapis.com/token";
  const now = Math.floor(Date.now() / 1000);
  const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const unsigned = `${b64({ alg: "RS256", typ: "JWT" })}.${b64({
    iss: key.client_email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud,
    iat: now,
    exp: now + 600,
  })}`;
  const sig = createSign("RSA-SHA256").update(unsigned).sign(key.private_key).toString("base64url");
  const res = await fetch(aud, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${unsigned}.${sig}` }),
  });
  if (!res.ok) throw new Error(`token: ${res.status} ${await res.text()}`);
  return ((await res.json()) as { access_token: string }).access_token;
}

const auth = { authorization: `Bearer ${await token()}` };
async function call<T>(method: string, url: string, body?: BodyInit, type = "application/json"): Promise<T> {
  const res = await fetch(url, { method, headers: { ...auth, "content-type": type }, body });
  if (!res.ok) throw new Error(`${method} ${url.replace(/\?.*/, "")}: ${res.status} ${await res.text()}`);
  return (await res.json()) as T;
}

const edit = await call<{ id: string }>("POST", `${API}/edits`, "{}");
if (check) {
  const { tracks } = await call<{ tracks: { track: string; releases?: { name?: string; status: string }[] }[] }>("GET", `${API}/edits/${edit.id}/tracks`);
  for (const t of tracks) console.log(`${t.track}: ${(t.releases ?? []).map((r) => `${r.name ?? "?"} (${r.status})`).join(", ") || "-"}`);
  await fetch(`${API}/edits/${edit.id}`, { method: "DELETE", headers: auth });
  console.log(`Signed in as ${key.client_email}; nothing changed. Notes for ${version}: ${fresh ? "ready" : "not yet (would upload as a draft)"}.`);
  process.exit(0);
}
const { versionCode } = await call<{ versionCode: number }>(
  "POST",
  `${UPLOAD}/edits/${edit.id}/bundles?uploadType=media`,
  Bun.file(bundlePath),
  "application/octet-stream",
);
const status = fresh ? "completed" : "draft";
await call("PUT", `${API}/edits/${edit.id}/tracks/${track}`, JSON.stringify({
  track,
  releases: [{ name: `${version} (${versionCode})`, versionCodes: [String(versionCode)], status, releaseNotes }],
}));
await call("POST", `${API}/edits/${edit.id}:commit`);

console.log(`Uploaded ${version} (${versionCode}) to "${track}" as ${status}.`);
if (!fresh) {
  console.log(`::warning::docs/play-whats-new/*.txt don't start with "# ${version}": uploaded as a draft. Add the notes and send it for review in Play Console.`);
}
