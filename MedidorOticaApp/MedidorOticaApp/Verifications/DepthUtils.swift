import ARKit
import CoreGraphics

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
}
