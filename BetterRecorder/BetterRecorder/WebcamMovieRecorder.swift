//
//  WebcamMovieRecorder.swift
//  BetterRecorder
//
//  Optional webcam file alongside screen capture (Electron records a separate WebM; native uses MOV).
//

import AVFoundation
import Foundation

final class WebcamMovieRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var completion: ((Result<URL, Error>) -> Void)?
    private var isPausedState = false

    func startRecording(outputURL: URL, deviceID: String?) throws {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let device = resolveDevice(deviceID: deviceID) else {
            throw NSError(domain: "BetterRecorder", code: 40, userInfo: [NSLocalizedDescriptionKey: "No webcam available"])
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "BetterRecorder", code: 41, userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input"])
        }
        session.addInput(input)

        guard session.canAddOutput(movieOutput) else {
            throw NSError(domain: "BetterRecorder", code: 42, userInfo: [NSLocalizedDescriptionKey: "Cannot add movie output"])
        }
        session.addOutput(movieOutput)

        session.commitConfiguration()

        try? FileManager.default.removeItem(at: outputURL)
        session.startRunning()

        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
    }

    func stopRecording(completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        } else {
            session.stopRunning()
            completion(.failure(NSError(domain: "BetterRecorder", code: 43, userInfo: [NSLocalizedDescriptionKey: "Webcam was not recording"])))
        }
    }

    func pause() {
        guard movieOutput.isRecording, !isPausedState else { return }
        movieOutput.pauseRecording()
        isPausedState = true
    }

    func resume() {
        guard movieOutput.isRecording, isPausedState else { return }
        movieOutput.resumeRecording()
        isPausedState = false
    }

    func cancelSession() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        session.stopRunning()
        completion = nil
    }

    private func resolveDevice(deviceID: String?) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        let devices = discovery.devices
        if let id = deviceID, let match = devices.first(where: { $0.uniqueID == id }) {
            return match
        }
        return devices.first
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {}

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        isPausedState = false
        session.stopRunning()
        if let error {
            completion?(.failure(error))
        } else {
            completion?(.success(outputFileURL))
        }
        completion = nil
    }
}
