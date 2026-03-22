//
//  ShareableContentService.swift
//  BetterRecorder
//

import Foundation
import ScreenCaptureKit

enum ShareableContentService {
    static func fetchContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }
}
