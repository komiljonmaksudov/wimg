// Revokes development certificates by serial number through the App Store
// Connect API. CI's fresh Mac makes a new "Apple Development" certificate on
// every iOS build; without this the account hits Apple's limit (2026-11-20,
// v1.0.1: "Your account has reached the maximum number of certificates").
//
//   swift scripts/asc-revoke-cert.swift <serial> [<serial> …]
//   env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (the .p8)
//
// Only DEVELOPMENT / IOS_DEVELOPMENT certificates are touched; a distribution
// certificate with that serial is left alone. No dependencies (CryptoKit).
import CryptoKit
import Foundation

func env(_ k: String) -> String {
    guard let v = ProcessInfo.processInfo.environment[k], !v.isEmpty else { fatalError("\(k) missing") }
    return v
}

func b64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

func token() throws -> String {
    let pem = try String(contentsOfFile: env("ASC_KEY_PATH"), encoding: .utf8)
    let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
    let now = Int(Date().timeIntervalSince1970)
    let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": env("ASC_KEY_ID"), "typ": "JWT"])
    let payload = try JSONSerialization.data(withJSONObject: [
        "iss": env("ASC_ISSUER_ID"), "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1",
    ])
    let input = b64url(header) + "." + b64url(payload)
    let sig = try key.signature(for: Data(input.utf8)).rawRepresentation
    return input + "." + b64url(sig)
}

func call(_ method: String, _ path: String, _ jwt: String) async throws -> (Int, [String: Any]) {
    var req = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com" + path)!)
    req.httpMethod = method
    req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
    let (data, resp) = try await URLSession.shared.data(for: req)
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    return ((resp as? HTTPURLResponse)?.statusCode ?? 0, json)
}

let serials = CommandLine.arguments.dropFirst().map { $0.uppercased() }
guard !serials.isEmpty else { print("no certificate serials given, nothing to do"); exit(0) }
let jwt = try token()
for serial in serials {
    // openssl may print a leading zero that App Store Connect leaves out.
    var found: [[String: Any]] = []
    for s in Set([serial, String(serial.drop(while: { $0 == "0" }))]) {
        let (_, json) = try await call("GET", "/v1/certificates?filter%5BserialNumber%5D=\(s)&limit=5", jwt)
        found += json["data"] as? [[String: Any]] ?? []
    }
    if found.isEmpty { print("\(serial): not found in App Store Connect"); continue }
    for cert in found {
        let id = cert["id"] as? String ?? ""
        let attrs = cert["attributes"] as? [String: Any] ?? [:]
        let type = attrs["certificateType"] as? String ?? ""
        let name = attrs["name"] as? String ?? ""
        guard type == "DEVELOPMENT" || type == "IOS_DEVELOPMENT" else {
            print("\(serial): \(type) \(name), left alone"); continue
        }
        let (status, _) = try await call("DELETE", "/v1/certificates/\(id)", jwt)
        print("\(serial): \(type) \(name) → \(status == 204 ? "revoked" : "not revoked (HTTP \(status))")")
    }
}
