# Banking Aggregators & PSD2/PSD3

## Current Approach

FinTS 3.0 direct connection (pure Zig, iOS + Android). Free, private, offline.
No intermediary sees transaction data.

## Why Not Aggregators

All PSD2 aggregators (AISPs) see transaction data in **plaintext** on their
servers. TLS only protects data in transit. AISPs must decrypt to normalize,
categorize, and standardize merchant names. This fundamentally conflicts with
wimg's local-first, privacy-first design.

## Aggregator Comparison

| | FinTS | GoCardless | finAPI | Tink | Lunch Flow | SimpleFIN |
|---|---|---|---|---|---|---|
| **Cost** | Free | "Free" (limits) | €250+/mo | Opaque | ~$3-5/mo | $1.50/mo |
| **German banks** | Most | 54+ | 2300+ | 500+ | 2400+ | US/CA only |
| **Privacy** | Zero intermediary | AISP (plaintext) | AISP | AISP | Meta-AISP | N/A |
| **Offline** | Full | No | No | No | No | No |

- **SimpleFIN**: US/Canada only — not viable for Germany
- **Lunch Flow**: Meta-aggregator routing to GoCardless/Tink/TrueLayer — adds cost, no privacy gain
- **GoCardless**: Best fallback if FinTS dies, but "free" = you're the funnel

## PSD2 XS2A Architecture

```
POST /consents → bank returns scaRedirect URL
User redirected to bank → authenticates with 2FA
Bank redirects back → app gets consentId
GET /accounts/{id}/transactions with consentId → JSON
Consent valid 180 days → must re-authenticate
```

- Berlin Group NextGenPSD2 is dominant standard (75%+ EU banks)
- Three SCA flows: redirect (most common), decoupled, embedded
- ~50+ implementation variants across German banks despite "one standard"
- Open-source adapter: github.com/adorsys/xs2a-adapter

## Privacy Deep Dive

- PSD2 uses QWAC/QSealC certificates for auth + integrity, NOT confidentiality
- PSD2 + GDPR contradict: GDPR minimizes sharing, PSD2 mandates it
- No mandatory data retention timeframe for AISPs
- PSD2 enforcement much weaker than GDPR (no EU-wide fine structure)
- Liability unclear in multi-party chains
- No technical mechanism prevents misuse — only audits/lawsuits

## AISP License — Not Worth It Now

| Requirement | Cost |
|---|---|
| BaFin application | €50-100K |
| Compliance officer | Ongoing |
| Professional indemnity insurance | Annual |
| Security audit | Recurring |
| AML procedures | Ongoing |
| QWAC/QSealC certificates | €500-2K/yr |

**When it makes sense:** wimg has paying users, revenue covers compliance,
or banks drop FinTS forcing PSD2-only access.

## PSD3 / PSR1 Timeline

- Political agreement: November 2025
- Publication: expected Q1-Q2 2026
- Full PSD3 compliance: ~2028
- Key changes: stricter API quality, fraud info sharing, consent dashboard
- FiDA (Financial Data Access): extends to investments/insurance/pensions, ~2027-2028

## Regulatory Watch

- **giroAPI Scheme**: German banks' native API initiative (launched Jan 2025)
- **FiDA**: extends open banking to insurance/investments (~2027-2028)
- **PSD3**: new rules ~2028 — wait before investing in license

## Decision

```
Now:           FinTS direct (free, private, works)     ← current
If FinTS dies: GoCardless free tier (compromise)       ← escape hatch
If business:   Own AISP license (full control)         ← only with revenue
```

## Update 2026-11-16 (research review)

- Decision unchanged: FinTS direct stays the main path. No operator-run aggregator.
- GoCardless Bank Account Data: closed to new signups (their page; since ~July 2025).
  No longer the escape hatch.
- Enable Banking: free "restricted mode" for private individuals, own linked accounts
  only. A user could bring their own app + key (no wimg server), but Enable Banking
  is still in the data path and its terms forbid public distribution without a
  contract. Ask them in writing before building. Paid tier: quote + monthly minimum.
- Tink, TrueLayer, Yapily, Salt Edge, finAPI: no public pricing found, no
  own-accounts mode. "finAPI €250+/mo" above is unverified.
- AISP: account-info-only is a BaFin registration (§34 ZAG, insurance, no capital).
  QWAC ~€400–1,350/yr, only with a regulator number. A licence would still put
  plaintext on a wimg server. "€50–100K" is unverified.
- FinTS: no shutdown announced by the DK; >2,000 institutes; VoP added 2025.
  MT940 is ending (DK rulebook terminated Nov 2025; Commerzbank HBCI on CAMT since
  June 2026). Treat CAMT as default, MT940 as legacy.
- PSD3/PSR: final texts 23 Apr 2026, not in the Official Journal as of 25 Oct 2026;
  applies ~21 months after entry into force (not before late 2028). No licence-free
  consumer data right found. FiDA: reported listed for withdrawal (Nov 2026).
- No FinTS equivalent found in AT/CH/NL/FR. EBICS is business-only.
- Next cheap steps: camt.053/052 + MT940 file import; per-bank personal APIs
  (bunq, comdirect REST, Fio) only on user demand. No scraping (MoneyMoney was
  stuck ~7 weeks in spring 2026 when its developer was ill).
- Triggers: a top-5 bank or the DK dates the end of FinTS read access; ≥2 matrix banks
  fail HKCAZ and HKKAZ for >2 weeks; ≥5 requests for one non-FinTS bank; PSR in the OJ.
