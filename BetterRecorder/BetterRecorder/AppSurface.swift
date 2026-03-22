//
//  AppSurface.swift
//  BetterRecorder
//
//  Mirrors Electron `windowType` query routing in `App.tsx`.
//

import Foundation

enum AppSurface: String, CaseIterable, Sendable {
    case hudOverlay = "hud-overlay"
    case sourceSelector = "source-selector"
    case countdown = "countdown"
    case editor = "editor"
    case `default` = "default"
}
