//
//  RearDepthCaptureCoordinator.swift
//  MedidorOticaApp
//
//  Coordena video e AVDepthData sincronizados para o modo traseiro sem LiDAR.
//

import AVFoundation
import CoreMedia
import ImageIO

// MARK: - Coordenador AVDepthData
/// Configura e entrega frames sincronizados de RGB + profundidade.
final class RearDepthCaptureCoordinator: NSObject {
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private let callbackQueue = DispatchQueue(label: "com.oticaManzolli.rearDepth.sync",
                                              qos: .userInitiated)
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private var frameHandler: ((RearDepthFrame) -> Void)?

    /// Configura os outputs na sessao informada.
    func configure(session: AVCaptureSession,
                   device: AVCaptureDevice,
                   frameHandler: @escaping (RearDepthFrame) -> Void) -> Bool {
        self.frameHandler = frameHandler

        guard let selection = RearDepthFallbackMeasurementEngine.bestFormatSelection(for: device) else {
            return false
        }

        guard session.canAddOutput(videoDataOutput),
              session.canAddOutput(depthDataOutput) else {
            return false
        }

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        depthDataOutput.alwaysDiscardsLateDepthData = true
        depthDataOutput.isFilteringEnabled = true

        session.addOutput(videoDataOutput)
        session.addOutput(depthDataOutput)

        do {
            try device.lockForConfiguration()
            device.activeFormat = selection.videoFormat
            device.activeDepthDataFormat = selection.depthFormat
            device.unlockForConfiguration()
        } catch {
            print("ERRO: nao foi possivel definir formato de depth traseiro: \(error)")
            return false
        }

        synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [
            videoDataOutput,
            depthDataOutput
        ])
        synchronizer?.setDelegate(self, queue: callbackQueue)
        return true
    }

    /// Limpa referencias fortes para evitar callbacks depois de parar a camera.
    func reset() {
        synchronizer?.setDelegate(nil, queue: nil)
        synchronizer = nil
        frameHandler = nil
    }
}

// MARK: - AVCaptureDataOutputSynchronizerDelegate
extension RearDepthCaptureCoordinator: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard let syncedVideo = synchronizedDataCollection
            .synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData,
              let syncedDepth = synchronizedDataCollection
            .synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
              !syncedVideo.sampleBufferWasDropped,
              !syncedDepth.depthDataWasDropped,
              let pixelBuffer = CMSampleBufferGetImageBuffer(syncedVideo.sampleBuffer) else {
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(syncedVideo.sampleBuffer).seconds
        let frame = RearDepthFrame(pixelBuffer: pixelBuffer,
                                   depthData: syncedDepth.depthData,
                                   timestamp: timestamp,
                                   cgOrientation: VerificationManager.shared.currentCGOrientation())
        frameHandler?(frame)
    }
}

// MARK: - Concurrency
/// O coordenador entrega callbacks em fila serial propria.
extension RearDepthCaptureCoordinator: @unchecked Sendable {}
