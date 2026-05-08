//
//  CameraType.swift
//  MedidorOticaApp
//
//  Define os tipos de camera usados pelos fluxos de medicao.
//

import AVFoundation

/// Tipos de camera suportados pelo aplicativo.
enum CameraType {
    case front
    case back

    /// Nome curto do sensor usado na interface.
    var sensorName: String {
        switch self {
        case .front:
            return "TrueDepth"
        case .back:
            return "LiDAR"
        }
    }

    /// Posicao fisica da camera associada ao tipo.
    var capturePosition: AVCaptureDevice.Position {
        switch self {
        case .front:
            return .front
        case .back:
            return .back
        }
    }
}
