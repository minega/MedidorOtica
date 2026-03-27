//
//  TrueDepthCalibrationEstimator.swift
//  MedidorOticaApp
//
//  Calcula a calibracao real do TrueDepth e publica o estado de bootstrap do sensor.
//

import Foundation
import ARKit
import ImageIO
import simd

// MARK: - Estimador TrueDepth
/// Consolida amostras em mm/pixel diretamente a partir do TrueDepth, mantendo apenas leituras confiaveis.
final class TrueDepthCalibrationEstimator {

    // MARK: - Diagnosticos Publicos
    struct Diagnostics {
        let storedSampleCount: Int
        let recentSampleCount: Int
        let lastHorizontalMMPerPixel: Double?
        let lastVerticalMMPerPixel: Double?
        let lastDepthMM: Double?
        let lastBaselineError: Double?
        let lastRejectReason: TrueDepthBlockReason?
        let lastValidSampleTimestamp: TimeInterval?
    }

    // MARK: - Tipos Internos
    private struct CalibrationSample {
        let timestamp: TimeInterval
        let mmPerPixelX: Double
        let mmPerPixelY: Double
        let depthMeters: Double
        let baselineError: Double
    }

    private enum SampleOutcome {
        case accepted(CalibrationSample)
        case rejected(TrueDepthBlockReason)
    }

    // MARK: - Constantes
    private enum Constants {
        static let maxSamples = 24
        static let sampleLifetime: TimeInterval = 2.0
        static let minimumEyeDistanceMM: Double = 45
        static let maximumEyeDistanceMM: Double = 80
        static let maximumBaselineError: Double = 0.35
        static let maximumBaselineErrorDiscard: Double = 0.8
        static let minimumHorizontalPixels: Double = 6
        static let minMMPerPixel: Double = 0.01
        static let maxMMPerPixel: Double = 1.0
    }

    // MARK: - Estado
    private let queue = DispatchQueue(label: "com.medidorotica.truedepth.calibration",
                                      qos: .userInitiated)
    private var samples: [CalibrationSample] = []
    private var lastSample: CalibrationSample?
    private var lastRejectReason: TrueDepthBlockReason?
    private var lastRejectTimestamp: TimeInterval?
    private var lastFrameTimestamp: TimeInterval = 0

    // MARK: - Log
    @inline(__always)
    private static func debug(_ code: Int, _ message: String) {
        print("TDCalib[\(code)]: \(message)")
    }

    // MARK: - API Publica
    /// Remove todas as amostras acumuladas e limpa o diagnostico do bootstrap.
    func reset() {
        queue.sync {
            samples.removeAll()
            lastSample = nil
            lastRejectReason = nil
            lastRejectTimestamp = nil
            lastFrameTimestamp = 0
        }
    }

    /// Armazena o frame atual e retorna o estado consolidado do bootstrap.
    @discardableResult
    func ingest(frame: ARFrame,
                bootstrapSampleCount: Int = 2) -> TrueDepthBootstrapStatus {
        let outcome = Self.makeSampleOutcome(from: frame)
        let timestamp = frame.timestamp

        return queue.sync {
            lastFrameTimestamp = timestamp
            register(outcome: outcome, timestamp: timestamp)
            purgeSamples(referenceTime: timestamp)
            return bootstrapStatusLocked(minRecentSamples: bootstrapSampleCount)
        }
    }

    /// Retorna o estado atual do bootstrap usando as ultimas amostras conhecidas.
    func bootstrapStatus(minRecentSamples: Int = 2) -> TrueDepthBootstrapStatus {
        queue.sync {
            bootstrapStatusLocked(minRecentSamples: minRecentSamples)
        }
    }

    /// Retorna uma calibracao estabilizada combinando as amostras mais recentes.
    func refinedCalibration(for frame: ARFrame,
                            cropRect: CGRect,
                            orientation: CGImagePropertyOrientation) -> PostCaptureCalibration? {
        guard cropRect.width > 0, cropRect.height > 0 else { return nil }
        let outcome = Self.makeSampleOutcome(from: frame)
        let timestamp = frame.timestamp

        return queue.sync {
            lastFrameTimestamp = timestamp
            register(outcome: outcome, timestamp: timestamp)
            purgeSamples(referenceTime: timestamp)
            return Self.makeCalibration(from: samples,
                                        cropRect: cropRect,
                                        orientation: orientation)
        }
    }

    /// Retorna uma calibracao imediata usando a amostra atual ou a ultima valida.
    func instantCalibration(for frame: ARFrame,
                            cropRect: CGRect,
                            orientation: CGImagePropertyOrientation) -> PostCaptureCalibration? {
        guard cropRect.width > 0, cropRect.height > 0 else { return nil }
        let outcome = Self.makeSampleOutcome(from: frame)
        let timestamp = frame.timestamp

        return queue.sync {
            lastFrameTimestamp = timestamp
            register(outcome: outcome, timestamp: timestamp)
            purgeSamples(referenceTime: timestamp)

            if case .accepted(let sample) = outcome {
                return Self.makeCalibration(from: [sample],
                                            cropRect: cropRect,
                                            orientation: orientation)
            }

            guard let lastSample else { return nil }
            return Self.makeCalibration(from: [lastSample],
                                        cropRect: cropRect,
                                        orientation: orientation)
        }
    }

    /// Retorna informacoes resumidas sobre o estado atual do estimador.
    func diagnostics() -> Diagnostics {
        queue.sync {
            let referenceTimestamp = max(lastFrameTimestamp, lastSample?.timestamp ?? 0)
            let recent = samples.filter { referenceTimestamp - $0.timestamp <= Constants.sampleLifetime }

            return Diagnostics(storedSampleCount: samples.count,
                               recentSampleCount: recent.count,
                               lastHorizontalMMPerPixel: lastSample?.mmPerPixelX,
                               lastVerticalMMPerPixel: lastSample?.mmPerPixelY,
                               lastDepthMM: lastSample.map { $0.depthMeters * 1000.0 },
                               lastBaselineError: lastSample?.baselineError,
                               lastRejectReason: lastRejectReason,
                               lastValidSampleTimestamp: lastSample?.timestamp)
        }
    }

    /// Indica se ja existem amostras recentes e consistentes para permitir a captura.
    func readiness(minRecentSamples: Int = 4,
                   depthRangeMM: ClosedRange<Double> = 250...600,
                   mmPerPixelRange: ClosedRange<Double> = 0.03...0.25) -> (ready: Bool, hint: String?) {
        queue.sync {
            let bootstrap = bootstrapStatusLocked(minRecentSamples: 2)
            guard bootstrap.sensorAlive else {
                let hint = bootstrap.failureReason?.shortMessage ?? "TrueDepth indisponivel."
                return (false, hint)
            }

            guard let lastSample else {
                return (false, TrueDepthBlockReason.noRecentSamples.shortMessage)
            }

            let referenceTime = max(lastFrameTimestamp, lastSample.timestamp)
            let recentSamples = samples.filter { referenceTime - $0.timestamp <= Constants.sampleLifetime }
            var reasons: [String] = []

            if recentSamples.count < minRecentSamples {
                reasons.append("Coletando calibracao (\(recentSamples.count)/\(minRecentSamples)).")
            }

            let depthMM = lastSample.depthMeters * 1000.0
            if !depthRangeMM.contains(depthMM) {
                reasons.append("Ajuste a distancia para \(Int(depthRangeMM.lowerBound))-\(Int(depthRangeMM.upperBound))mm.")
            }

            if !mmPerPixelRange.contains(lastSample.mmPerPixelX) ||
                !mmPerPixelRange.contains(lastSample.mmPerPixelY) {
                reasons.append("Estabilize a posicao para obter escala consistente.")
            }

            if lastSample.baselineError > Constants.maximumBaselineError {
                reasons.append("Rastreie o rosto novamente para reduzir ruido.")
            }

            let ready = reasons.isEmpty
            return (ready, ready ? nil : reasons.joined(separator: " "))
        }
    }

    // MARK: - Armazenamento
    private func register(outcome: SampleOutcome, timestamp: TimeInterval) {
        switch outcome {
        case .accepted(let sample):
            lastRejectReason = nil
            lastRejectTimestamp = nil
            store(sample)
        case .rejected(let reason):
            lastRejectReason = reason
            lastRejectTimestamp = timestamp
        }
    }

    private func store(_ sample: CalibrationSample) {
        guard sample.baselineError.isFinite else {
            Self.debug(120, "Descartando amostra com baseline indefinido")
            return
        }

        guard sample.baselineError <= Constants.maximumBaselineErrorDiscard else {
            Self.debug(121, "Descartando amostra com baseline muito alto (\(sample.baselineError))")
            return
        }

        let clippedBaseline = min(sample.baselineError, Constants.maximumBaselineError)
        let adjustedSample = CalibrationSample(timestamp: sample.timestamp,
                                               mmPerPixelX: sample.mmPerPixelX,
                                               mmPerPixelY: sample.mmPerPixelY,
                                               depthMeters: sample.depthMeters,
                                               baselineError: clippedBaseline)

        if let last = samples.last,
           abs(last.timestamp - adjustedSample.timestamp) < 0.0005 {
            samples[samples.count - 1] = adjustedSample
        } else {
            samples.append(adjustedSample)
        }

        if samples.count > Constants.maxSamples {
            samples.removeFirst(samples.count - Constants.maxSamples)
        }

        lastSample = adjustedSample
    }

    private func purgeSamples(referenceTime: TimeInterval) {
        samples.removeAll { referenceTime - $0.timestamp > Constants.sampleLifetime }
    }

    // MARK: - Bootstrap
    private func bootstrapStatusLocked(minRecentSamples: Int) -> TrueDepthBootstrapStatus {
        let referenceTime = max(lastFrameTimestamp,
                                lastSample?.timestamp ?? 0,
                                lastRejectTimestamp ?? 0)

        guard referenceTime > 0 else {
            return TrueDepthBootstrapStatus(state: .startingSession,
                                            failureReason: nil,
                                            recentSampleCount: 0,
                                            lastValidSampleTimestamp: nil,
                                            lastRejectTimestamp: nil)
        }

        let recentSamples = samples.filter { referenceTime - $0.timestamp <= Constants.sampleLifetime }
        guard recentSamples.count < minRecentSamples else {
            return TrueDepthBootstrapStatus(state: .sensorAlive,
                                            failureReason: nil,
                                            recentSampleCount: recentSamples.count,
                                            lastValidSampleTimestamp: lastSample?.timestamp,
                                            lastRejectTimestamp: lastRejectTimestamp)
        }

        let reason = currentBootstrapReasonLocked(referenceTime: referenceTime,
                                                  recentSampleCount: recentSamples.count)
        return TrueDepthBootstrapStatus(state: bootstrapState(for: reason),
                                        failureReason: reason,
                                        recentSampleCount: recentSamples.count,
                                        lastValidSampleTimestamp: lastSample?.timestamp,
                                        lastRejectTimestamp: lastRejectTimestamp)
    }

    private func currentBootstrapReasonLocked(referenceTime: TimeInterval,
                                              recentSampleCount: Int) -> TrueDepthBlockReason {
        if let lastRejectReason,
           let lastRejectTimestamp,
           referenceTime - lastRejectTimestamp <= Constants.sampleLifetime {
            return lastRejectReason
        }

        if recentSampleCount > 0 {
            return .noRecentSamples
        }

        if let lastSample, referenceTime - lastSample.timestamp > Constants.sampleLifetime {
            return .noRecentSamples
        }

        return .noFaceAnchor
    }

    private func bootstrapState(for reason: TrueDepthBlockReason) -> TrueDepthBootstrapState {
        switch reason {
        case .noFaceAnchor, .faceNotTracked:
            return .waitingForFaceAnchor
        case .invalidIntrinsics, .invalidEyeDepth, .pixelBaselineTooSmall:
            return .waitingForEyeProjection
        case .ipdOutOfRange, .scaleOutOfRange, .baselineNoiseTooHigh, .noRecentSamples:
            return .waitingForDepthConsistency
        }
    }

    // MARK: - Construcao da calibracao
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

    // MARK: - Geracao de amostras
    private static func makeSampleOutcome(from frame: ARFrame) -> SampleOutcome {
        guard case .normal = frame.camera.trackingState else {
            debug(201, "Tracking state nao normal")
            return .rejected(.faceNotTracked)
        }

        let faceAnchorResult = trackedFaceAnchor(in: frame)
        guard case .success(let faceAnchor) = faceAnchorResult else {
            if case .failure(let reason) = faceAnchorResult {
                return .rejected(reason)
            }
            return .rejected(.noFaceAnchor)
        }

        let intrinsics = frame.camera.intrinsics
        let fx = Double(intrinsics.columns.0.x)
        let fy = Double(intrinsics.columns.1.y)
        guard fx > 0, fy > 0 else {
            debug(203, "Intrinsecos invalidos fx=\(fx) fy=\(fy)")
            return .rejected(.invalidIntrinsics)
        }

        let worldToCamera = simd_inverse(frame.camera.transform)
        let leftEyeWorld = simd_mul(faceAnchor.transform, faceAnchor.leftEyeTransform)
        let rightEyeWorld = simd_mul(faceAnchor.transform, faceAnchor.rightEyeTransform)
        let leftEyeCamera = simd_mul(worldToCamera, leftEyeWorld)
        let rightEyeCamera = simd_mul(worldToCamera, rightEyeWorld)
        let leftPositionCamera = position(from: leftEyeCamera)
        let rightPositionCamera = position(from: rightEyeCamera)

        let leftDepth = Double(-leftPositionCamera.z)
        let rightDepth = Double(-rightPositionCamera.z)
        guard leftDepth.isFinite,
              rightDepth.isFinite,
              leftDepth > 0,
              rightDepth > 0 else {
            debug(204, "Profundidade invalida left=\(leftDepth) right=\(rightDepth)")
            return .rejected(.invalidEyeDepth)
        }

        let leftWorldPosition = position(from: leftEyeWorld)
        let rightWorldPosition = position(from: rightEyeWorld)
        let distanceMM = Double(simd_distance(leftWorldPosition, rightWorldPosition)) * 1000.0
        guard distanceMM >= Constants.minimumEyeDistanceMM,
              distanceMM <= Constants.maximumEyeDistanceMM else {
            debug(205, "IPD fora da faixa (\(distanceMM)mm)")
            return .rejected(.ipdOutOfRange)
        }

        guard let leftPixelX = projectToPixelX(position: leftPositionCamera, intrinsics: intrinsics),
              let rightPixelX = projectToPixelX(position: rightPositionCamera, intrinsics: intrinsics) else {
            debug(206, "Falha ao projetar olhos para pixels")
            return .rejected(.invalidEyeDepth)
        }

        let pixelDeltaX = Swift.abs(rightPixelX - leftPixelX)
        guard pixelDeltaX >= Constants.minimumHorizontalPixels,
              pixelDeltaX.isFinite else {
            debug(207, "Delta de pixels insuficiente \(pixelDeltaX)")
            return .rejected(.pixelBaselineTooSmall)
        }

        let baselineHorizontal = distanceMM / pixelDeltaX
        guard baselineHorizontal.isFinite else {
            debug(208, "mmPerPixelX nao finito \(baselineHorizontal)")
            return .rejected(.scaleOutOfRange)
        }

        guard baselineHorizontal >= Constants.minMMPerPixel,
              baselineHorizontal <= Constants.maxMMPerPixel else {
            debug(209, "mmPerPixelX fora da faixa \(baselineHorizontal)")
            return .rejected(.scaleOutOfRange)
        }

        let verticalScale = (fy > 0 && fx > 0) ? (fx / fy) : 1.0
        let mmPerPixelY = baselineHorizontal * verticalScale
        guard mmPerPixelY.isFinite,
              mmPerPixelY >= Constants.minMMPerPixel,
              mmPerPixelY <= Constants.maxMMPerPixel else {
            debug(210, "mmPerPixelY fora da faixa \(mmPerPixelY)")
            return .rejected(.scaleOutOfRange)
        }

        let averageDepth = max(0.12, (leftDepth + rightDepth) * 0.5)
        let depthSkew = Swift.abs(leftDepth - rightDepth) / max(averageDepth, 0.0001)
        let scaleSkew = Swift.abs(mmPerPixelY - baselineHorizontal) / max(baselineHorizontal, 0.0001)
        let qualityError = max(depthSkew, scaleSkew)
        guard qualityError <= Constants.maximumBaselineErrorDiscard else {
            debug(213, "Ruido excessivo na baseline \(qualityError)")
            return .rejected(.baselineNoiseTooHigh)
        }

        let sample = CalibrationSample(timestamp: frame.timestamp,
                                       mmPerPixelX: baselineHorizontal,
                                       mmPerPixelY: mmPerPixelY,
                                       depthMeters: averageDepth,
                                       baselineError: qualityError)
        return .accepted(sample)
    }

    private static func trackedFaceAnchor(in frame: ARFrame) -> Result<ARFaceAnchor, TrueDepthBlockReason> {
        guard let faceAnchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first else {
            debug(202, "FaceAnchor indisponivel")
            return .failure(.noFaceAnchor)
        }

        guard faceAnchor.isTracked else {
            debug(212, "FaceAnchor presente mas nao rastreado")
            return .failure(.faceNotTracked)
        }

        return .success(faceAnchor)
    }

    // MARK: - Helpers matematicos
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

// MARK: - Concurrency
/// O acesso as amostras fica protegido pela fila privada do estimador.
extension TrueDepthCalibrationEstimator: @unchecked Sendable {}

// MARK: - Estatistica robusta
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
        return reduce(0, +) / Double(count)
    }
}

// MARK: - Orientacao
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
