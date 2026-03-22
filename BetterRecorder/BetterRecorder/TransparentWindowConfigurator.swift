//
//  TransparentWindowConfigurator.swift
//  BetterRecorder
//
//  Matches Electron HUD overlay: transparent, frameless content area (see `createHudOverlayWindow`).
//

import AppKit
import SwiftUI

struct TransparentWindowConfigurator: NSViewRepresentable {
    var windowIdentifier: String?

    init(windowIdentifier: String? = nil) {
        self.windowIdentifier = windowIdentifier
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if let windowIdentifier {
                window.identifier = NSUserInterfaceItemIdentifier(windowIdentifier)
            }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
