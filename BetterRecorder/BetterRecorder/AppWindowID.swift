//
//  AppWindowID.swift
//  BetterRecorder
//
//  Stable SwiftUI `WindowGroup` identifiers aligned with Electron `windowType` values.
//

import Foundation

enum AppWindowID: String, CaseIterable, Sendable {
    case hudOverlay = "hud-overlay"
    case editor = "editor"
    case sourceSelector = "source-selector"
    case countdown = "countdown"
}
