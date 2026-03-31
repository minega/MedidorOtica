//
//  CapturedPhoto.swift
//  MedidorOticaApp
//
//  Estrutura que encapsula a imagem capturada e os dados de calibracao associados.
//

import UIKit
import ImageIO

/// Representa uma captura realizada pela camera, incluindo a imagem e os dados de calibracao.
struct CapturedPhoto {
    /// Imagem final fornecida para o fluxo pos-captura.
    let image: UIImage
    /// Calibracao utilizada para converter valores normalizados em milimetros.
    let calibration: PostCaptureCalibration
    /// Mapa local da escala facial para compensar deformacoes de perspectiva.
    let localCalibration: LocalFaceScaleCalibration
    /// Referencia legada da captura mantida apenas para auditoria e compatibilidade.
    /// O fluxo novo da pos-captura recalcula o PC exclusivamente a partir da foto estatica.
    let captureCentralPoint: NormalizedPoint?
    /// Timestamp do frame utilizado na captura.
    let frameTimestamp: TimeInterval
    /// Orientacao aplicada ao frame final entregue para o pos-captura.
    let orientation: CGImagePropertyOrientation
    /// Aviso opcional exibido no pos-captura quando a foto exige revisao extra.
    let captureWarning: String?

    /// Inicializa a captura preservando metadados uteis para auditoria futura.
    init(image: UIImage,
         calibration: PostCaptureCalibration,
         localCalibration: LocalFaceScaleCalibration = .empty,
         captureCentralPoint: NormalizedPoint? = nil,
         frameTimestamp: TimeInterval = 0,
         orientation: CGImagePropertyOrientation = .up,
         captureWarning: String? = nil) {
        self.image = image
        self.calibration = calibration
        self.localCalibration = localCalibration
        self.captureCentralPoint = captureCentralPoint
        self.frameTimestamp = frameTimestamp
        self.orientation = orientation
        self.captureWarning = captureWarning
    }
}
