//
//  ScreenCaptureRecordingEngine.swift
//  BetterRecorder
//
//  Ported from Recordly `electron/native/ScreenCaptureKitRecorder.swift` (in-process, no CLI).
//

import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

private let targetCaptureFPS = 60

struct NativeCaptureStartConfig: Sendable {
    var outputVideoURL: URL
    var systemAudioOutputURL: URL?
    var microphoneOutputURL: URL?
    var capturesSystemAudio: Bool
    var capturesMicrophone: Bool
    var microphoneDeviceID: String?
    var microphoneLabel: String?
    var displayID: CGDirectDisplayID?
    var windowID: CGWindowID?
    var fps: Int
}

protocol ScreenCaptureRecordingEngineDelegate: AnyObject {
    func screenCaptureRecordingEngine(_ engine: ScreenCaptureRecordingEngine, didDetectCapturedWindowClosed videoPath: String)
}

/// Native ScreenCaptureKit + AVAssetWriter session (macOS), matching the Electron helper behavior.
final class ScreenCaptureRecordingEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    weak var delegate: ScreenCaptureRecordingEngineDelegate?

    private let queue = DispatchQueue(label: "betterrecorder.screencapturekit.video")
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioWriter: AVAssetWriter?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneOnlyWriter: AVAssetWriter?
    private var microphoneOnlyInput: AVAssetWriterInput?
    private var stream: SCStream?
    private var firstSampleTime: CMTime = .zero
    private var firstSystemAudioSampleTime: CMTime?
    private var firstMicrophoneSampleTime: CMTime?
    private var lastSampleBuffer: CMSampleBuffer?
    private var lastVideoPresentationTime: CMTime = .zero
    private var lastVideoDuration: CMTime = .zero
    private var isRecording = false
    private var isPaused = false
    private var pauseStartedHostTime: CMTime?
    private var pendingResumeAdjustment = false
    private var accumulatedPausedDuration: CMTime = .zero
    private var sessionStarted = false
    private var frameCount = 0
    private var outputURL: URL?
    private var microphoneOutputURL: URL?
    private var trackedWindowId: UInt32?
    private var windowValidationTask: Task<Void, Never>?
    private var capturesSystemAudio = false
    private var capturesMicrophone = false
    private var writesSystemAudioToSeparateTrack = false
    private var writesMicrophoneToSeparateTrack = false

    private let microphoneOutputTypeRawValue = 2

    func startCapture(config: NativeCaptureStartConfig) async throws {
        guard !isRecording else {
            throw NSError(domain: "BetterRecorderCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recording is already in progress"])
        }

        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let streamConfig = SCStreamConfiguration()
        capturesSystemAudio = config.capturesSystemAudio
        capturesMicrophone = config.capturesMicrophone

        if capturesMicrophone && !supportsNativeMicrophoneCapture(streamConfig: streamConfig) {
            throw NSError(
                domain: "BetterRecorderCapture",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Microphone capture requires a newer macOS / ScreenCaptureKit runtime"]
            )
        }

        writesSystemAudioToSeparateTrack = capturesSystemAudio
        writesMicrophoneToSeparateTrack = capturesSystemAudio && capturesMicrophone
        if capturesMicrophone && !capturesSystemAudio {
            writesMicrophoneToSeparateTrack = true
        }

        let requestedFPS = max(targetCaptureFPS, config.fps)
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(requestedFPS))
        streamConfig.queueDepth = 6
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.showsCursor = false
        streamConfig.capturesAudio = capturesSystemAudio || capturesMicrophone
        streamConfig.sampleRate = 48_000
        streamConfig.channelCount = 2
        streamConfig.excludesCurrentProcessAudio = true

        if capturesMicrophone {
            streamConfig.setValue(true, forKey: "captureMicrophone")
            if let microphoneDeviceID = Self.resolveMicrophoneCaptureDeviceID(deviceID: config.microphoneDeviceID, label: config.microphoneLabel) {
                streamConfig.setValue(microphoneDeviceID, forKey: "microphoneCaptureDeviceID")
            }
        }

        let filter: SCContentFilter
        let outputWidth: Int
        let outputHeight: Int

        if let windowID = config.windowID {
            trackedWindowId = UInt32(windowID)
            guard let window = availableContent.windows.first(where: { $0.windowID == windowID }) else {
                throw NSError(domain: "BetterRecorderCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "Window not found"])
            }

            filter = SCContentFilter(desktopIndependentWindow: window)

            let candidateDisplay = availableContent.displays.first(where: {
                $0.frame.intersects(window.frame) || $0.frame.contains(CGPoint(x: window.frame.midX, y: window.frame.midY))
            })
            let scaleFactor = Self.scaleFactor(for: candidateDisplay?.displayID ?? CGMainDisplayID())
            outputWidth = max(2, Int(window.frame.width) * scaleFactor)
            outputHeight = max(2, Int(window.frame.height) * scaleFactor)
            streamConfig.ignoreShadowsSingleWindow = true
            streamConfig.width = outputWidth
            streamConfig.height = outputHeight
        } else {
            trackedWindowId = nil
            let displayId = config.displayID ?? CGMainDisplayID()
            guard let display = availableContent.displays.first(where: { $0.displayID == displayId }) else {
                throw NSError(domain: "BetterRecorderCapture", code: 4, userInfo: [NSLocalizedDescriptionKey: "Display not found"])
            }

            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let displayBounds = CGDisplayBounds(display.displayID)
            let scaleFactor = Self.scaleFactor(for: display.displayID)
            outputWidth = max(2, Int(displayBounds.width) * scaleFactor)
            outputHeight = max(2, Int(displayBounds.height) * scaleFactor)
            streamConfig.width = outputWidth
            streamConfig.height = outputHeight
        }

        let destinationURL = config.outputVideoURL
        outputURL = destinationURL
        let outputFileType: AVFileType = destinationURL.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        assetWriter = try AVAssetWriter(url: destinationURL, fileType: outputFileType)
        microphoneOutputURL = nil
        firstSystemAudioSampleTime = nil
        firstMicrophoneSampleTime = nil

        guard let assistant = AVOutputSettingsAssistant(preset: .preset3840x2160) else {
            throw NSError(domain: "BetterRecorderCapture", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unable to create output settings assistant"])
        }

        assistant.sourceVideoFormat = try CMVideoFormatDescription(
            videoCodecType: .h264,
            width: outputWidth,
            height: outputHeight
        )

        guard var outputSettings = assistant.videoSettings else {
            throw NSError(domain: "BetterRecorderCapture", code: 6, userInfo: [NSLocalizedDescriptionKey: "Output settings unavailable"])
        }

        outputSettings[AVVideoWidthKey] = outputWidth
        outputSettings[AVVideoHeightKey] = outputHeight

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        videoInput.expectsMediaDataInRealTime = true

        guard let assetWriter = assetWriter, assetWriter.canAdd(videoInput) else {
            throw NSError(domain: "BetterRecorderCapture", code: 7, userInfo: [NSLocalizedDescriptionKey: "Unable to add video writer input"])
        }

        assetWriter.add(videoInput)
        self.videoInput = videoInput

        if writesSystemAudioToSeparateTrack {
            guard let systemAudioOutputPath = config.systemAudioOutputURL else {
                throw NSError(domain: "BetterRecorderCapture", code: 11, userInfo: [NSLocalizedDescriptionKey: "Missing system audio output URL"])
            }

            let systemAudioURL = systemAudioOutputPath
            let systemAudioWriter = try AVAssetWriter(url: systemAudioURL, fileType: .m4a)
            let systemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioOutputSettings(bitRate: 160_000))
            systemAudioInput.expectsMediaDataInRealTime = true

            guard systemAudioWriter.canAdd(systemAudioInput) else {
                throw NSError(domain: "BetterRecorderCapture", code: 12, userInfo: [NSLocalizedDescriptionKey: "Unable to add system audio writer input"])
            }

            systemAudioWriter.add(systemAudioInput)
            self.systemAudioWriter = systemAudioWriter
            self.systemAudioInput = systemAudioInput

            guard systemAudioWriter.startWriting() else {
                throw NSError(domain: "BetterRecorderCapture", code: 13, userInfo: [NSLocalizedDescriptionKey: systemAudioWriter.error?.localizedDescription ?? "Unable to start system audio writing"])
            }

            systemAudioWriter.startSession(atSourceTime: .zero)
        }

        if writesMicrophoneToSeparateTrack {
            guard let microphoneOutputPath = config.microphoneOutputURL else {
                throw NSError(domain: "BetterRecorderCapture", code: 14, userInfo: [NSLocalizedDescriptionKey: "Missing microphone output URL"])
            }

            microphoneOutputURL = microphoneOutputPath
            let microphoneWriter = try AVAssetWriter(url: microphoneOutputPath, fileType: .m4a)
            let microphoneInput = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioOutputSettings(bitRate: 128_000))
            microphoneInput.expectsMediaDataInRealTime = true

            guard microphoneWriter.canAdd(microphoneInput) else {
                throw NSError(domain: "BetterRecorderCapture", code: 15, userInfo: [NSLocalizedDescriptionKey: "Unable to add microphone writer input"])
            }

            microphoneWriter.add(microphoneInput)
            microphoneOnlyWriter = microphoneWriter
            microphoneOnlyInput = microphoneInput

            guard microphoneWriter.startWriting() else {
                throw NSError(domain: "BetterRecorderCapture", code: 16, userInfo: [NSLocalizedDescriptionKey: microphoneWriter.error?.localizedDescription ?? "Unable to start microphone audio writing"])
            }

            microphoneWriter.startSession(atSourceTime: .zero)
        }

        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if capturesSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        if capturesMicrophone {
            guard let microphoneOutputType = SCStreamOutputType(rawValue: microphoneOutputTypeRawValue) else {
                throw NSError(domain: "BetterRecorderCapture", code: 17, userInfo: [NSLocalizedDescriptionKey: "Microphone stream output type is unavailable"])
            }
            try stream.addStreamOutput(self, type: microphoneOutputType, sampleHandlerQueue: queue)
        }
        try await stream.startCapture()

        guard assetWriter.startWriting() else {
            throw NSError(domain: "BetterRecorderCapture", code: 8, userInfo: [NSLocalizedDescriptionKey: assetWriter.error?.localizedDescription ?? "Unable to start video writing"])
        }

        assetWriter.startSession(atSourceTime: .zero)
        sessionStarted = true
        isRecording = true
        isPaused = false
        pauseStartedHostTime = nil
        pendingResumeAdjustment = false
        accumulatedPausedDuration = .zero
        frameCount = 0
        firstSampleTime = .zero
        lastVideoPresentationTime = .zero
        lastVideoDuration = .zero
        startWindowValidationIfNeeded()
    }

    func stopCapture() async throws -> String {
        guard isRecording else {
            throw NSError(domain: "BetterRecorderCapture", code: 9, userInfo: [NSLocalizedDescriptionKey: "No recording in progress"])
        }
        return try await finishCapture()
    }

    func pauseCapture() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        pauseStartedHostTime = CMClockGetTime(CMClockGetHostTimeClock())
        pendingResumeAdjustment = false
    }

    func resumeCapture() {
        guard isRecording, isPaused else { return }
        isPaused = false
        pendingResumeAdjustment = true
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sessionStarted, sampleBuffer.isValid, isRecording else { return }
        guard let presentationTime = adjustedPresentationTime(for: sampleBuffer, outputType: outputType) else { return }

        if outputType == .screen {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let attachment = attachments.first,
                  let statusRawValue = attachment[SCStreamFrameInfo.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRawValue),
                  status == .complete else {
                return
            }

            guard let videoInput = videoInput, videoInput.isReadyForMoreMediaData else { return }

            if firstSampleTime == .zero {
                firstSampleTime = sampleBuffer.presentationTimeStamp
            }

            lastSampleBuffer = sampleBuffer
            let timing = CMSampleTimingInfo(duration: sampleBuffer.duration, presentationTimeStamp: presentationTime, decodeTimeStamp: sampleBuffer.decodeTimeStamp)
            if let retimedSampleBuffer = try? CMSampleBuffer(copying: sampleBuffer, withNewTiming: [timing]) {
                videoInput.append(retimedSampleBuffer)
                lastVideoPresentationTime = presentationTime
                lastVideoDuration = sampleBuffer.duration
                frameCount += 1
            }
            return
        }

        if outputType == .audio {
            guard let systemAudioInput else { return }
            appendAudioSampleBuffer(sampleBuffer, to: systemAudioInput, firstSampleTime: &firstSystemAudioSampleTime, presentationTime: presentationTime)
            return
        }

        if outputType.rawValue == microphoneOutputTypeRawValue {
            if let microphoneOnlyInput {
                appendAudioSampleBuffer(sampleBuffer, to: microphoneOnlyInput, firstSampleTime: &firstMicrophoneSampleTime, presentationTime: presentationTime)
            }
            return
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Stream errors are surfaced when stopping capture.
    }

    private func finishCapture() async throws -> String {
        windowValidationTask?.cancel()
        windowValidationTask = nil
        trackedWindowId = nil

        isRecording = false
        if let activeStream = stream {
            do {
                try await activeStream.stopCapture()
            } catch {
                // Stream may have already been stopped by the system.
            }
        }
        stream = nil

        if let originalBuffer = lastSampleBuffer, let videoInput = videoInput {
            let additionalTime = lastVideoPresentationTime + frameDuration(for: originalBuffer)
            let timing = CMSampleTimingInfo(duration: originalBuffer.duration, presentationTimeStamp: additionalTime, decodeTimeStamp: originalBuffer.decodeTimeStamp)
            if let additionalSampleBuffer = try? CMSampleBuffer(copying: originalBuffer, withNewTiming: [timing]) {
                videoInput.append(additionalSampleBuffer)
            }
        }

        assetWriter?.endSession(atSourceTime: lastSampleBuffer?.presentationTimeStamp ?? .zero)
        videoInput?.markAsFinished()
        await assetWriter?.finishWriting()

        systemAudioInput?.markAsFinished()
        await systemAudioWriter?.finishWriting()

        microphoneOnlyInput?.markAsFinished()
        await microphoneOnlyWriter?.finishWriting()

        let path = outputURL?.path ?? ""
        assetWriter = nil
        videoInput = nil
        systemAudioWriter = nil
        systemAudioInput = nil
        microphoneOnlyWriter = nil
        microphoneOnlyInput = nil
        outputURL = nil
        microphoneOutputURL = nil
        sessionStarted = false
        firstSampleTime = .zero
        firstSystemAudioSampleTime = nil
        firstMicrophoneSampleTime = nil
        lastSampleBuffer = nil
        lastVideoPresentationTime = .zero
        lastVideoDuration = .zero
        frameCount = 0
        isPaused = false
        pauseStartedHostTime = nil
        pendingResumeAdjustment = false
        accumulatedPausedDuration = .zero
        capturesSystemAudio = false
        capturesMicrophone = false
        writesSystemAudioToSeparateTrack = false
        writesMicrophoneToSeparateTrack = false
        return path
    }

    private func adjustedPresentationTime(for sampleBuffer: CMSampleBuffer, outputType: SCStreamOutputType) -> CMTime? {
        if isPaused {
            return nil
        }

        let sampleTime = sampleBuffer.presentationTimeStamp
        if pendingResumeAdjustment, let pauseStartedHostTime {
            let pauseGap = sampleTime - pauseStartedHostTime
            if pauseGap > .zero {
                accumulatedPausedDuration = accumulatedPausedDuration + pauseGap
            }
            self.pauseStartedHostTime = nil
            pendingResumeAdjustment = false
        }

        if outputType == .screen {
            if firstSampleTime == .zero {
                firstSampleTime = sampleTime
            }
            return max(.zero, sampleTime - firstSampleTime - accumulatedPausedDuration)
        }

        return sampleTime - accumulatedPausedDuration
    }

    private func frameDuration(for sampleBuffer: CMSampleBuffer) -> CMTime {
        if sampleBuffer.duration.isValid && sampleBuffer.duration > .zero {
            return sampleBuffer.duration
        }

        if lastVideoDuration.isValid && lastVideoDuration > .zero {
            return lastVideoDuration
        }

        return CMTime(value: 1, timescale: CMTimeScale(targetCaptureFPS))
    }

    private func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput, firstSampleTime: inout CMTime?, presentationTime: CMTime) {
        guard input.isReadyForMoreMediaData else { return }

        if firstSampleTime == nil {
            firstSampleTime = presentationTime
        }

        guard let firstSampleTime else { return }
        let relativePresentationTime = max(.zero, presentationTime - firstSampleTime)
        let timing = CMSampleTimingInfo(duration: sampleBuffer.duration, presentationTimeStamp: relativePresentationTime, decodeTimeStamp: sampleBuffer.decodeTimeStamp)
        if let retimedSampleBuffer = try? CMSampleBuffer(copying: sampleBuffer, withNewTiming: [timing]) {
            input.append(retimedSampleBuffer)
        }
    }

    private static func audioOutputSettings(bitRate: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: bitRate,
        ]
    }

    private static func resolveMicrophoneCaptureDeviceID(deviceID: String?, label: String?) -> String? {
        let audioDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices

        if let microphoneLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines), !microphoneLabel.isEmpty {
            if let matchedDevice = audioDevices.first(where: { $0.localizedName == microphoneLabel }) {
                return matchedDevice.uniqueID
            }
        }

        if let microphoneDeviceId = deviceID?.trimmingCharacters(in: .whitespacesAndNewlines), !microphoneDeviceId.isEmpty {
            if audioDevices.contains(where: { $0.uniqueID == microphoneDeviceId }) {
                return microphoneDeviceId
            }
        }

        return nil
    }

    private func supportsNativeMicrophoneCapture(streamConfig: SCStreamConfiguration) -> Bool {
        let supportsConfigSelector = streamConfig.responds(to: Selector(("setCaptureMicrophone:")))
        let supportsDeviceSelector = streamConfig.responds(to: Selector(("setMicrophoneCaptureDeviceID:")))
        let supportsOutputType = SCStreamOutputType(rawValue: microphoneOutputTypeRawValue) != nil
        return supportsConfigSelector && supportsDeviceSelector && supportsOutputType
    }

    private func startWindowValidationIfNeeded() {
        guard let trackedWindowId else {
            windowValidationTask?.cancel()
            windowValidationTask = nil
            return
        }

        windowValidationTask?.cancel()
        windowValidationTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                guard self.isRecording else { return }

                do {
                    let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    let windowStillAvailable = availableContent.windows.contains(where: { $0.windowID == trackedWindowId })
                    if !windowStillAvailable {
                        let path = try await self.finishCapture()
                        await MainActor.run {
                            self.delegate?.screenCaptureRecordingEngine(self, didDetectCapturedWindowClosed: path)
                        }
                        return
                    }
                } catch {
                    continue
                }
            }
        }
    }

    private static func scaleFactor(for displayId: CGDirectDisplayID) -> Int {
        guard let mode = CGDisplayCopyDisplayMode(displayId) else {
            return 1
        }
        return max(1, mode.pixelWidth / max(1, mode.width))
    }
}
