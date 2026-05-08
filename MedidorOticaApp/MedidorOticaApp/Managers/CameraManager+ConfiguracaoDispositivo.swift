//
//  CameraManager+ConfiguracaoDispositivo.swift
//  MedidorOticaApp
//
//  Ajustes de hardware e compatibilidade com chamadas legadas.
//

import AVFoundation
import ARKit

extension CameraManager {
    // MARK: - Sessao AV legado
    /// Prepara uma `AVCaptureSession` apenas para caminhos legados fora da medicao.
    func setupSession(completion: @escaping (Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            self.stopSessionIfRunning()
            self.cleanupSession()

            var configurationSucceeded = true
            self.session.beginConfiguration()

            if self.session.canSetSessionPreset(.high) {
                self.session.sessionPreset = .high
            }

            if !self.configureVideoInput() {
                configurationSucceeded = false
            }

            if configurationSucceeded, !self.configurePhotoOutput() {
                configurationSucceeded = false
            }

            self.session.commitConfiguration()

            guard configurationSucceeded else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            self.startSession(completion: completion)
        }
    }

    /// Alterna entre o fluxo frontal TrueDepth e o fluxo traseiro LiDAR.
    func switchCamera() {
        let nextType: CameraType = cameraPosition == .front ? .back : .front
        startMeasurementSession(cameraType: nextType) { success in
            print(success ? "Camera alternada para \(nextType.sensorName)" : "Nao foi possivel alternar camera.")
        }
    }

    /// Liga ou desliga o flash, caso disponivel.
    func toggleFlash() {
        guard let device = videoDeviceInput?.device else { return }
        guard device.hasTorch, device.isTorchAvailable else {
            if isFlashOn { isFlashOn = false }
            return
        }

        do {
            try device.lockForConfiguration()
            isFlashOn.toggle()
            let mode: AVCaptureDevice.TorchMode = isFlashOn ? .on : .off
            guard device.isTorchModeSupported(mode) else {
                isFlashOn = (device.torchMode == .on)
                publishError(.deviceConfigurationFailed)
                device.unlockForConfiguration()
                return
            }
            device.torchMode = mode
            device.unlockForConfiguration()
        } catch {
            publishError(.deviceConfigurationFailed)
        }
    }

    /// Mantido para compatibilidade com chamadas antigas.
    func setup(position: AVCaptureDevice.Position,
               arSession: ARSession? = nil,
               completion: @escaping (Bool) -> Void) {
        let cameraType: CameraType = position == .front ? .front : .back
        startMeasurementSession(cameraType: cameraType, completion: completion)
    }

    // MARK: - Helpers
    private func stopSessionIfRunning() {
        if session.isRunning {
            session.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    private func configurePhotoOutput() -> Bool {
        guard session.canAddOutput(videoOutput) else {
            publishError(.cannotAddOutput)
            return false
        }

        session.addOutput(videoOutput)
        if #available(iOS 16, *) {
            videoOutput.maxPhotoDimensions = CMVideoDimensions(width: 0, height: 0)
        } else {
            videoOutput.isHighResolutionCaptureEnabled = true
        }

        if let connection = videoOutput.connection(with: .video) {
            connection.setPortraitOrientation()
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = (cameraPosition == .front)
            }
        }

        return true
    }

    private func startSession(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            self.session.startRunning()

            DispatchQueue.main.async {
                let started = self.session.isRunning
                self.isSessionRunning = started
                completion(started)
            }
        }
    }

    /// Retorna o dispositivo TrueDepth obrigatorio.
    func cameraDevice(for position: AVCaptureDevice.Position,
                      ignoringFrontOverride: Bool = false) -> AVCaptureDevice? {
        guard position == .front else { return nil }
        guard ignoringFrontOverride || isFrontCameraEnabled else { return nil }

        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera],
                                                                mediaType: .video,
                                                                position: .front)
        return discoverySession.devices.first
    }

    private func configureVideoInput() -> Bool {
        guard let videoDevice = cameraDevice(for: cameraPosition) else {
            publishError(.cameraUnavailable)
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: videoDevice)
            guard session.canAddInput(input) else {
                publishError(.cannotAddInput)
                return false
            }

            session.addInput(input)
            videoDeviceInput = input
            return true
        } catch {
            publishError(.createCaptureInput(error))
            return false
        }
    }
}
