//
//  CameraType.swift
//  MedidorOticaApp
//
//  Enum que define qual câmera utilizar (frontal ou traseira).
//

import Foundation

/// Tipos de câmera suportados pelo aplicativo
enum CameraType {
    case front    // Câmera frontal (TrueDepth)
    case back     // Câmera traseira (LiDAR)
}

