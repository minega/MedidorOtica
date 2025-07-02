//
//  CameraManager+CapturaFoto.swift
//  MedidorOticaApp
//
//  Extensão que controla a captura de fotos utilizando ARKit ou AVCaptureSession.
//

import AVFoundation
import UIKit
import ARKit

extension CameraManager {
    // MARK: - Captura de Foto
    /// Captura uma foto utilizando ARKit ou AVCaptureSession.
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        if isUsingARSession {
            captureARPhoto(completion: completion)
        } else {
            captureAVPhoto(completion: completion)
        }
    }

    private func captureARPhoto(completion: @escaping (UIImage?) -> Void) {
        guard let frame = arSession?.currentFrame else {
            print("ERRO: Não foi possível obter o frame atual da sessão AR")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        outputDelegate?(frame)

        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("ERRO: Falha ao criar CGImage a partir do buffer de pixel")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let image = UIImage(cgImage: cgImage)
        print("Imagem capturada da sessão AR com sucesso")
        DispatchQueue.main.async { completion(image) }
    }

    private func captureAVPhoto(completion: @escaping (UIImage?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.session.isRunning, self.videoDeviceInput != nil else {
                print("Erro: Sessão não está em execução ou input não configurado")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let settings = self.createPhotoSettings()

            let processor = PhotoCaptureProcessor { [weak self] image in
                self?.handleCapturedPhoto(image: image, completion: completion)
            }

            self.currentPhotoCaptureProcessor = processor
            self.videoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    private func createPhotoSettings() -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()

        if let device = videoDeviceInput?.device, device.isFlashAvailable {
            settings.flashMode = isFlashOn ? .on : .off
            print("Flash configurado: \(isFlashOn ? \"ligado\" : \"desligado\")")
        }

        return settings
    }

    private func handleCapturedPhoto(image: UIImage?, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.currentPhotoCaptureProcessor = nil
            print(image != nil ? "Foto capturada com sucesso" : "Falha ao capturar foto")
            completion(image)
        }
    }
}

// MARK: - Photo Capture Processor
private class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private var selfRetain: PhotoCaptureProcessor?
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
        super.init()
        self.selfRetain = self
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { selfRetain = nil }

        if let error = error {
            print("Erro ao processar foto: \(error.localizedDescription)")
            completion(nil)
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("Falha ao processar imagem")
            completion(nil)
            return
        }

        completion(image)
    }
}
