//
//  TrueDepthCalibrationEstimator.swift
//  MedidorOticaApp
//
//  Calcula calibrações submilimétricas a partir do sensor TrueDepth.
//

import Foundation
import ARKit
import simd

// MARK: - Estimador TrueDepth
/// Consolida amostras em mm/pixel diretamente a partir do TrueDepth, mantendo apenas leituras confiáveis.
final class TrueDepthCalibrationEstimator {

    // MARK: - Diagnósticos Públicos
    struct Diagnostics {
        let storedSampleCount: Int
        let recentSampleCount: Int
        let lastHorizontalMMPerPixel: Double?
        let lastVerticalMMPerPixel: Double?
        let lastDepthMM: Double?
        let lastBaselineError: Double?
    }

    // MARK: - Amostra Interna
    private struct CalibrationSample {
        let timestamp: TimeInterval
        let mmPerPixelX: Double
        let mmPerPixelY: Double
        let depthMeters: Double
        let baselineError: Double
    }

    // MARK: - Constantes
    private enum Constants {
        static let maxSamples = 24
        static let sampleLifetime: TimeInterval = 1.4
        static let minimumEyeDistanceMM: Double = 45
        static let maximumEyeDistanceMM: Double = 80
        static let maximumBaselineError: Double = 0.2
        static let minimumHorizontalPixels: Double = 10
        static let minMMPerPixel: Double = 0.01
        static let maxMMPerPixel: Double = 1.5
    }

    // MARK: - Estado
    private let queue = DispatchQueue(label: "com.medidorotica.truedepth.calibration", qos: .userInitiated)
    private var samples: [CalibrationSample] = []
    private var lastSample: CalibrationSample?

    // MARK: - API Pública
    /// Remove todas as amostras acumuladas.
    func reset() {
        queue.sync {
            samples.removeAll()
            lastSample = nil
        }
    }

    /// Armazena uma amostra calculada do frame informado.
    func ingest(frame: ARFrame) {
        guard let sample = Self.makeSample(from: frame) else { return }
        let timestamp = frame.timestamp

        queue.async {
            self.store(sample)
            self.purgeSamples(referenceTime: timestamp)
        }
    }

    /// Retorna uma calibração estabilizada combinando as amostras mais recentes.
    func refinedCalibration(for frame: ARFrame,
                            cropRect: CGRect,
                            orientation: CGImagePropertyOrientation) -> PostCaptureCalibration? {
        guard cropRect.width > 0, cropRect.height > 0 else { return nil }
        let candidate = Self.makeSample(from: frame)
        let timestamp = frame.timestamp

        return queue.sync {
            if let sample = candidate { self.store(sample) }
            self.purgeSamples(referenceTime: timestamp)
            return Self.makeCalibration(from: self.samples,
                                        cropRect: cropRect,
                                        orientation: orientation)
        }
    }

    /// Retorna uma calibração imediata usando a amostra atual ou a última válida.
    func instantCalibration(for frame: ARFrame,
                            cropRect: CGRect,
                            orientation: CGImagePropertyOrientation) -> PostCaptureCalibration? {
        guard cropRect.width > 0, cropRect.height > 0 else { return nil }
        if let sample = Self.makeSample(from: frame) {
            let timestamp = frame.timestamp
            return queue.sync {
                self.store(sample)
                self.purgeSamples(referenceTime: timestamp)
                return Self.makeCalibration(from: [sample],
                                            cropRect: cropRect,
                                            orientation: orientation)
            }
        }

        return queue.sync {
            guard let sample = self.lastSample else { return nil }
            return Self.makeCalibration(from: [sample],
                                        cropRect: cropRect,
                                        orientation: orientation)
        }
    }

    /// Retorna informações resumidas sobre o estado atual do estimador.
    func diagnostics() -> Diagnostics {
        queue.sync {
            let referenceTimestamp = lastSample?.timestamp ?? 0
            let recent = samples.filter { referenceTimestamp - $0.timestamp <= Constants.sampleLifetime }

            return Diagnostics(storedSampleCount: samples.count,
                               recentSampleCount: recent.count,
                               lastHorizontalMMPerPixel: lastSample?.mmPerPixelX,
                               lastVerticalMMPerPixel: lastSample?.mmPerPixelY,
                               lastDepthMM: lastSample.map { $0.depthMeters * 1000.0 },
                               lastBaselineError: lastSample?.baselineError)
        }
    }

    // MARK: - Armazenamento de Amostras
    private func store(_ sample: CalibrationSample) {
        guard sample.baselineError <= Constants.maximumBaselineError else { return }

        if let last = samples.last, abs(last.timestamp - sample.timestamp) < 0.0005 {
            samples[samples.count - 1] = sample
        } else {
            samples.append(sample)
        }

        if samples.count > Constants.maxSamples {
            samples.removeFirst(samples.count - Constants.maxSamples)
        }

        lastSample = sample
    }

    private func purgeSamples(referenceTime: TimeInterval) {
        samples.removeAll { referenceTime - $0.timestamp > Constants.sampleLifetime }
    }

    // MARK: - Construção de Calibração
    private static func makeCalibration(from samples: [CalibrationSample],
                                        cropRect: CGRect,
                                        orientation: CGImagePropertyOrientation) -> PostCaptureCalibration? {
        guard !samples.isEmpty else { return nil }

        let horizontalValues = samples.map(\.mmPerPixelX)
        let verticalValues = samples.map(\.mmPerPixelY)

        guard let horizontal = Statistics.robustMean(horizontalValues),
              let vertical = Statistics.robustMean(verticalValues) else {
            return nil
        }

        let axes = orientation.adjustedAxes(horizontal: horizontal, vertical: vertical)

        let horizontalReference = axes.horizontal * Double(cropRect.width)
        let verticalReference = axes.vertical * Double(cropRect.height)

        guard horizontalReference.isFinite,
              verticalReference.isFinite,
              horizontalReference > 0,
              verticalReference > 0 else {
            return nil
        }

        return PostCaptureCalibration(horizontalReferenceMM: horizontalReference,
                                      verticalReferenceMM: verticalReference)
    }

    // MARK: - Geração de Amostras
    private static func makeSample(from frame: ARFrame) -> CalibrationSample? {
        guard case .normal = frame.camera.trackingState else { return nil }
        guard let faceAnchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first,
              faceAnchor.isTracked else { return nil }

        let intrinsics = frame.camera.intrinsics
        let fx = Double(intrinsics.columns.0.x)
        let fy = Double(intrinsics.columns.1.y)

        guard fx > 0, fy > 0 else { return nil }

        let worldToCamera = simd_inverse(frame.camera.transform)

        let leftEyeWorld = simd_mul(faceAnchor.transform, faceAnchor.leftEyeTransform)
        let rightEyeWorld = simd_mul(faceAnchor.transform, faceAnchor.rightEyeTransform)

        let leftEyeCamera = simd_mul(worldToCamera, leftEyeWorld)
        let rightEyeCamera = simd_mul(worldToCamera, rightEyeWorld)

        let leftPositionCamera = position(from: leftEyeCamera)
        let rightPositionCamera = position(from: rightEyeCamera)

        let leftDepth = Double(-leftPositionCamera.z)
        let rightDepth = Double(-rightPositionCamera.z)
        guard leftDepth.isFinite, rightDepth.isFinite else { return nil }

        let averageDepth = max(0.12, min(1.5, (leftDepth + rightDepth) * 0.5))

        let leftWorldPosition = position(from: leftEyeWorld)
        let rightWorldPosition = position(from: rightEyeWorld)
        let distanceMM = Double(simd_distance(leftWorldPosition, rightWorldPosition)) * 1000.0
        guard distanceMM >= Constants.minimumEyeDistanceMM,
              distanceMM <= Constants.maximumEyeDistanceMM else { return nil }

        guard let leftPixelX = projectToPixelX(position: leftPositionCamera, intrinsics: intrinsics),
              let rightPixelX = projectToPixelX(position: rightPositionCamera, intrinsics: intrinsics) else {
            return nil
        }

        let pixelDelta = abs(rightPixelX - leftPixelX)
        guard pixelDelta >= Constants.minimumHorizontalPixels, pixelDelta.isFinite else { return nil }

        let baselineHorizontal = distanceMM / pixelDelta
        let depthHorizontal = (averageDepth * 1000.0) / fx
        let baselineError = abs(baselineHorizontal - depthHorizontal) / baselineHorizontal

        let blendedHorizontal = (baselineHorizontal * 0.7) + (depthHorizontal * 0.3)
        let verticalMMPerPixel = (averageDepth * 1000.0) / fy

        guard blendedHorizontal.isFinite,
              verticalMMPerPixel.isFinite,
              blendedHorizontal >= Constants.minMMPerPixel,
              blendedHorizontal <= Constants.maxMMPerPixel,
              verticalMMPerPixel >= Constants.minMMPerPixel,
              verticalMMPerPixel <= Constants.maxMMPerPixel else {
            return nil
        }

        return CalibrationSample(timestamp: frame.timestamp,
                                 mmPerPixelX: blendedHorizontal,
                                 mmPerPixelY: verticalMMPerPixel,
                                 depthMeters: averageDepth,
                                 baselineError: baselineError)
    }

    // MARK: - Helpers Matemáticos
    private static func position(from transform: simd_float4x4) -> simd_float3 {
        simd_float3(transform.columns.3.x,
                    transform.columns.3.y,
                    transform.columns.3.z)
    }

    private static func projectToPixelX(position: simd_float3,
                                        intrinsics: simd_float3x3) -> Double? {
        let z = Double(-position.z)
        guard z > 0 else { return nil }

        let x = Double(position.x)
        let fx = Double(intrinsics.columns.0.x)
        let cx = Double(intrinsics.columns.2.x)

        return fx * (x / z) + cx
    }
}

// MARK: - Estatística Robusta
private enum Statistics {
    static func robustMean(_ values: [Double]) -> Double? {
        let valid = values.filter { $0.isFinite }
        guard !valid.isEmpty else { return nil }

        let median = valid.median()
        let tolerance = max(0.12 * median, 0.0005)
        let filtered = valid.filter { abs($0 - median) <= tolerance }

        let usable = filtered.isEmpty ? valid : filtered
        return usable.average()
    }
}

private extension Array where Element == Double {
    func median() -> Double {
        guard !isEmpty else { return 0 }
        let sorted = self.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    func average() -> Double {
        guard !isEmpty else { return 0 }
        let sum = reduce(0, +)
        return sum / Double(count)
    }
}

// MARK: - Orientação
private extension CGImagePropertyOrientation {
    var swapsAxes: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        default:
            return false
        }
    }

    func adjustedAxes(horizontal: Double, vertical: Double) -> (horizontal: Double, vertical: Double) {
        swapsAxes ? (vertical, horizontal) : (horizontal, vertical)
    }
}
