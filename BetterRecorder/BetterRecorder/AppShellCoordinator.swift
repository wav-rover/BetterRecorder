//
//  AppShellCoordinator.swift
//  BetterRecorder
//
//  Central shell state: which primary window is active and programmatic open/dismiss
//  for auxiliary windows (mirrors Electron main + IPC window orchestration).
//

import Foundation
import Observation
import SwiftUI

enum PrimaryShell: Sendable {
    /// HUD is the main window (capture entry).
    case capture
    /// Editor is the main window after `switch-to-editor`.
    case editor
}

@MainActor
@Observable
final class AppShellCoordinator {
    var primaryShell: PrimaryShell = .capture

    private var openWindowAction: OpenWindowAction?
    private var dismissWindowAction: DismissWindowAction?

    func attachWindowActions(open: OpenWindowAction, dismiss: DismissWindowAction) {
        openWindowAction = open
        dismissWindowAction = dismiss
    }

    /// Mirrors `switch-to-editor` IPC: close HUD, close auxiliary windows, show editor.
    func switchToEditor() {
        dismissWindowAction?(id: AppWindowID.sourceSelector.rawValue)
        dismissWindowAction?(id: AppWindowID.countdown.rawValue)
        dismissWindowAction?(id: AppWindowID.hudOverlay.rawValue)
        openWindowAction?(id: AppWindowID.editor.rawValue)
        primaryShell = .editor
    }

    func openSourceSelector() {
        openWindowAction?(id: AppWindowID.sourceSelector.rawValue)
    }

    func openCountdown() {
        openWindowAction?(id: AppWindowID.countdown.rawValue)
    }

    func closeSourceSelector() {
        dismissWindowAction?(id: AppWindowID.sourceSelector.rawValue)
    }

    func closeCountdown() {
        dismissWindowAction?(id: AppWindowID.countdown.rawValue)
    }

    func showHUD() {
        openWindowAction?(id: AppWindowID.hudOverlay.rawValue)
    }
}
