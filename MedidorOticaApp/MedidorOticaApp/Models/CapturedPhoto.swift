//
//  CapturedPhoto.swift
//  MedidorOticaApp
//
//  Estrutura que encapsula a imagem capturada e os dados de calibração associados.
//

import UIKit

/// Representa uma captura realizada pela câmera, incluindo a imagem e os dados de calibração.
struct CapturedPhoto {
    /// Imagem final fornecida para o fluxo pós-captura.
    let image: UIImage
    /// Calibração utilizada para converter valores normalizados em milímetros.
    let calibration: PostCaptureCalibration
}
