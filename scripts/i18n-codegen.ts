/**
 * Generates the iOS + Android runtime translation tables from the single
 * `i18n/en.ts` source of truth.
 *
 * Outputs:
 *   wimg-ios/plugins/WimgI18n/Sources/WimgI18n/Translations.swift
 *   wimg-android/app/src/main/java/com/wimg/app/i18n/Translations.kt
 *
 * Usage: bun scripts/i18n-codegen.ts
 */
import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import { en } from "../i18n/en";

// --- iOS: Translations.swift (inside WimgI18n SPM package) ---
function escapeSwift(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

let swift = `// Auto-generated from i18n/en.ts — do not edit manually.
// Run: bun scripts/i18n-codegen.ts
//
// This file is regenerated on every codegen run. Edits here will be lost.

internal let translations: [String: String] = [
`;

for (const [de, enValue] of Object.entries(en)) {
  swift += `    "${escapeSwift(de)}": "${escapeSwift(enValue)}",\n`;
}

swift += `]
`;

const swiftPath = "wimg-ios/plugins/WimgI18n/Sources/WimgI18n/Translations.swift";
writeFileSync(swiftPath, swift);

// --- Android: Translations.kt ---
function escapeKotlin(s: string): string {
  return s
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\$/g, "\\$");
}

let kotlin = `// Auto-generated from i18n/en.ts — do not edit manually.
// Run: bun scripts/i18n-codegen.ts
//
// This file is regenerated on every codegen run. Edits here will be lost.

package com.wimg.app.i18n

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import com.wimg.app.ui.theme.LocaleState

private val translations: Map<String, String> = mapOf(
`;

for (const [de, enValue] of Object.entries(en)) {
  kotlin += `    "${escapeKotlin(de)}" to "${escapeKotlin(enValue)}",\n`;
}

kotlin += `)

/** Composable lookup — recomposes when LocaleState.locale flips. */
@Composable
@ReadOnlyComposable
fun L(key: String): String =
    if (LocaleState.locale == "en") translations[key] ?: key else key

/** Composable lookup with format args. */
@Composable
@ReadOnlyComposable
fun L(key: String, vararg args: Any?): String = L(key).format(*args)

/** Non-composable fallback for model layer / outside compose scope. */
fun __t(key: String): String =
    if (LocaleState.locale == "en") translations[key] ?: key else key
`;

const kotlinDir = "wimg-android/app/src/main/java/com/wimg/app/i18n";
if (!existsSync(kotlinDir)) mkdirSync(kotlinDir, { recursive: true });
const kotlinPath = `${kotlinDir}/Translations.kt`;
writeFileSync(kotlinPath, kotlin);

console.log(`Generated ${swiftPath} with ${Object.keys(en).length} entries`);
console.log(`Generated ${kotlinPath} with ${Object.keys(en).length} entries`);
