//
//  CaptureSource.swift
//  BetterRecorder
//
//  Selected capture target (screen or window), aligned with Electron desktop source ids.
//

import CoreGraphics
import Foundation
import ScreenCaptureKit

struct CaptureSource: Equatable, Identifiable, Sendable {
    /// Electron-style id: `screen:123` or `window:456` (window uses CGWindowID).
    var id: String
    var displayName: String
    var kind: Kind
    var displayID: CGDirectDisplayID?
    var windowID: CGWindowID?

    enum Kind: Sendable {
        case screen
        case window
    }

    var hasSelection: Bool {
        switch kind {
        case .screen:
            return displayID != nil
        case .window:
            return windowID != nil
        }
    }
}

extension CaptureSource {
    static func screen(display: SCDisplay, name: String) -> CaptureSource {
        CaptureSource(
            id: "screen:\(display.displayID)",
            displayName: name,
            kind: .screen,
            displayID: display.displayID,
            windowID: nil
        )
    }

    static func window(_ window: SCWindow, displayName: String) -> CaptureSource {
        CaptureSource(
            id: "window:\(window.windowID)",
            displayName: displayName,
            kind: .window,
            displayID: nil,
            windowID: window.windowID
        )
    }
}
