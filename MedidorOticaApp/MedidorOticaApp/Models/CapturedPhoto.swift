//
//  CapturedPhoto.swift
//  MedidorOticaApp
//
//  Estrutura que encapsula a imagem capturada e os dados de calibração associados.
//

import UIKit
import ImageIO

/// Representa uma captura realizada pela câmera, incluindo a imagem e os dados de calibração.
struct CapturedPhoto {
    /// Imagem final fornecida para o fluxo pós-captura.
    let image: UIImage
    /// Calibração utilizada para converter valores normalizados em milímetros.
    let calibration: PostCaptureCalibration
    /// Mapa local da escala facial para compensar deformações de perspectiva.
    let localCalibration: LocalFaceScaleCalibration
    /// Timestamp do frame utilizado na captura.
    let frameTimestamp: TimeInterval
    /// Orientação aplicada ao frame final entregue para o pós-captura.
    let orientation: CGImagePropertyOrientation
    /// Aviso opcional exibido no pós-captura quando a foto exige revisão extra.
    let captureWarning: String?

    /// Inicializa a captura preservando metadados úteis para auditoria futura.
    init(image: UIImage,
         calibration: PostCaptureCalibration,
         localCalibration: LocalFaceScaleCalibration = .empty,
         frameTimestamp: TimeInterval = 0,
         orientation: CGImagePropertyOrientation = .up,
         captureWarning: String? = nil) {
        self.image = image
        self.calibration = calibration
        self.localCalibration = localCalibration
        self.frameTimestamp = frameTimestamp
        self.orientation = orientation
        self.captureWarning = captureWarning
    }
}
