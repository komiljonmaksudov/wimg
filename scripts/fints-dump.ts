#!/usr/bin/env bun
/**
 * Run the real libwimg FinTS flow from the terminal and show what the bank
 * actually sends for each booking: raw MT940 `:86:` fields (?30 BIC, ?31 IBAN,
 * ?32/33 name) and CAMT <DbtrAcct>/<CdtrAcct> IBANs.
 *
 * It loads a native libwimg.dylib via bun:ffi and supplies the HTTP transport
 * (curl) that iOS normally provides through URLSession. Library code is not
 * modified.
 *
 * Build the dylib once:
 *     cd libwimg && zig build -Dtarget=aarch64-macos -Dshared=true \
 *         -Doptimize=ReleaseFast --prefix /tmp/wimg-native
 *
 * Run:
 *     LIBWIMG=/tmp/wimg-native/lib/libwimg.dylib bun scripts/fints-dump.ts \
 *         [--blz 20041177] [--days 60] [--grep "Union Investment"]
 *
 * Credentials: FINTS_USER / FINTS_PIN env vars, or prompted (PIN is not echoed).
 * Raw bank responses (contain personal data!) are written 0600 to --out
 * (default: a fresh dir under os.tmpdir()). Requests (which hold the PIN) are
 * never written anywhere.
 */

import { dlopen, FFIType, JSCallback, CString, read, toArrayBuffer, ptr } from "bun:ffi";
import { mkdtempSync, writeFileSync, chmodSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

const PRODUCT_ID = "F7C4049477F6136957A46EC28";

function arg(name: string, fallback: string): string {
	const i = process.argv.indexOf(`--${name}`);
	return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const blz = arg("blz", "20041177");
const days = Number(arg("days", "60"));
const grep = arg("grep", "").toLowerCase();
const outDir = arg("out", mkdtempSync(join(tmpdir(), "wimg-fints-")));
const libPath = process.env.LIBWIMG ?? "libwimg/zig-out/lib/libwimg.dylib";

function prompt(label: string, hidden = false): string {
	process.stdout.write(label);
	if (hidden) Bun.spawnSync(["stty", "-echo"], { stdin: "inherit" });
	const line = (globalThis.prompt?.("") ?? "").trim();
	if (hidden) {
		Bun.spawnSync(["stty", "echo"], { stdin: "inherit" });
		process.stdout.write("\n");
	}
	return line;
}

const user = process.env.FINTS_USER ?? prompt("Comdirect Zugangsnummer: ");
const pin = process.env.FINTS_PIN ?? prompt("PIN (hidden): ", true);

const lib = dlopen(libPath, {
	wimg_init: { args: [FFIType.cstring], returns: FFIType.i32 },
	wimg_set_http_callback: { args: [FFIType.ptr], returns: FFIType.void },
	wimg_fints_connect: { args: [FFIType.ptr, FFIType.u32], returns: FFIType.ptr },
	wimg_fints_send_tan: { args: [FFIType.ptr, FFIType.u32], returns: FFIType.ptr },
	wimg_fints_fetch: { args: [FFIType.ptr, FFIType.u32], returns: FFIType.ptr },
	wimg_fints_get_tan_media: { args: [], returns: FFIType.ptr },
	wimg_fints_set_tan_medium: { args: [FFIType.ptr, FFIType.u32], returns: FFIType.ptr },
});

// ---- Transport: base64 FinTS over HTTPS via curl ----
let respCount = 0;
const raw: string[] = []; // decoded bank responses

const http = new JSCallback(
	(urlPtr, urlLen, bodyPtr, bodyLen, outPtr, outLen) => {
		const url = Buffer.from(toArrayBuffer(urlPtr, 0, urlLen)).toString();
		const body = Buffer.from(toArrayBuffer(bodyPtr, 0, bodyLen));
		const p = Bun.spawnSync(
			["curl", "-sS", "--fail", "--max-time", "60", "-X", "POST", "--data-binary", "@-", url],
			{ stdin: body },
		);
		if (p.exitCode !== 0) {
			console.error("curl failed:", p.stderr.toString());
			return -1;
		}
		const b64 = p.stdout;
		if (b64.length > outLen) return -1;
		new Uint8Array(toArrayBuffer(outPtr, 0, outLen)).set(b64);
		const decoded = Buffer.from(b64.toString().replace(/\s+/g, ""), "base64").toString("latin1");
		raw.push(decoded);
		const file = join(outDir, `resp-${++respCount}.txt`);
		writeFileSync(file, decoded, { mode: 0o600 });
		return b64.length;
	},
	{ args: [FFIType.ptr, FFIType.u32, FFIType.ptr, FFIType.u32, FFIType.ptr, FFIType.u32], returns: FFIType.i32 },
);

function call(fn: (p: any, n: number) => any, payload: object): any {
	const buf = Buffer.from(JSON.stringify(payload));
	const out = fn(ptr(buf), buf.length);
	if (!out) throw new Error("libwimg returned null (see stderr above)");
	const len = read.u32(out, 0);
	return JSON.parse(new CString(out, 4, len).toString());
}

// ---- Run the flow ----
lib.symbols.wimg_init(Buffer.from(join(outDir, "scratch.db") + "\0") as any);
lib.symbols.wimg_set_http_callback(http.ptr as any);

console.log("connecting…");
const conn = call(lib.symbols.wimg_fints_connect, { blz, user, pin, product: PRODUCT_ID });
console.log("connect:", conn.status, conn.message ?? "");
if (conn.status !== "ok") process.exit(1);

if (conn.tan_medium_required) {
	const out = lib.symbols.wimg_fints_get_tan_media()!;
	const media = JSON.parse(new CString(out as any, 4, read.u32(out as any, 0)).toString());
	console.log("TAN media:", JSON.stringify(media.media));
	const name = prompt("TAN medium name: ");
	call(lib.symbols.wimg_fints_set_tan_medium, { name });
}

const iso = (d: Date) => d.toISOString().slice(0, 10);
const to = new Date();
const from = new Date(Date.now() - days * 86400_000);

let res = call(lib.symbols.wimg_fints_fetch, { from: iso(from), to: iso(to) });
while (res.status === "tan_required") {
	console.log("\nTAN required:", res.challenge ?? "");
	if (res.phototan) {
		const png = join(outDir, "phototan.png");
		writeFileSync(png, Buffer.from(res.phototan, "base64"), { mode: 0o600 });
		console.log("photoTAN image:", png);
		Bun.spawnSync(["open", png]); // macOS: show it, scan with your photoTAN app
	}
	const tan = res.decoupled ? (prompt("Approve in banking app, then press Enter… "), "") : prompt("TAN: ");
	const t = call(lib.symbols.wimg_fints_send_tan, { tan });
	console.log("send_tan:", t.status, t.message ?? "");
	if (t.status === "error") process.exit(1);
	res = t.status === "tan_required" ? t : call(lib.symbols.wimg_fints_fetch, { from: iso(from), to: iso(to) });
}
console.log("fetch:", res.status, res.message ?? "");

// ---- Inspect raw payloads ----
const all = raw.join("\n");
const entries86 = [...all.matchAll(/:86:([\s\S]*?)(?=\r?\n:6[01]:|\r?\n-|$)/g)].map((m) => m[1].replace(/\r?\n/g, ""));
const camt = [...all.matchAll(/<(Dbtr|Cdtr)Acct>[\s\S]*?<IBAN>([A-Z0-9]+)<\/IBAN>/g)].map((m) => `${m[1]}: ${m[2]}`);

console.log(`\nMT940 :86: entries: ${entries86.length}, CAMT account IBANs: ${camt.length}`);
let withIban = 0;
for (const e of entries86) {
	const f = (n: string) => e.match(new RegExp(`\\?${n}([^?]*)`))?.[1] ?? "";
	const iban = f("31");
	if (/^[A-Z]{2}\d{2}/.test(iban)) withIban++;
	if (grep && !e.toLowerCase().includes(grep)) continue;
	console.log("---");
	console.log(`?30 BIC/BLZ : ${f("30")}`);
	console.log(`?31 IBAN/Kto: ${iban}`);
	console.log(`?32 name    : ${f("32")}${f("33")}`);
	console.log(`text        : ${e.slice(0, 160)}`);
}
console.log(`\nentries whose ?31 looks like an IBAN: ${withIban}/${entries86.length}`);
if (camt.length) console.log("CAMT:", camt.slice(0, 10).join(", "));
console.log(`\nRaw responses (personal data): ${outDir}`);
