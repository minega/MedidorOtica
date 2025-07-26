//
//  DepthUtils.swift
//  MedidorOticaApp
//
//  Utilidades para leitura de profundidade e cálculo de pontos médios.
//

import ARKit
import CoreGraphics
import Vision
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

    /// Retorna a largura e altura considerando a orientação fornecida.
    func orientedDimensions(for buffer: CVPixelBuffer,
                            orientation: CGImagePropertyOrientation) -> (width: Int, height: Int) {
        let rawWidth = CVPixelBufferGetWidth(buffer)
        let rawHeight = CVPixelBufferGetHeight(buffer)
        return orientation.isPortrait ? (rawHeight, rawWidth) : (rawWidth, rawHeight)
    }

    /// Versão para `CGImage`.
    func orientedDimensions(for image: CGImage,
                            orientation: CGImagePropertyOrientation) -> (Int, Int) {
        let rawWidth = image.width
        let rawHeight = image.height
        return orientation.isPortrait ? (rawHeight, rawWidth) : (rawWidth, rawHeight)
    }

    /// Converte um ponto de pixel em coordenadas normalizadas de tela.
    func normalizedPoint(_ pixelPoint: CGPoint,
                         width: Int,
                         height: Int,
                         orientation: CGImagePropertyOrientation) -> CGPoint {
        var point = CGPoint(x: pixelPoint.x / CGFloat(width),
                            y: pixelPoint.y / CGFloat(height))
        point.y = 1 - point.y
        if orientation.isMirrored { point.x = 1 - point.x }
        return point
    }

    /// Cria uma `VNDetectFaceLandmarksRequest` com a revisão mais recente.
    /// - Returns: Requisição configurada para iOS 17 ou superior.
    func makeLandmarksRequest() -> VNDetectFaceLandmarksRequest {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        return request
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

extension CGImagePropertyOrientation {
    /// Converte `UIImage.Orientation` em `CGImagePropertyOrientation`.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }

    /// Indica se a orientação é vertical
    var isPortrait: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        default:
            return false
        }
    }

    /// Indica se a orientação é espelhada horizontalmente
    var isMirrored: Bool {
        switch self {
        case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored:
            return true
        default:
            return false
        }
    }
}
