//
//  CapturedPhoto.swift
//  MedidorOticaApp
//
//  Estrutura que encapsula a imagem capturada e os dados de calibracao associados.
//

import UIKit
import ImageIO

// MARK: - Origem da escala
/// Define como a foto deve resolver a escala final no pos-captura.
enum CaptureScaleSource: String, Codable, Equatable {
    case sensorDepth
    case manualBridge
}

/// Representa uma captura realizada pela camera, incluindo a imagem e os dados de calibracao.
struct CapturedPhoto {
    /// Imagem final fornecida para o fluxo pos-captura.
    let image: UIImage
    /// Calibracao utilizada para converter valores normalizados em milimetros.
    let calibration: PostCaptureCalibration
    /// Mapa local da escala facial para compensar deformacoes de perspectiva.
    let localCalibration: LocalFaceScaleCalibration
    /// PC projetado no frame capturado para reduzir vies lateral no pos-captura.
    let captureCentralPoint: NormalizedPoint?
    /// Snapshot 3D dos olhos utilizado para converter DNP perto em DNP longe.
    let eyeGeometrySnapshot: CaptureEyeGeometrySnapshot?
    /// Timestamp do frame utilizado na captura.
    let frameTimestamp: TimeInterval
    /// Orientacao aplicada ao frame final entregue para o pos-captura.
    let orientation: CGImagePropertyOrientation
    /// Aviso opcional exibido no pos-captura quando a foto exige revisao extra.
    let captureWarning: String?
    /// Origem da escala usada para calcular as medidas finais.
    let scaleSource: CaptureScaleSource

    /// Inicializa a captura preservando metadados uteis para auditoria futura.
    init(image: UIImage,
         calibration: PostCaptureCalibration,
         localCalibration: LocalFaceScaleCalibration = .empty,
         captureCentralPoint: NormalizedPoint? = nil,
         eyeGeometrySnapshot: CaptureEyeGeometrySnapshot? = nil,
         frameTimestamp: TimeInterval = 0,
         orientation: CGImagePropertyOrientation = .up,
         captureWarning: String? = nil,
         scaleSource: CaptureScaleSource = .sensorDepth) {
        self.image = image
        self.calibration = calibration
        self.localCalibration = localCalibration
        self.captureCentralPoint = captureCentralPoint
        self.eyeGeometrySnapshot = eyeGeometrySnapshot
        self.frameTimestamp = frameTimestamp
        self.orientation = orientation
        self.captureWarning = captureWarning
        self.scaleSource = scaleSource
    }
}
