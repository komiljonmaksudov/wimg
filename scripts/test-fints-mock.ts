#!/usr/bin/env bun
/**
 * End-to-end FinTS flow test against a scripted fake bank.
 *
 * Loads a native libwimg.dylib via bun:ffi and plays the bank side of the
 * HTTP callback, so connect → TAN → fetch run through the real C ABI
 * (root.zig) without credentials or network. The bank parameters (HITANS) are
 * the real ones from a Berliner Sparkasse anonymous probe; the dialog replies
 * follow the FinTS spec / python-fints. This proves our flow against that
 * reading of the protocol — it is not a substitute for a real bank login.
 *
 * Scenarios:
 *   pushtan  3920 allows 911+923 → picks 923 (decoupled), HKTAN v7, 3955 →
 *            three 3956 status polls → approved → HKKAZ import
 *   chiptan  3920 allows 911 only → HKTAN v6, typed TAN → HKKAZ import
 *   volksbank  Atruvia parameters: no MT940 (HIKAZS) at all, only CAMT →
 *            app approval (946) → HKCAZ with a KTI1 account → CAMT import
 *   tanmedium  typed-TAN method that needs a TAN medium (smsTAN, two phones) →
 *            HKTAB lookup in its own TAN-free dialog → medium name in HKTAN
 *
 * Build the dylib, then run:
 *     cd libwimg && zig build -Dtarget=aarch64-macos -Dshared=true \
 *         -Doptimize=ReleaseFast --prefix /tmp/wimg-native
 *     LIBWIMG=/tmp/wimg-native/lib/libwimg.dylib bun scripts/test-fints-mock.ts
 */

import { dlopen, FFIType, JSCallback, CString, read, toArrayBuffer, ptr } from "bun:ffi";
import { mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

// BLZs must exist in banks.zig: Berliner Sparkasse, Volksbank Vorpommern (Atruvia).
const BLZ = process.argv[2] === "volksbank" ? "13091054" : "10050000";
const libPath = process.env.LIBWIMG ?? "libwimg/zig-out/lib/libwimg.dylib";

// Each scenario runs in its own process: libwimg keeps one global session.
const scenario = process.argv[2];
if (!scenario) {
	let failed = false;
	for (const s of ["pushtan", "chiptan", "volksbank", "tanmedium"]) {
		const p = Bun.spawnSync(["bun", import.meta.path, s], { stdout: "pipe", stderr: "pipe", env: process.env });
		const out = p.stdout.toString();
		process.stdout.write(out);
		if (p.exitCode !== 0) {
			failed = true;
			console.log(`  (exit ${p.exitCode})`);
			if (process.env.VERBOSE) process.stdout.write(p.stderr.toString());
		}
	}
	process.exit(failed ? 1 : 0);
}

const HITANS =
	"HITANS:139:6:3+1+1+1+J:N:0:910:2:HHD1.3.0:::chipTAN manuell:6:1:TAN-Nummer:3:J:2:N:0:0:N:N:00:0:N:1:911:2:HHD1.3.2OPT:HHDOPT1:1.3.2:chipTAN optisch:6:1:TAN-Nummer:3:J:2:N:0:0:N:N:00:0:N:1'" +
	"HITANS:140:7:3+1+1+1+N:N:0:923:2:pushTAN-cas:Decoupled::pushTAN 2.0:::Aufforderung:2048:J:2:N:0:0:N:N:00:2:N:5:180:1:1:J:J'";

// Atruvia (fints1.atruvia.de), anonymous BPD probe Nov 2026.
const HITANS_ATRUVIA =
	"HITANS:84:6:3+1+1+1+J:N:0:962:2:HHD1.4:HHD:1.4:Smart-TAN plus manuell:6:1:Challenge:2048:J:1:N:0:2:N:J:00:0:N:1'" +
	"HITANS:85:7:3+1+1+1+N:N:0:946:2:DECOUPLED:Decoupled::SecureGo plus (Direktfreigabe):::TAN:2048:J:1:N:0:2:N:J:00:0:N:1:150:2:2:J:J'";
// Typed-TAN method with two registered phones (description_required=2, media=2).
const HITANS_SMS = "HITANS:139:6:3+1+1+1+J:N:0:920:2:smsTAN:mobileTAN::smsTAN:6:1:TAN-Nummer:3:J:2:N:0:0:N:N:00:2:N:2'";
// HITAB as python-fints serialises TANMedia4 entries.
const HITAB = "HITAB:4:4:3+0+M:1::::::::Handy Eins:********5678+M:1::::::::Handy Zwei:********5679'";
const HICAZS_ATRUVIA = "HICAZS:52:1:3+1+1+1+740:N:N:urn?:iso?:std?:iso?:20022?:tech?:xsd?:camt.052.001.08'";

const CAMT =
	'<?xml version="1.0" encoding="UTF-8"?><Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08"><BkToCstmrAcctRpt><Rpt>' +
	'<Ntry><Amt Ccy="EUR">12.50</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-03-01</Dt></BookgDt><NtryDtls><TxDtls><RmtInf><Ustrd>REWE SAGT DANKE 12345</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>' +
	'<Ntry><Amt Ccy="EUR">3500.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><BookgDt><Dt>2026-03-05</Dt></BookgDt><NtryDtls><TxDtls><RmtInf><Ustrd>GEHALT MAERZ 2026</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>' +
	"</Rpt></BkToCstmrAcctRpt></Document>";

const MT940 = [
	":20:STARTUMS",
	":25:10050000/1234567890",
	":28C:0/1",
	":60F:C260301EUR5000,00",
	":61:2603010301D12,50NMSC",
	":86:?00KARTENZAHLUNG?20SVWZ+REWE SAGT DANKE 12345?30COBADEFF?31DE89370400440532013000?32REWE Markt GmbH",
	":61:2603050305C3500,00NMSC",
	":86:?00GEHALT/LOHN?20SVWZ+GEHALT MAERZ 2026?32ARBEITGEBER GMBH?33LOHNBUERO",
	":62F:C260305EUR8487,50",
	"-",
	"",
].join("\r\n");

const failures: string[] = [];
const check = (ok: boolean, what: string) => {
	console.log(`  ${ok ? "ok  " : "FAIL"} ${what}`);
	if (!ok) failures.push(what);
};

function bankMsg(dialog: string, ...segs: string[]): string {
	return `HNHBK:1:3+000000000000+300+${dialog}+1+${dialog}:1'` + segs.join("") + "HNHBS:99:1+1'";
}

// ---- The fake bank ----
let polls = 0;
const seen: string[] = [];

function bank(req: string): string {
	const volksbank = scenario === "volksbank";
	const pushtan = scenario === "pushtan" || volksbank; // app approval flow
	const tanmedium = scenario === "tanmedium";
	const ver = pushtan ? 7 : 6;
	const secFunc = volksbank ? "946" : pushtan ? "923" : tanmedium ? "920" : "911";

	if (req.includes("HKEND")) {
		seen.push("end");
		return bankMsg("0", "HIRMG:2:2+0100::Dialog beendet.'");
	}
	if (req.includes("HKSYN")) {
		seen.push("sync");
		return bankMsg(
			"SYNCDLG",
			"HIRMG:2:2+0010::Nachricht entgegengenommen.'",
			`HIRMS:3:2:3+3920::Zugelassene Zwei-Schritt-Verfahren fuer den Benutzer.:${volksbank ? "962:946" : pushtan ? "911:923" : tanmedium ? "920" : "911"}+0020::Auftrag ausgefuehrt.'`,
			`HIBPA:4:3:3+20+280:${BLZ}+Testbank+3+1+300'`,
			volksbank ? HITANS_ATRUVIA : tanmedium ? HITANS_SMS + "HITABS:130:4:3+1+1+0'" : HITANS,
			volksbank ? HICAZS_ATRUVIA : "HIKAZS:104:5:3+1+1+360:J:N'",
			"HISYN:150:4:5+SYSTEMID123'",
			`HIUPD:151:6:4+1234567890::280:${BLZ}+DE12130910541234567890+testuser+1+EUR+Max Mustermann++Girokonto'`,
		);
	}
	if (/HKTAN:\d+:\d\+4\+HKTAB/.test(req)) {
		seen.push("tabinit");
		check(req.includes("HKIDN") && req.includes("HKVVB"), "TAN media lookup opens its own dialog (HKIDN + HKVVB)");
		check(req.includes(`+PIN:1+${secFunc}+`), `TAN media dialog signs with method ${secFunc}`);
		// No SCA for an HKTAB dialog.
		return bankMsg("TABDLG", "HIRMG:2:2+0010::Nachricht entgegengenommen.'", "HIRMS:3:2:5+3076::Starke Kundenauthentifizierung nicht notwendig.'", "HITAN:4:6:5+4++noref+nochallenge'");
	}
	if (req.includes("HKTAB:")) {
		seen.push("tab");
		check(req.includes("HKTAB:3:4+0+A'"), "HKTAB asks for all TAN media in the version from HITABS");
		check(req.includes("+TABDLG+"), "HKTAB is sent inside the opened dialog");
		return bankMsg("TABDLG", "HIRMG:2:2+0010::Nachricht entgegengenommen.'", "HIRMS:3:2:3+0020::Auftrag ausgefuehrt.'", HITAB);
	}
	if (req.includes("HKIDN")) {
		seen.push("auth");
		if (tanmedium) check(/HKTAN:\d+:6\+4\+HKIDN\+{8}:\+Handy Zwei'/.test(req), "auth init HKTAN names the chosen TAN medium");
		check(req.includes(`+PIN:1+${secFunc}+`), `auth init signs with method ${secFunc}`);
		check(new RegExp(`HKTAN:\\d+:${ver}\\+4\\+HKIDN`).test(req), `auth init sends HKTAN v${ver} process 4`);
		check(req.includes("+SYSTEMID123"), "auth init carries the synced system id");
		if (pushtan) {
			return bankMsg(
				"AUTHDLG",
				"HIRMG:2:2+0010::Nachricht entgegengenommen.'",
				"HIRMS:3:2:5+3955::Auftrag empfangen - Bitte Auftrag in Ihrer App freigeben.'",
				"HITAN:4:7:5+4++REF-AUTH+Bitte geben Sie den Auftrag in der pushTAN-App frei.'",
			);
		}
		return bankMsg(
			"AUTHDLG",
			"HIRMG:2:2+0010::Nachricht entgegengenommen.'",
			"HIRMS:3:2:5+0030::Auftrag empfangen - Bitte TAN eingeben.'",
			"HITAN:4:6:5+4++REF-CHIP+Bitte TAN eingeben'",
		);
	}
	if (/HKTAN:\d+:\d\+S/.test(req)) {
		polls++;
		seen.push("poll");
		check(/HKTAN:\d+:7\+S/.test(req), `status poll ${polls} uses HKTAN v7 process S`);
		check(req.includes("REF-AUTH"), `status poll ${polls} quotes the original task reference`);
		check(req.includes("+AUTHDLG+"), `status poll ${polls} stays in the auth dialog`);
		// Status replies carry neither challenge text nor reference: the code decides.
		if (polls < 3) {
			return bankMsg(
				"AUTHDLG",
				"HIRMG:2:2+3060::Bitte beachten Sie die enthaltenen Warnungen/Hinweise.'",
				"HIRMS:3:2:3+3956::Starke Kundenauthentifizierung noch ausstehend.'",
				"HITAN:4:7:3+S'",
			);
		}
		return bankMsg("AUTHDLG", "HIRMG:2:2+0010::Nachricht entgegengenommen.'", "HIRMS:3:2:3+0020::Auftrag ausgefuehrt.'", "HITAN:4:7:3+S'");
	}
	if (/HKTAN:\d+:\d\+2/.test(req)) {
		seen.push("tan");
		check(/HKTAN:\d+:6\+2/.test(req), "TAN submit uses HKTAN v6 process 2");
		check(req.includes("REF-CHIP"), "TAN submit quotes the task reference");
		check(req.includes(":123456'"), "TAN submit carries the typed TAN in the signature");
		return bankMsg("AUTHDLG", "HIRMG:2:2+0010::Nachricht entgegengenommen.'", "HIRMS:3:2:3+0020::Auftrag ausgefuehrt.'");
	}
	if (req.includes("HKCAZ")) {
		seen.push("caz");
		check(volksbank, "CAMT request only for the CAMT-only bank");
		check(
			req.includes(`HKCAZ:3:1+DE12130910541234567890:GENODEF1HST:1234567890::280:${BLZ}+urn?:iso?:std?:iso?:20022?:tech?:xsd?:camt.052.001.08+N+20260301+20260331+`),
			"HKCAZ: account is one KTI1 element (IBAN:BIC:Konto::280:BLZ), then the bank's camt format",
		);
		check(/HKTAN:\d+:7\+4\+HKCAZ/.test(req), "CAMT request sends HKTAN v7 process 4");
		check(req.includes("+AUTHDLG+"), "CAMT request reuses the approved dialog");
		return bankMsg(
			"AUTHDLG",
			"HIRMG:2:2+0010::Nachricht entgegengenommen.'",
			"HIRMS:3:2:3+0020::Auftrag ausgefuehrt.+3076::Starke Kundenauthentifizierung nicht notwendig.'",
			`HICAZ:4:1:3+DE12130910541234567890:GENODEF1HST:1234567890::280:${BLZ}+urn?:iso?:std?:iso?:20022?:tech?:xsd?:camt.052.001.08+@${CAMT.length}@${CAMT}'`,
		);
	}
	if (req.includes("HKKAZ")) {
		check(!volksbank, "MT940 request never goes to the CAMT-only bank");
		seen.push("kaz");
		check(/HKKAZ:\d+:5\+/.test(req), "statement request is HKKAZ v5");
		check(new RegExp(`HKTAN:\\d+:${ver}\\+4\\+HKKAZ`).test(req), `statement request sends HKTAN v${ver} process 4`);
		check(req.includes("+AUTHDLG+"), "statement request reuses the approved dialog");
		check(req.includes(`1234567890::280:${BLZ}`), "statement request uses the account from HIUPD");
		return bankMsg(
			"AUTHDLG",
			"HIRMG:2:2+0010::Nachricht entgegengenommen.'",
			"HIRMS:3:2:3+0020::Auftrag ausgefuehrt.+3076::Starke Kundenauthentifizierung nicht notwendig.'",
			`HIKAZ:4:5:3+@${MT940.length}@${MT940}'`,
		);
	}
	seen.push("unknown");
	check(false, `unexpected request: ${req.slice(0, 200)}`);
	return bankMsg("0", "HIRMG:2:2+9010::Unbekannt.'");
}

// ---- libwimg via FFI ----
const lib = dlopen(libPath, {
	wimg_init: { args: [FFIType.cstring], returns: FFIType.i32 },
	wimg_set_http_callback: { args: [FFIType.ptr], returns: FFIType.void },
	wimg_fints_connect: { args: [FFIType.ptr, FFIType.u32], returns: FFIType.ptr },
	wimg_fints_send_tan: { args: [FFIType.ptr, FFIType.u32], returns: FFIType.ptr },
	wimg_fints_fetch: { args: [FFIType.ptr, FFIType.u32], returns: FFIType.ptr },
	wimg_fints_get_tan_media: { args: [], returns: FFIType.ptr },
	wimg_fints_set_tan_medium: { args: [FFIType.ptr, FFIType.u32], returns: FFIType.ptr },
});

const http = new JSCallback(
	(_urlPtr, _urlLen, bodyPtr, bodyLen, outPtr, outLen) => {
		const b64 = Buffer.from(toArrayBuffer(bodyPtr, 0, bodyLen)).toString();
		const req = Buffer.from(b64, "base64").toString("latin1");
		const resp = Buffer.from(Buffer.from(bank(req), "latin1").toString("base64"));
		if (resp.length > outLen) return -1;
		new Uint8Array(toArrayBuffer(outPtr, 0, outLen)).set(resp);
		return resp.length;
	},
	{ args: [FFIType.ptr, FFIType.u32, FFIType.ptr, FFIType.u32, FFIType.ptr, FFIType.u32], returns: FFIType.i32 },
);

function call(fn: (p: any, n: number) => any, payload: object): any {
	const buf = Buffer.from(JSON.stringify(payload));
	const out = fn(ptr(buf), buf.length);
	if (!out) return { status: "null" };
	return JSON.parse(new CString(out, 4, read.u32(out, 0)).toString());
}

const dir = mkdtempSync(join(tmpdir(), "wimg-mock-"));
console.log(`scenario: ${scenario}`);
lib.symbols.wimg_init(Buffer.from(join(dir, "mock.db") + "\0") as any);
lib.symbols.wimg_set_http_callback(http.ptr as any);
const range = { from: "2026-03-01", to: "2026-03-31" };

const conn = call(lib.symbols.wimg_fints_connect, { blz: BLZ, user: "testuser", pin: "12345", product: "F7C4049477F6136957A46EC28" });
check(conn.status === "ok", `connect ok (${JSON.stringify(conn).slice(0, 80)})`);
if (scenario === "tanmedium") {
	check(conn.tan_medium_required === true, "connect asks for a TAN medium");
	const out = lib.symbols.wimg_fints_get_tan_media();
	const media = out ? JSON.parse(new CString(out, 4, read.u32(out, 0)).toString()) : { status: "null" };
	const names = (media.media ?? []).map((m: any) => m.name);
	check(media.status === "ok" && names.join("|") === "Handy Eins|Handy Zwei", `TAN media listed (${JSON.stringify(media).slice(0, 120)})`);
	check(seen.join(" ").endsWith("tabinit tab end"), `lookup dialog is opened and closed (${seen.join(" → ")})`);
	const set = call(lib.symbols.wimg_fints_set_tan_medium, { name: "Handy Zwei" });
	check(set.status === "ok", "TAN medium selected");
} else {
	check(conn.tan_medium_required === false, "no TAN medium picker");
}

const first = call(lib.symbols.wimg_fints_fetch, range);
check(first.status === "tan_required", `first fetch asks for approval/TAN (${first.status})`);

if (scenario === "pushtan" || scenario === "volksbank") {
	check(first.decoupled === true, "challenge is flagged as app approval (decoupled)");
	const t = call(lib.symbols.wimg_fints_send_tan, { tan: "" });
	check(t.status === "ok", `status check returns ok once approved (${JSON.stringify(t)})`);
	check(polls === 3, `polled until approved (${polls} polls, bank approves on the 3rd)`);
} else {
	check(first.decoupled === false, "challenge is a typed TAN");
	const t = call(lib.symbols.wimg_fints_send_tan, { tan: "123456" });
	check(t.status === "ok", `TAN accepted (${JSON.stringify(t)})`);
}

const res = call(lib.symbols.wimg_fints_fetch, range);
check(res.imported === 2, `statements imported (${JSON.stringify(res).slice(0, 120)})`);
check(seen.filter((s) => s === "auth").length === 1, `one authenticated dialog, no re-login (${seen.join(" → ")})`);

rmSync(dir, { recursive: true, force: true });
console.log(failures.length ? `  ${failures.length} FAILED` : "  all checks passed");
process.exit(failures.length ? 1 : 0);
