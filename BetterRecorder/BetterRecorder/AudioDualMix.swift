//
//  AudioDualMix.swift
//  BetterRecorder
//
//  Mixes system + microphone M4A captures and muxes with screen MP4 (Electron `muxNativeMacRecordingWithAudio` equivalent).
//

import AVFoundation
import Foundation

enum MacRecordingMux {
    /// Final mux: H.264 video + optional mixed AAC (Electron `muxNativeMacRecordingWithAudio` equivalent).
    static func muxVideoWithAudioTracks(
        videoURL: URL,
        systemAudioURL: URL?,
        microphoneURL: URL?,
        outputURL: URL
    ) async throws {
        let hasSystem = systemAudioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let hasMic = microphoneURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        if !hasSystem && !hasMic {
            if videoURL != outputURL {
                try? FileManager.default.removeItem(at: outputURL)
                try FileManager.default.copyItem(at: videoURL, to: outputURL)
            }
            return
        }

        if hasSystem && !hasMic, let s = systemAudioURL {
            try await muxVideo(videoURL, singleAudio: s, outputURL: outputURL)
            return
        }

        if !hasSystem && hasMic, let m = microphoneURL {
            try await muxVideo(videoURL, singleAudio: m, outputURL: outputURL)
            return
        }

        guard hasSystem && hasMic, let s = systemAudioURL, let m = microphoneURL else {
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.copyItem(at: videoURL, to: outputURL)
            return
        }

        let tempMixed = videoURL.deletingLastPathComponent().appendingPathComponent("mixed-audio-\(UUID().uuidString).m4a")
        do {
            try await mixTwoM4AFiles(systemURL: s, microphoneURL: m, outputURL: tempMixed)
        } catch {
            try await muxVideo(videoURL, singleAudio: s, outputURL: outputURL)
            if FileManager.default.fileExists(atPath: m.path) { try? FileManager.default.removeItem(at: m) }
            return
        }
        defer { try? FileManager.default.removeItem(at: tempMixed) }

        try await muxVideo(videoURL, singleAudio: tempMixed, outputURL: outputURL)
    }

    private static func mixTwoM4AFiles(systemURL: URL, microphoneURL: URL, outputURL: URL) async throws {
        let sysFile = try AVAudioFile(forReading: systemURL)
        let micFile = try AVAudioFile(forReading: microphoneURL)

        let targetFormat = sysFile.processingFormat
        let micFormat = micFile.processingFormat
        guard micFormat.sampleRate == targetFormat.sampleRate,
              micFormat.channelCount == targetFormat.channelCount else {
            throw NSError(domain: "BetterRecorder", code: 10, userInfo: [NSLocalizedDescriptionKey: "Microphone and system audio format mismatch"])
        }

        sysFile.framePosition = 0
        micFile.framePosition = 0

        let frameCount = AVAudioFrameCount(min(sysFile.length, micFile.length))
        guard frameCount > 0,
              let sysBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount),
              let micBuf = AVAudioPCMBuffer(pcmFormat: micFormat, frameCapacity: frameCount),
              let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            throw NSError(domain: "BetterRecorder", code: 11, userInfo: [NSLocalizedDescriptionKey: "Buffer alloc failed"])
        }

        try sysFile.read(into: sysBuf)
        try micFile.read(into: micBuf)
        sysBuf.frameLength = frameCount
        micBuf.frameLength = frameCount

        let n = Int(frameCount)
        let ch = Int(targetFormat.channelCount)
        guard let sData = sysBuf.floatChannelData, let mData = micBuf.floatChannelData, let oData = outBuf.floatChannelData else {
            throw NSError(domain: "BetterRecorder", code: 12, userInfo: [NSLocalizedDescriptionKey: "PCM data unavailable"])
        }

        for c in 0..<ch {
            for i in 0..<n {
                oData[c][i] = (sData[c][i] + mData[c][i]) * 0.5
            }
        }
        outBuf.frameLength = frameCount

        let tempCaf = outputURL.deletingLastPathComponent().appendingPathComponent("mixed-pcm-\(UUID().uuidString).caf")
        try? FileManager.default.removeItem(at: tempCaf)
        let outFile = try AVAudioFile(forWriting: tempCaf, settings: targetFormat.settings)
        try outFile.write(from: outBuf)
        defer { try? FileManager.default.removeItem(at: tempCaf) }

        let asset = AVURLAsset(url: tempCaf)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "BetterRecorder", code: 13, userInfo: [NSLocalizedDescriptionKey: "Export session failed"])
        }
        try? FileManager.default.removeItem(at: outputURL)
        export.outputURL = outputURL
        export.outputFileType = .m4a
        await export.export()
        if export.status != .completed {
            throw export.error ?? NSError(domain: "BetterRecorder", code: 14, userInfo: nil)
        }
    }

    private static func muxVideo(_ videoURL: URL, singleAudio: URL, outputURL: URL) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: singleAudio)

        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        guard let vTrack = videoTracks.first, let aTrack = audioTracks.first else {
            throw NSError(domain: "BetterRecorder", code: 20, userInfo: [NSLocalizedDescriptionKey: "Missing tracks"])
        }

        let composition = AVMutableComposition()
        let vRange = try await vTrack.load(.timeRange)
        let aRange = try await aTrack.load(.timeRange)

        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "BetterRecorder", code: 21, userInfo: [NSLocalizedDescriptionKey: "Composition failed"])
        }

        try compVideo.insertTimeRange(vRange, of: vTrack, at: .zero)
        let audioInsert = CMTimeMinimum(aRange.duration, vRange.duration)
        try compAudio.insertTimeRange(
            CMTimeRange(start: .zero, duration: audioInsert),
            of: aTrack,
            at: .zero
        )

        try? FileManager.default.removeItem(at: outputURL)

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "BetterRecorder", code: 22, userInfo: [NSLocalizedDescriptionKey: "Export session failed"])
        }
        export.outputURL = outputURL
        export.outputFileType = .mp4
        await export.export()
        if export.status != .completed {
            throw export.error ?? NSError(domain: "BetterRecorder", code: 23, userInfo: nil)
        }
    }
}
