//
//  DepthUtils.swift
//  MedidorOticaApp
//
//  Utilidades para leitura de profundidade e cálculo de pontos médios.
//

import ARKit
import CoreGraphics
import UIKit

extension VerificationManager {
    // MARK: - Utilidades de Profundidade
    /// Retorna a profundidade em um ponto específico do depth map.
    func depthValue(from depthMap: CVPixelBuffer, at point: CGPoint) -> Float? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard point.x >= 0, point.x < CGFloat(width),
              point.y >= 0, point.y < CGFloat(height) else { return nil }

        guard CVPixelBufferLockBaseAddress(depthMap, .readOnly) == kCVReturnSuccess,
              let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let offset = Int(point.y) * bytesPerRow + Int(point.x) * MemoryLayout<Float>.size
        guard offset + MemoryLayout<Float>.size <= CVPixelBufferGetDataSize(depthMap) else { return nil }

        let value = base.load(fromByteOffset: offset, as: Float.self)
        return value.isFinite ? value : nil
    }

    /// Calcula o ponto médio de uma lista de pontos normalizados.
    func averagePoint(from points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }

        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }

        return CGPoint(x: sumX / CGFloat(points.count),
                       y: sumY / CGFloat(points.count))
    }

    /// Retorna a orientação atual considerando a posição da câmera
    func currentCGOrientation() -> CGImagePropertyOrientation {
        let position = CameraManager.shared.cameraPosition

        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return position == .front ? .downMirrored : .up
        case .landscapeRight:
            return position == .front ? .upMirrored : .down
        case .portraitUpsideDown:
            return position == .front ? .rightMirrored : .left
        default:
            return position == .front ? .leftMirrored : .right
        }
    }

    /// Orientação atual para projeção de pontos na tela
    func currentUIOrientation() -> UIInterfaceOrientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft:  return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }

    /// Ajusta os desvios horizontal e vertical conforme a orientação do dispositivo
    /// - Parameters:
    ///   - horizontal: Desvio horizontal em centímetros
    ///   - vertical: Desvio vertical em centímetros
    /// - Returns: Desvios adaptados à orientação atual
    func adjustOffsets(horizontal: Float, vertical: Float) -> (Float, Float) {
        // Orientação travada em retrato, não é necessário ajustar os eixos
        return (horizontal, vertical)
    }
}
