import Foundation

/// Centralized configuration — all URLs, keys, and constants in one place.
enum WimgConfig {
    // MARK: - Sync API

    #if DEBUG && targetEnvironment(simulator)
    static let syncBaseURL = "http://localhost:8787"
    #else
    static let syncBaseURL = "https://wimg-sync.komiljonmaksudov.com"
    #endif

    // MARK: - GitHub

    static let releasesURL = "https://github.com/milimyname/wimg/releases"

    // MARK: - UserDefaults keys

    static let udSyncKey = "wimg_sync_key"
    static let udSyncLastTS = "wimg_sync_last_ts"
}
