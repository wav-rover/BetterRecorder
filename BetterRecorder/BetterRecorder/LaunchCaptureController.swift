//
//  LaunchCaptureController.swift
//  BetterRecorder
//
//  Coordinates HUD capture preferences, ScreenCaptureKit session, countdown, and editor handoff.
//

import AppKit
import AVFoundation
import Foundation
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

enum HUDDropdown: Equatable {
    case none
    case sources
    case mic
    case countdown
    case webcam
    case more
}

@Observable
@MainActor
final class LaunchCaptureController: NSObject {
    private let coordinator: AppShellCoordinator

    var selectedSource: CaptureSource?
    var microphoneEnabled = false
    var microphoneDeviceID: String?
    var systemAudioEnabled = false
    var webcamEnabled = false
    var webcamDeviceID: String?
    var countdownDelaySeconds: Int = 3
    var hideHudFromCapture = false

    var recording = false
    var paused = false
    var countdownActive = false
    var countdownTick: Int?
    var elapsedTimeString = "00:00"

    var activeDropdown: HUDDropdown = .none

    var pendingMainVideoURL: URL?
    var pendingWebcamVideoURL: URL?

    private var recordingEngine: ScreenCaptureRecordingEngine?
    private var webcamRecorder: WebcamMovieRecorder?
    private var elapsedTimer: Timer?
    private var sessionStartDate: Date?
    private var pausedElapsedOffset: TimeInterval = 0
    private var countdownTask: Task<Void, Never>?
    private var sessionTimestamp: Int64 = 0

    private static let countdownOptions = [0, 3, 5, 10]

    init(coordinator: AppShellCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    var hasSelectedSource: Bool {
        selectedSource?.hasSelection ?? false
    }

    var recordingsDirectoryPath: String {
        RecordingsDirectoryService.resolvedRecordingsDirectoryURL().path
    }

    func setCountdownDelay(_ value: Int) {
        guard Self.countdownOptions.contains(value) else { return }
        countdownDelaySeconds = value
        UserDefaults.standard.set(value, forKey: "countdownDelaySeconds")
    }

    func loadPersistedDefaults() {
        if let v = UserDefaults.standard.object(forKey: "countdownDelaySeconds") as? Int,
           Self.countdownOptions.contains(v) {
            countdownDelaySeconds = v
        }
    }

    func chooseRecordingsFolder() {
        _ = RecordingsDirectoryService.chooseRecordingsDirectory()
    }

    func openSourceSelectorIfNeeded() {
        if !hasSelectedSource {
            coordinator.openSourceSelector()
        }
    }

    func openSourceSelectorWindow() {
        coordinator.openSourceSelector()
    }

    func applySelectedSource(_ source: CaptureSource) {
        selectedSource = source
        coordinator.closeSourceSelector()
    }

    func cancelSourceSelector() {
        coordinator.closeSourceSelector()
    }

    func preparePermissions() async -> Bool {
        do {
            _ = try await ShareableContentService.fetchContent()
        } catch {
            return false
        }

        if microphoneEnabled {
            let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
            }
            if !ok { return false }
        }

        if webcamEnabled {
            let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { cont.resume(returning: $0) }
            }
            if !ok { return false }
        }

        return true
    }

    func toggleRecording() async {
        if recording {
            await stopRecording(switchToEditorAfter: true)
        } else {
            await startRecordingFlow()
        }
    }

    func pauseOrResume() {
        guard recording else { return }
        if paused {
            recordingEngine?.resumeCapture()
            webcamRecorder?.resume()
            paused = false
            sessionStartDate = Date().addingTimeInterval(-pausedElapsedOffset)
            startElapsedTimer()
        } else {
            recordingEngine?.pauseCapture()
            webcamRecorder?.pause()
            paused = true
            if let start = sessionStartDate {
                pausedElapsedOffset = Date().timeIntervalSince(start)
            }
            elapsedTimer?.invalidate()
        }
    }

    func cancelRecording() async {
        countdownTask?.cancel()
        countdownTask = nil
        countdownActive = false
        coordinator.closeCountdown()

        if recording {
            webcamRecorder?.cancelSession()
            webcamRecorder = nil
            if let engine = recordingEngine {
                _ = try? await engine.stopCapture()
            }
            recordingEngine = nil
            recording = false
            paused = false
            elapsedTimer?.invalidate()
            sessionStartDate = nil
            pausedElapsedOffset = 0
            updateElapsedLabel(0)
        }
    }

    func hideHudWindow() {
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue == AppWindowID.hudOverlay.rawValue }) {
            w.orderOut(nil)
        }
    }

    func closeApplication() {
        NSApp.terminate(nil)
    }

    func openVideoFileThenEditor() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingMainVideoURL = url
        pendingWebcamVideoURL = nil
        coordinator.switchToEditor()
    }

    func openProjectFileThenEditor() async {
        let panel = NSOpenPanel()
        if let recordly = UTType(filenameExtension: "recordly") {
            panel.allowedContentTypes = [recordly]
        } else {
            panel.allowedContentTypes = [.json]
        }
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingMainVideoURL = nil
        pendingWebcamVideoURL = nil
        UserDefaults.standard.set(url.path, forKey: "lastOpenedProjectPath")
        coordinator.switchToEditor()
    }

    func stopRecordingFromTray() async {
        if recording {
            await stopRecording(switchToEditorAfter: true)
        }
    }

    func showHudWindow() {
        coordinator.showHUD()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Private

    private func startRecordingFlow() async {
        guard !recording, !countdownActive else { return }

        guard let source = selectedSource, source.hasSelection else {
            coordinator.openSourceSelector()
            return
        }

        guard await preparePermissions() else { return }

        if countdownDelaySeconds > 0 {
            await runCountdownThenRecord()
        } else {
            await beginCaptureAfterCountdown()
        }
    }

    private func runCountdownThenRecord() async {
        countdownActive = true
        coordinator.openCountdown()
        let total = countdownDelaySeconds

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            countdownTask = Task { @MainActor in
                for tick in stride(from: total, through: 1, by: -1) {
                    if Task.isCancelled {
                        await cancelCountdownUI()
                        cont.resume()
                        return
                    }
                    countdownTick = tick
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                if Task.isCancelled {
                    await cancelCountdownUI()
                    cont.resume()
                    return
                }
                await cancelCountdownUI()
                await beginCaptureAfterCountdown()
                cont.resume()
            }
        }
    }

    private func cancelCountdownUI() async {
        countdownTick = nil
        countdownActive = false
        coordinator.closeCountdown()
    }

    func cancelCountdownFromUser() {
        countdownTask?.cancel()
        countdownTask = nil
        countdownTick = nil
        countdownActive = false
        coordinator.closeCountdown()
    }

    private func beginCaptureAfterCountdown() async {
        guard let source = selectedSource, source.hasSelection else { return }

        sessionTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        recording = true
        paused = false
        pausedElapsedOffset = 0
        sessionStartDate = Date()
        startElapsedTimer()

        let recordingsRoot = RecordingsDirectoryService.resolvedRecordingsDirectoryURL()
        RecordingsDirectoryService.accessResolvedDirectoryForWriting {
            try? FileManager.default.createDirectory(at: recordingsRoot, withIntermediateDirectories: true)
        }

        let mainName = "recording-\(sessionTimestamp).mp4"
        let videoURL = recordingsRoot.appendingPathComponent(mainName)

        var systemAudioURL: URL?
        var microphoneURL: URL?
        if systemAudioEnabled {
            systemAudioURL = recordingsRoot.appendingPathComponent("recording-\(sessionTimestamp).system.m4a")
        }
        if microphoneEnabled {
            microphoneURL = recordingsRoot.appendingPathComponent("recording-\(sessionTimestamp).mic.m4a")
        }

        let micDevice: String? = microphoneEnabled
            ? (microphoneDeviceID ?? AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            ).devices.first?.uniqueID)
            : nil

        let micLabel: String? = {
            guard let id = micDevice, !id.isEmpty else { return nil }
            return AVCaptureDevice(uniqueID: id)?.localizedName
        }()

        if webcamEnabled {
            let webcamURL = recordingsRoot.appendingPathComponent("recording-\(sessionTimestamp)-webcam.mov")
            let cam = WebcamMovieRecorder()
            webcamRecorder = cam
            do {
                try cam.startRecording(outputURL: webcamURL, deviceID: webcamDeviceID)
            } catch {
                webcamRecorder = nil
            }
        }

        let engine = ScreenCaptureRecordingEngine()
        engine.delegate = self
        recordingEngine = engine

        var displayID = source.displayID
        let windowID = source.windowID
        if source.kind == .screen, displayID == nil {
            displayID = CGMainDisplayID()
        }

        let config = NativeCaptureStartConfig(
            outputVideoURL: videoURL,
            systemAudioOutputURL: systemAudioURL,
            microphoneOutputURL: microphoneURL,
            capturesSystemAudio: systemAudioEnabled,
            capturesMicrophone: microphoneEnabled,
            microphoneDeviceID: micDevice,
            microphoneLabel: micLabel,
            displayID: displayID,
            windowID: windowID,
            fps: 60
        )

        do {
            try await engine.startCapture(config: config)
        } catch {
            recording = false
            recordingEngine = nil
            webcamRecorder?.cancelSession()
            webcamRecorder = nil
            elapsedTimer?.invalidate()
            updateElapsedLabel(0)
        }
    }

    private func stopRecording(switchToEditorAfter: Bool) async {
        guard recording else { return }

        let engine = recordingEngine
        recordingEngine = nil

        var webcamPath: URL?
        if let cam = webcamRecorder {
            webcamRecorder = nil
            webcamPath = await withCheckedContinuation { cont in
                cam.stopRecording { result in
                    switch result {
                    case let .success(url):
                        cont.resume(returning: url)
                    case .failure:
                        cont.resume(returning: nil)
                    }
                }
            }
        }

        guard let engine else { return }

        let rawVideoPath: String
        do {
            rawVideoPath = try await engine.stopCapture()
        } catch {
            recording = false
            elapsedTimer?.invalidate()
            return
        }

        await finalizeMuxAndHandoff(rawVideoPath: rawVideoPath, webcamPath: webcamPath, switchToEditorAfter: switchToEditorAfter)
    }

    private func finalizeMuxAndHandoff(rawVideoPath: String, webcamPath: URL?, switchToEditorAfter: Bool) async {
        recording = false
        paused = false
        elapsedTimer?.invalidate()
        updateElapsedLabel(0)

        let videoURL = URL(fileURLWithPath: rawVideoPath)
        let dir = videoURL.deletingLastPathComponent()
        let baseName = videoURL.deletingPathExtension().lastPathComponent

        let systemM4A = systemAudioEnabled ? dir.appendingPathComponent("\(baseName).system.m4a") : nil
        let micM4A = microphoneEnabled ? dir.appendingPathComponent("\(baseName).mic.m4a") : nil

        let finalURL = dir.appendingPathComponent("\(baseName)-final.mp4")
        do {
            try await MacRecordingMux.muxVideoWithAudioTracks(
                videoURL: videoURL,
                systemAudioURL: systemM4A,
                microphoneURL: micM4A,
                outputURL: finalURL
            )
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try? FileManager.default.removeItem(at: videoURL)
                if let s = systemM4A, FileManager.default.fileExists(atPath: s.path) { try? FileManager.default.removeItem(at: s) }
                if let m = micM4A, FileManager.default.fileExists(atPath: m.path) { try? FileManager.default.removeItem(at: m) }
            }
        } catch {
            // Keep original video if mux fails
        }

        let outputMain: URL
        if FileManager.default.fileExists(atPath: finalURL.path) {
            outputMain = finalURL
        } else {
            outputMain = videoURL
        }

        pendingMainVideoURL = outputMain
        pendingWebcamVideoURL = webcamPath

        if switchToEditorAfter {
            coordinator.switchToEditor()
        }
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let start = self.sessionStartDate, self.recording, !self.paused else { return }
                let elapsed = Date().timeIntervalSince(start)
                self.updateElapsedLabel(elapsed)
            }
        }
        if let t = elapsedTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    private func updateElapsedLabel(_ t: TimeInterval) {
        let total = Int(t)
        let m = total / 60
        let s = total % 60
        elapsedTimeString = String(format: "%02d:%02d", m, s)
    }
}

extension LaunchCaptureController: ScreenCaptureRecordingEngineDelegate {
    nonisolated func screenCaptureRecordingEngine(_ engine: ScreenCaptureRecordingEngine, didDetectCapturedWindowClosed videoPath: String) {
        Task { @MainActor in
            self.recordingEngine = nil

            var webcamPath: URL?
            if let cam = self.webcamRecorder {
                self.webcamRecorder = nil
                webcamPath = await withCheckedContinuation { cont in
                    cam.stopRecording { result in
                        switch result {
                        case let .success(url):
                            cont.resume(returning: url)
                        case .failure:
                            cont.resume(returning: nil)
                        }
                    }
                }
            }

            await self.finalizeMuxAndHandoff(rawVideoPath: videoPath, webcamPath: webcamPath, switchToEditorAfter: false)

            let alert = NSAlert()
            alert.messageText = "Captured window closed"
            alert.informativeText = "The window being recorded is no longer available."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()

            self.coordinator.openSourceSelector()
        }
    }
}
