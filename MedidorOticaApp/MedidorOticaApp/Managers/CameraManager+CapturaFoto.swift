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
        let context = photoProcessingContext
        // Reaproveita a orientação calculada pelo VerificationManager para alinhar a foto ao preview
        let orientation = VerificationManager.shared.currentCGOrientation()
        let orientedCIImage = ciImage.oriented(forExifOrientation: orientation.exifOrientation)

        guard let cgImageFull = context.createCGImage(orientedCIImage, from: orientedCIImage.extent) else {
            print("ERRO: Falha ao criar CGImage a partir do buffer de pixel")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let width = CGFloat(cgImageFull.width)
        let height = CGFloat(cgImageFull.height)
        let viewSize = UIScreen.main.bounds.size
        var cropRect = AVMakeRect(aspectRatio: viewSize, insideRect: CGRect(x: 0, y: 0, width: width, height: height))
        cropRect.origin.x = (width - cropRect.width) / 2
        cropRect.origin.y = (height - cropRect.height) / 2

        guard let croppedCG = cgImageFull.cropping(to: cropRect) else {
            print("ERRO: Falha ao recortar a imagem capturada")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // Normaliza a orientação para manter a foto na vertical independente do sensor
        let image = UIImage(cgImage: croppedCG, scale: 1.0, orientation: .up)
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
            print("Flash configurado: \(isFlashOn ? "ligado" : "desligado")")
        }

        return settings
    }

    /// Recorta a imagem mantendo o mesmo enquadramento do preview.
    private func cropToScreenAspect(_ image: UIImage) -> UIImage {
        let screenSize = UIScreen.main.bounds.size
        guard let cg = image.cgImage else { return image }
        let imgSize = CGSize(width: CGFloat(cg.width),
                             height: CGFloat(cg.height))

        var cropRect = AVMakeRect(aspectRatio: screenSize,
                                  insideRect: CGRect(origin: .zero, size: imgSize))
        cropRect.origin.x = (imgSize.width - cropRect.width) / 2
        cropRect.origin.y = (imgSize.height - cropRect.height) / 2

        guard let croppedCG = cg.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: croppedCG,
                       scale: image.scale,
                       orientation: image.imageOrientation)
    }

    /// Ajusta a orientação EXIF para que a imagem final permaneça em pé.
    private func normalizeOrientation(of image: UIImage) -> UIImage {
        guard image.imageOrientation != .up,
              let cg = image.cgImage else { return image }

        let exifOrientation = CGImagePropertyOrientation(image.imageOrientation)
        let ciImage = CIImage(cgImage: cg).oriented(forExifOrientation: exifOrientation.exifOrientation)

        guard let orientedCG = photoProcessingContext.createCGImage(ciImage, from: ciImage.extent) else {
            return image
        }

        return UIImage(cgImage: orientedCG, scale: image.scale, orientation: .up)
    }

    private func handleCapturedPhoto(image: UIImage?, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.currentPhotoCaptureProcessor = nil

            guard let img = image else {
                print("Falha ao capturar foto")
                completion(nil)
                return
            }

            let normalized = self?.normalizeOrientation(of: img) ?? img
            let cropped = self?.cropToScreenAspect(normalized) ?? normalized
            print("Foto capturada com sucesso")
            completion(cropped)
        }
    }
}

// MARK: - Photo Capture Processor
final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
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
