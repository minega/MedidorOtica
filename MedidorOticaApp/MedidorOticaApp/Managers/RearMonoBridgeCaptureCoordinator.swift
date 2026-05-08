//
//  RearMonoBridgeCaptureCoordinator.swift
//  MedidorOticaApp
//
//  Coordena frames da camera traseira principal para o modo Mono com escala manual pela ponte.
//

import AVFoundation
import CoreMedia
import ImageIO

// MARK: - Coordenador Mono
/// Entrega frames RGB da camera principal traseira sem ativar LiDAR ou depth por camera dupla.
final class RearMonoBridgeCaptureCoordinator: NSObject {
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let callbackQueue = DispatchQueue(label: "com.oticaManzolli.rearMono.video",
                                              qos: .userInitiated)
    private var frameHandler: ((RearMonoBridgeFrame) -> Void)?

    /// Configura a sessao para receber video da camera principal traseira.
    func configure(session: AVCaptureSession,
                   device: AVCaptureDevice,
                   frameHandler: @escaping (RearMonoBridgeFrame) -> Void) -> Bool {
        self.frameHandler = frameHandler

        guard session.canAddOutput(videoDataOutput) else {
            return false
        }

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        session.addOutput(videoDataOutput)
        videoDataOutput.setSampleBufferDelegate(self, queue: callbackQueue)

        configureMainCamera(device)
        return true
    }

    /// Limpa o delegate antes de parar a sessao.
    func reset() {
        videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
        frameHandler = nil
    }

    private func configureMainCamera(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }

            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }

            device.videoZoomFactor = 1.0
            device.unlockForConfiguration()
        } catch {
            print("ERRO: nao foi possivel configurar camera Mono traseira: \(error)")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension RearMonoBridgeCaptureCoordinator: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let frame = RearMonoBridgeFrame(pixelBuffer: pixelBuffer,
                                        timestamp: timestamp,
                                        cgOrientation: VerificationManager.shared.currentCGOrientation())
        frameHandler?(frame)
    }
}

// MARK: - Concurrency
/// O coordenador usa fila serial propria para callbacks da camera.
extension RearMonoBridgeCaptureCoordinator: @unchecked Sendable {}
