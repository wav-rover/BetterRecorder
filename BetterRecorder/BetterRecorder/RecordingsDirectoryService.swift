//
//  RecordingsDirectoryService.swift
//  BetterRecorder
//
//  Default recordings folder under Application Support + optional user override (Electron RECORDINGS_DIR / chooseRecordingsDirectory).
//

import AppKit
import Foundation

enum RecordingsDirectoryService {
    private static let userDefaultsKey = "recordingsDirectoryBookmark"

    static func defaultRecordingsDirectoryURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let base = appSupport ?? FileManager.default.homeDirectoryForCurrentUser
        let bundleID = Bundle.main.bundleIdentifier ?? "BetterRecorder"
        let url = base.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func resolvedRecordingsDirectoryURL() -> URL {
        if let bookmark = UserDefaults.standard.data(forKey: userDefaultsKey),
           let url = resolvedURL(fromBookmark: bookmark) {
            return url
        }
        return defaultRecordingsDirectoryURL()
    }

    static func setCustomRecordingsDirectory(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: userDefaultsKey)
    }

    static func clearCustomRecordingsDirectory() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    private static func resolvedURL(fromBookmark data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale {
            return nil
        }
        return url
    }

    @MainActor
    static func chooseRecordingsDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = resolvedRecordingsDirectoryURL()

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            try setCustomRecordingsDirectory(url)
        } catch {
            return nil
        }
        return url
    }

    /// Call before writing when using a security-scoped custom directory.
    static func accessResolvedDirectoryForWriting(_ block: () throws -> Void) rethrows {
        guard let bookmark = UserDefaults.standard.data(forKey: userDefaultsKey),
              let url = resolvedURL(fromBookmark: bookmark) else {
            try block()
            return
        }
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
        try block()
    }
}
