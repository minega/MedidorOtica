//
//  TrueDepthCalibrationEstimator.swift
//  MedidorOticaApp
//
//  Estima a escala real do TrueDepth usando malha facial e projecao 3D.
//

import Foundation
import ARKit
import ImageIO
import UIKit
import simd

// MARK: - Estimador TrueDepth
/// Consolida amostras em mm/pixel a partir do Face Tracking, mantendo apenas leituras confiaveis.
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
        let lastTrackedFaceTimestamp: TimeInterval?
    }

    // MARK: - Tipos Internos
    private struct CalibrationSample {
        let timestamp: TimeInterval
        let mmPerPixelX: Double
        let mmPerPixelY: Double
        let depthMeters: Double
        let baselineError: Double
    }

    private struct PairMeasurement {
        let mmDistance: Double
        let pixelDX: Double
        let pixelDY: Double
    }

    private struct LocalScaleAccumulator {
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var sumHorizontal: Double = 0
        var sumVertical: Double = 0
        var sumDepth: Double = 0
        var count = 0

        mutating func append(_ sample: LocalFaceScaleSample) {
            sumX += sample.point.x
            sumY += sample.point.y
            sumHorizontal += sample.horizontalReferenceMM
            sumVertical += sample.verticalReferenceMM
            sumDepth += sample.depthMM
            count += 1
        }

        func averagedSample() -> LocalFaceScaleSample? {
            guard count > 0 else { return nil }

            return LocalFaceScaleSample(point: NormalizedPoint(x: sumX / CGFloat(count),
                                                               y: sumY / CGFloat(count)),
                                        horizontalReferenceMM: sumHorizontal / Double(count),
                                        verticalReferenceMM: sumVertical / Double(count),
                                        depthMM: sumDepth / Double(count))
        }
    }

    private enum SampleOutcome {
        case accepted(CalibrationSample)
        case rejected(TrueDepthBlockReason)
    }

    private enum SensorLivenessOutcome {
        case trackedFace
        case blocked(TrueDepthBlockReason)
    }

    // MARK: - Constantes
    private enum Constants {
        static let maxSamples = 90
        static let sampleLifetime: TimeInterval = 1.5
        static let sensorLivenessLifetime: TimeInterval = 0.45
        static let minimumHorizontalPixels: Double = 3
        static let minimumInterPupillaryMM: Double = 45
        static let maximumInterPupillaryMM: Double = 80
        static let minimumMeshDistanceMM: Double = 60
        static let maximumMeshDistanceMM: Double = 180
        static let minMMPerPixel: Double = 0.01
        static let maxMMPerPixel: Double = 0.35
        static let maximumBaselineError: Double = 0.18
        static let maximumBaselineErrorDiscard: Double = 0.35
        static let meshSupportToleranceRatio: Double = 0.12
        static let trimRatio = 0.10
        static let meshPairTrimDivisor = 20
        static let maxMeshPairs = 6
        static let localCalibrationGridColumns = 8
        static let localCalibrationGridRows = 10
        static let localCalibrationMinimumDepthMeters = 0.18
        static let localCalibrationMaximumDepthMeters = 0.60
        static let minimumLocalSamples = 12
    }

    // MARK: - Estado
    private let queue = DispatchQueue(label: "com.medidorotica.truedepth.calibration",
                                      qos: .userInitiated)
    private var samples: [CalibrationSample] = []
    private var lastSample: CalibrationSample?
    private var lastRejectReason: TrueDepthBlockReason?
    private var lastRejectTimestamp: TimeInterval?
    private var lastTrackedFaceTimestamp: TimeInterval?
    private var lastLivenessFailureReason: TrueDepthBlockReason?
    private var lastLivenessFailureTimestamp: TimeInterval?
    private var lastFrameTimestamp: TimeInterval = 0

    // MARK: - API Publica
    /// Limpa todas as amostras e reinicia o bootstrap do sensor.
    func reset() {
        queue.sync {
            samples.removeAll()
            lastSample = nil
            lastRejectReason = nil
            lastRejectTimestamp = nil
            lastTrackedFaceTimestamp = nil
            lastLivenessFailureReason = nil
            lastLivenessFailureTimestamp = nil
            lastFrameTimestamp = 0
        }
    }

    /// Registra o frame atual e devolve o estado do bootstrap do sensor.
    @discardableResult
    func ingest(frame: ARFrame,
                cgOrientation: CGImagePropertyOrientation,
                uiOrientation: UIInterfaceOrientation,
                bootstrapSampleCount: Int = 1) -> TrueDepthBootstrapStatus {
        let faceAnchorResult = Self.trackedFaceAnchor(in: frame)
        let livenessOutcome = Self.makeSensorLivenessOutcome(from: faceAnchorResult)
        let sampleOutcome = Self.makeSampleOutcome(from: frame,
                                                   faceAnchorResult: faceAnchorResult,
                                                   cgOrientation: cgOrientation,
                                                   uiOrientation: uiOrientation)
        let timestamp = frame.timestamp

        return queue.sync {
            lastFrameTimestamp = timestamp
            register(livenessOutcome: livenessOutcome, timestamp: timestamp)
            register(outcome: sampleOutcome, timestamp: timestamp)
            purgeSamples(referenceTime: timestamp)
            return bootstrapStatusLocked(minRecentSamples: bootstrapSampleCount)
        }
    }

    /// Informa o estado atual do bootstrap sem inserir um novo frame.
    func bootstrapStatus(minRecentSamples: Int = 1) -> TrueDepthBootstrapStatus {
        queue.sync {
            bootstrapStatusLocked(minRecentSamples: minRecentSamples)
        }
    }

    /// Retorna uma calibracao estabilizada para o frame atual.
    func refinedCalibration(for frame: ARFrame,
                            cropRect: CGRect,
                            orientation: CGImagePropertyOrientation,
                            uiOrientation: UIInterfaceOrientation) -> PostCaptureCalibration? {
        updateEstimator(frame: frame,
                        cgOrientation: orientation,
                        uiOrientation: uiOrientation)

        return queue.sync {
            Self.makeCalibration(from: samples, cropRect: cropRect)
        }
    }

    /// Retorna uma calibracao imediata usando a amostra atual ou a ultima valida.
    func instantCalibration(for frame: ARFrame,
                            cropRect: CGRect,
                            orientation: CGImagePropertyOrientation,
                            uiOrientation: UIInterfaceOrientation) -> PostCaptureCalibration? {
        updateEstimator(frame: frame,
                        cgOrientation: orientation,
                        uiOrientation: uiOrientation)

        return queue.sync {
            guard let lastSample else { return nil }
            return Self.makeCalibration(from: [lastSample], cropRect: cropRect)
        }
    }

    /// Gera uma calibracao de preview usando a imagem inteira orientada.
    func previewCalibration(for frame: ARFrame,
                            orientation: CGImagePropertyOrientation,
                            uiOrientation: UIInterfaceOrientation) -> PostCaptureCalibration? {
        let cropRect = CGRect(origin: .zero,
                              size: Self.orientedViewportSize(resolution: frame.camera.imageResolution,
                                                              orientation: orientation))
        return refinedCalibration(for: frame,
                                  cropRect: cropRect,
                                  orientation: orientation,
                                  uiOrientation: uiOrientation)
    }

    /// Gera um mapa local de escala a partir da malha 3D do TrueDepth no frame capturado.
    func localFaceCalibration(for frame: ARFrame,
                              faceAnchor: ARFaceAnchor,
                              orientation: CGImagePropertyOrientation,
                              uiOrientation: UIInterfaceOrientation) -> LocalFaceScaleCalibration? {
        let viewportSize = Self.orientedViewportSize(resolution: frame.camera.imageResolution,
                                                     orientation: orientation)
        let focal = Self.orientedFocalLengths(from: frame.camera.intrinsics,
                                              orientation: orientation)
        guard focal.fx > 0, focal.fy > 0 else { return nil }

        let worldToCamera = simd_inverse(frame.camera.transform)
        let calibration = Self.makeLocalFaceCalibration(faceAnchor: faceAnchor,
                                                        camera: frame.camera,
                                                        worldToCamera: worldToCamera,
                                                        uiOrientation: uiOrientation,
                                                        viewportSize: viewportSize,
                                                        focal: focal)
        return calibration?.isReliable == true ? calibration : nil
    }

    /// Retorna um diagnostico resumido do estado interno atual.
    func diagnostics() -> Diagnostics {
        queue.sync {
            let referenceTime = currentReferenceTimeLocked()
            let recentSamples = samples.filter { referenceTime - $0.timestamp <= Constants.sampleLifetime }

            return Diagnostics(storedSampleCount: samples.count,
                               recentSampleCount: recentSamples.count,
                               lastHorizontalMMPerPixel: lastSample?.mmPerPixelX,
                               lastVerticalMMPerPixel: lastSample?.mmPerPixelY,
                               lastDepthMM: lastSample.map { $0.depthMeters * 1000.0 },
                               lastBaselineError: lastSample?.baselineError,
                               lastRejectReason: lastRejectReason,
                               lastValidSampleTimestamp: lastSample?.timestamp,
                               lastTrackedFaceTimestamp: lastTrackedFaceTimestamp)
        }
    }

    /// Indica se ja existe escala suficiente para liberar a captura.
    func readiness(minRecentSamples: Int = 2,
                   mmPerPixelRange: ClosedRange<Double> = 0.015...0.30) -> (ready: Bool, hint: String?) {
        queue.sync {
            let bootstrap = bootstrapStatusLocked(minRecentSamples: 1)
            guard bootstrap.sensorAlive else {
                return (false, bootstrap.failureReason?.shortMessage ?? "TrueDepth indisponivel.")
            }

            guard let lastSample else {
                return (false, TrueDepthBlockReason.noRecentSamples.shortMessage)
            }

            let referenceTime = currentReferenceTimeLocked()
            let recentSamples = samples.filter { referenceTime - $0.timestamp <= Constants.sampleLifetime }
            var reasons: [String] = []

            if recentSamples.count < minRecentSamples {
                reasons.append("Coletando escala do TrueDepth.")
            }

            if !mmPerPixelRange.contains(lastSample.mmPerPixelX) ||
                !mmPerPixelRange.contains(lastSample.mmPerPixelY) {
                reasons.append("Reposicione o rosto para medir a escala.")
            }

            if lastSample.baselineError > Constants.maximumBaselineError {
                reasons.append("Mantenha o rosto firme.")
            }

            return reasons.isEmpty ? (true, nil) : (false, reasons.joined(separator: " "))
        }
    }

    // MARK: - Atualizacao Interna
    private func updateEstimator(frame: ARFrame,
                                 cgOrientation: CGImagePropertyOrientation,
                                 uiOrientation: UIInterfaceOrientation) {
        let faceAnchorResult = Self.trackedFaceAnchor(in: frame)
        let livenessOutcome = Self.makeSensorLivenessOutcome(from: faceAnchorResult)
        let sampleOutcome = Self.makeSampleOutcome(from: frame,
                                                   faceAnchorResult: faceAnchorResult,
                                                   cgOrientation: cgOrientation,
                                                   uiOrientation: uiOrientation)
        let timestamp = frame.timestamp

        queue.sync {
            lastFrameTimestamp = timestamp
            register(livenessOutcome: livenessOutcome, timestamp: timestamp)
            register(outcome: sampleOutcome, timestamp: timestamp)
            purgeSamples(referenceTime: timestamp)
        }
    }

    private func register(livenessOutcome: SensorLivenessOutcome,
                          timestamp: TimeInterval) {
        switch livenessOutcome {
        case .trackedFace:
            lastTrackedFaceTimestamp = timestamp
            lastLivenessFailureReason = nil
            lastLivenessFailureTimestamp = nil
        case .blocked(let reason):
            lastLivenessFailureReason = reason
            lastLivenessFailureTimestamp = timestamp
        }
    }

    private func register(outcome: SampleOutcome,
                          timestamp: TimeInterval) {
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
        let adjustedSample = CalibrationSample(timestamp: sample.timestamp,
                                               mmPerPixelX: sample.mmPerPixelX,
                                               mmPerPixelY: sample.mmPerPixelY,
                                               depthMeters: sample.depthMeters,
                                               baselineError: min(sample.baselineError,
                                                                  Constants.maximumBaselineError))

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
        let referenceTime = currentReferenceTimeLocked()
        guard referenceTime > 0 else {
            return TrueDepthBootstrapStatus(state: .startingSession,
                                            failureReason: nil,
                                            recentSampleCount: 0,
                                            lastValidSampleTimestamp: nil,
                                            lastRejectTimestamp: nil)
        }

        let recentSamples = samples.filter { referenceTime - $0.timestamp <= Constants.sampleLifetime }
        let hasTrackedFace = hasRecentTrackedFaceLocked(referenceTime: referenceTime)

        if hasTrackedFace && recentSamples.count >= minRecentSamples {
            return TrueDepthBootstrapStatus(state: .sensorAlive,
                                            failureReason: nil,
                                            recentSampleCount: recentSamples.count,
                                            lastValidSampleTimestamp: lastSample?.timestamp,
                                            lastRejectTimestamp: lastRejectTimestamp)
        }

        if hasTrackedFace {
            return TrueDepthBootstrapStatus(state: .sensorAlive,
                                            failureReason: nil,
                                            recentSampleCount: recentSamples.count,
                                            lastValidSampleTimestamp: lastSample?.timestamp,
                                            lastRejectTimestamp: lastRejectTimestamp)
        }

        let reason = currentBootstrapReasonLocked(referenceTime: referenceTime)
        return TrueDepthBootstrapStatus(state: bootstrapState(for: reason),
                                        failureReason: reason,
                                        recentSampleCount: recentSamples.count,
                                        lastValidSampleTimestamp: lastSample?.timestamp,
                                        lastRejectTimestamp: lastRejectTimestamp)
    }

    private func currentReferenceTimeLocked() -> TimeInterval {
        [
            lastFrameTimestamp,
            lastSample?.timestamp ?? 0,
            lastRejectTimestamp ?? 0,
            lastTrackedFaceTimestamp ?? 0,
            lastLivenessFailureTimestamp ?? 0
        ].max() ?? 0
    }

    private func currentBootstrapReasonLocked(referenceTime: TimeInterval) -> TrueDepthBlockReason {
        if let lastLivenessFailureReason,
           let lastLivenessFailureTimestamp,
           referenceTime - lastLivenessFailureTimestamp <= Constants.sensorLivenessLifetime {
            return lastLivenessFailureReason
        }

        if let lastRejectReason,
           let lastRejectTimestamp,
           referenceTime - lastRejectTimestamp <= Constants.sampleLifetime {
            return lastRejectReason
        }

        return .noFaceAnchor
    }

    private func hasRecentTrackedFaceLocked(referenceTime: TimeInterval) -> Bool {
        guard let lastTrackedFaceTimestamp else { return false }
        return referenceTime - lastTrackedFaceTimestamp <= Constants.sensorLivenessLifetime
    }

    private func bootstrapState(for reason: TrueDepthBlockReason) -> TrueDepthBootstrapState {
        switch reason {
        case .noFaceAnchor, .faceNotTracked:
            return .waitingForFaceAnchor
        case .invalidIntrinsics, .invalidEyeDepth:
            return .waitingForEyeProjection
        case .ipdOutOfRange, .pixelBaselineTooSmall, .scaleOutOfRange,
                .baselineNoiseTooHigh, .noRecentSamples:
            return .waitingForDepthConsistency
        }
    }

    // MARK: - Calibracao
    private static func makeCalibration(from samples: [CalibrationSample],
                                        cropRect: CGRect) -> PostCaptureCalibration? {
        guard cropRect.width > 0, cropRect.height > 0 else { return nil }
        guard !samples.isEmpty else { return nil }

        let horizontalValues = samples.map(\.mmPerPixelX)
        let verticalValues = samples.map(\.mmPerPixelY)

        guard let horizontal = Statistics.robustMean(horizontalValues),
              let vertical = Statistics.robustMean(verticalValues),
              horizontal.isFinite,
              vertical.isFinite,
              horizontal > 0,
              vertical > 0 else {
            return nil
        }

        let horizontalReference = horizontal * Double(cropRect.width)
        let verticalReference = vertical * Double(cropRect.height)

        guard horizontalReference.isFinite,
              verticalReference.isFinite,
              horizontalReference > 0,
              verticalReference > 0 else {
            return nil
        }

        return PostCaptureCalibration(horizontalReferenceMM: horizontalReference,
                                      verticalReferenceMM: verticalReference)
    }

    // MARK: - Amostras
    private static func makeSensorLivenessOutcome(from faceAnchorResult: Result<ARFaceAnchor, TrueDepthBlockReason>) -> SensorLivenessOutcome {
        switch faceAnchorResult {
        case .success:
            return .trackedFace
        case .failure(let reason):
            return .blocked(reason)
        }
    }

    private static func makeSampleOutcome(from frame: ARFrame,
                                          faceAnchorResult: Result<ARFaceAnchor, TrueDepthBlockReason>,
                                          cgOrientation: CGImagePropertyOrientation,
                                          uiOrientation: UIInterfaceOrientation) -> SampleOutcome {
        guard case .normal = frame.camera.trackingState else {
            return .rejected(.faceNotTracked)
        }

        guard case .success(let faceAnchor) = faceAnchorResult else {
            if case .failure(let reason) = faceAnchorResult {
                return .rejected(reason)
            }
            return .rejected(.noFaceAnchor)
        }

        let viewportSize = orientedViewportSize(resolution: frame.camera.imageResolution,
                                                orientation: cgOrientation)
        let focal = orientedFocalLengths(from: frame.camera.intrinsics,
                                         orientation: cgOrientation)
        guard focal.fx > 0, focal.fy > 0 else {
            return .rejected(.invalidIntrinsics)
        }

        var horizontalCandidates: [Double] = []
        var verticalCandidates: [Double] = []
        var fallbackFailureReason: TrueDepthBlockReason?

        let meshCandidates = meshBasedCandidates(faceAnchor: faceAnchor,
                                                 camera: frame.camera,
                                                 uiOrientation: uiOrientation,
                                                 viewportSize: viewportSize)
        let interPupillaryResult = interPupillaryCandidate(faceAnchor: faceAnchor,
                                                           camera: frame.camera,
                                                           uiOrientation: uiOrientation,
                                                           viewportSize: viewportSize)

        let mmPerPixelX: Double
        let mmPerPixelY: Double

        switch interPupillaryResult {
        case .success(let candidate):
            // Quando a distancia interpupilar real esta disponivel, ela vira a referencia principal.
            // Isso evita inflar a escala com pares largos da malha facial.
            horizontalCandidates = [candidate]

            let projectedVertical = candidate * (focal.fx / focal.fy)
            guard projectedVertical.isFinite,
                  projectedVertical >= Constants.minMMPerPixel,
                  projectedVertical <= Constants.maxMMPerPixel else {
                return .rejected(.scaleOutOfRange)
            }

            let filteredVerticalSupport = supportedMeshCandidates(meshCandidates.vertical,
                                                                  around: projectedVertical)
            verticalCandidates = [projectedVertical] + filteredVerticalSupport
            mmPerPixelX = candidate
            mmPerPixelY = Statistics.robustMean(verticalCandidates) ?? projectedVertical
        case .failure(let reason):
            fallbackFailureReason = reason
            horizontalCandidates = meshCandidates.horizontal
            verticalCandidates = meshCandidates.vertical

            guard !horizontalCandidates.isEmpty else {
                let meshFailureReason = meshSamplingFailureReason(faceAnchor: faceAnchor,
                                                                 camera: frame.camera,
                                                                 uiOrientation: uiOrientation,
                                                                 viewportSize: viewportSize)
                return .rejected(meshFailureReason ?? fallbackFailureReason ?? .invalidEyeDepth)
            }

            guard let horizontalMean = Statistics.robustMean(horizontalCandidates),
                  horizontalMean.isFinite,
                  horizontalMean >= Constants.minMMPerPixel,
                  horizontalMean <= Constants.maxMMPerPixel else {
                return .rejected(.scaleOutOfRange)
            }

            let projectedVertical = horizontalMean * (focal.fx / focal.fy)
            if projectedVertical.isFinite {
                verticalCandidates.append(projectedVertical)
            }

            guard let verticalMean = Statistics.robustMean(verticalCandidates),
                  verticalMean.isFinite,
                  verticalMean >= Constants.minMMPerPixel,
                  verticalMean <= Constants.maxMMPerPixel else {
                return .rejected(.scaleOutOfRange)
            }

            mmPerPixelX = horizontalMean
            mmPerPixelY = verticalMean
        }

        let baselineError = max(Statistics.normalizedDispersion(horizontalCandidates, center: mmPerPixelX),
                                Statistics.normalizedDispersion(verticalCandidates, center: mmPerPixelY))
        guard baselineError <= Constants.maximumBaselineErrorDiscard else {
            return .rejected(.baselineNoiseTooHigh)
        }

        let depthMeters = averageEyeDepth(faceAnchor: faceAnchor, camera: frame.camera)
        let sample = CalibrationSample(timestamp: frame.timestamp,
                                       mmPerPixelX: mmPerPixelX,
                                       mmPerPixelY: mmPerPixelY,
                                       depthMeters: depthMeters,
                                       baselineError: baselineError)
        return .accepted(sample)
    }

    private static func trackedFaceAnchor(in frame: ARFrame) -> Result<ARFaceAnchor, TrueDepthBlockReason> {
        guard let faceAnchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first else {
            return .failure(.noFaceAnchor)
        }

        guard faceAnchor.isTracked else {
            return .failure(.faceNotTracked)
        }

        return .success(faceAnchor)
    }

    private static func interPupillaryCandidate(faceAnchor: ARFaceAnchor,
                                                camera: ARCamera,
                                                uiOrientation: UIInterfaceOrientation,
                                                viewportSize: CGSize) -> Result<Double, TrueDepthBlockReason> {
        let leftTransform = simd_mul(faceAnchor.transform, faceAnchor.leftEyeTransform)
        let rightTransform = simd_mul(faceAnchor.transform, faceAnchor.rightEyeTransform)
        let leftPosition = worldPosition(from: leftTransform)
        let rightPosition = worldPosition(from: rightTransform)

        let distanceMM = Double(simd_distance(leftPosition, rightPosition)) * 1000.0
        guard distanceMM.isFinite,
              distanceMM >= Constants.minimumInterPupillaryMM,
              distanceMM <= Constants.maximumInterPupillaryMM else {
            return .failure(.ipdOutOfRange)
        }

        let projectedLeft = camera.projectPoint(leftPosition,
                                                orientation: uiOrientation,
                                                viewportSize: viewportSize)
        let projectedRight = camera.projectPoint(rightPosition,
                                                 orientation: uiOrientation,
                                                 viewportSize: viewportSize)
        let pixelDX = Double(abs(projectedRight.x - projectedLeft.x))
        guard pixelDX.isFinite,
              pixelDX >= Constants.minimumHorizontalPixels else {
            return .failure(.pixelBaselineTooSmall)
        }

        let mmPerPixel = distanceMM / pixelDX
        guard mmPerPixel.isFinite,
              mmPerPixel >= Constants.minMMPerPixel,
              mmPerPixel <= Constants.maxMMPerPixel else {
            return .failure(.scaleOutOfRange)
        }

        return .success(mmPerPixel)
    }

    private static func meshSamplingFailureReason(faceAnchor: ARFaceAnchor,
                                                  camera: ARCamera,
                                                  uiOrientation: UIInterfaceOrientation,
                                                  viewportSize: CGSize) -> TrueDepthBlockReason? {
        let vertices = faceAnchor.geometry.vertices
        guard let minimumXVertex = vertices.min(by: { $0.x < $1.x }),
              let maximumXVertex = vertices.max(by: { $0.x < $1.x }),
              let measurement = measurePair(first: minimumXVertex,
                                            second: maximumXVertex,
                                            faceAnchor: faceAnchor,
                                            camera: camera,
                                            uiOrientation: uiOrientation,
                                            viewportSize: viewportSize) else {
            return .noRecentSamples
        }

        if measurement.pixelDX < Constants.minimumHorizontalPixels {
            return .pixelBaselineTooSmall
        }

        return .noRecentSamples
    }

    private static func meshBasedCandidates(faceAnchor: ARFaceAnchor,
                                            camera: ARCamera,
                                            uiOrientation: UIInterfaceOrientation,
                                            viewportSize: CGSize) -> (horizontal: [Double], vertical: [Double]) {
        let vertices = faceAnchor.geometry.vertices
        guard vertices.count >= 2 else { return ([], []) }

        let horizontalPairs = candidatePairs(from: vertices.sorted { $0.x < $1.x })
        let verticalPairs = candidatePairs(from: vertices.sorted { $0.y < $1.y })

        let horizontal = candidateValues(from: horizontalPairs,
                                         axis: \.pixelDX,
                                         faceAnchor: faceAnchor,
                                         camera: camera,
                                         uiOrientation: uiOrientation,
                                         viewportSize: viewportSize)
        let vertical = candidateValues(from: verticalPairs,
                                       axis: \.pixelDY,
                                       faceAnchor: faceAnchor,
                                       camera: camera,
                                       uiOrientation: uiOrientation,
                                       viewportSize: viewportSize)
        return (horizontal, vertical)
    }

    private static func candidatePairs(from sortedVertices: [simd_float3]) -> [(simd_float3, simd_float3)] {
        guard sortedVertices.count >= 2 else { return [] }

        let trimCount = max(1, sortedVertices.count / Constants.meshPairTrimDivisor)
        let trimmed = Array(sortedVertices.dropFirst(trimCount).dropLast(trimCount))
        let workingSet = trimmed.count >= 2 ? trimmed : sortedVertices
        let pairCount = min(Constants.maxMeshPairs, workingSet.count / 2)
        guard pairCount > 0 else { return [] }

        return (0..<pairCount).map {
            (workingSet[$0], workingSet[workingSet.count - 1 - $0])
        }
    }

    private static func candidateValues(from pairs: [(simd_float3, simd_float3)],
                                        axis: KeyPath<PairMeasurement, Double>,
                                        faceAnchor: ARFaceAnchor,
                                        camera: ARCamera,
                                        uiOrientation: UIInterfaceOrientation,
                                        viewportSize: CGSize) -> [Double] {
        pairs.compactMap { pair in
            guard let measurement = measurePair(first: pair.0,
                                                second: pair.1,
                                                faceAnchor: faceAnchor,
                                                camera: camera,
                                                uiOrientation: uiOrientation,
                                                viewportSize: viewportSize) else {
                return nil
            }

            guard measurement.mmDistance >= Constants.minimumMeshDistanceMM,
                  measurement.mmDistance <= Constants.maximumMeshDistanceMM else {
                return nil
            }

            let pixels = measurement[keyPath: axis]
            guard pixels.isFinite,
                  pixels >= Constants.minimumHorizontalPixels else {
                return nil
            }

            let value = measurement.mmDistance / pixels
            guard value.isFinite,
                  value >= Constants.minMMPerPixel,
                  value <= Constants.maxMMPerPixel else {
                return nil
            }

            return value
        }
    }

    /// Mantem apenas candidatos da malha compatíveis com a escala principal derivada dos olhos.
    private static func supportedMeshCandidates(_ values: [Double],
                                                around reference: Double) -> [Double] {
        guard reference.isFinite, reference > 0 else { return [] }

        let minimum = reference * (1 - Constants.meshSupportToleranceRatio)
        let maximum = reference * (1 + Constants.meshSupportToleranceRatio)
        return values.filter { value in
            value.isFinite &&
            value >= minimum &&
            value <= maximum
        }
    }

    private static func measurePair(first: simd_float3,
                                    second: simd_float3,
                                    faceAnchor: ARFaceAnchor,
                                    camera: ARCamera,
                                    uiOrientation: UIInterfaceOrientation,
                                    viewportSize: CGSize) -> PairMeasurement? {
        let distanceMeters = euclideanDistance(first, second)
        guard distanceMeters.isFinite, distanceMeters > 0 else { return nil }

        let worldFirst = worldPosition(of: first, transform: faceAnchor.transform)
        let worldSecond = worldPosition(of: second, transform: faceAnchor.transform)
        let projectedFirst = camera.projectPoint(worldFirst,
                                                 orientation: uiOrientation,
                                                 viewportSize: viewportSize)
        let projectedSecond = camera.projectPoint(worldSecond,
                                                  orientation: uiOrientation,
                                                  viewportSize: viewportSize)

        let pixelDX = Double(abs(projectedSecond.x - projectedFirst.x))
        let pixelDY = Double(abs(projectedSecond.y - projectedFirst.y))
        guard pixelDX.isFinite, pixelDY.isFinite else { return nil }

        return PairMeasurement(mmDistance: distanceMeters * 1000.0,
                               pixelDX: pixelDX,
                               pixelDY: pixelDY)
    }

    private static func makeLocalFaceCalibration(faceAnchor: ARFaceAnchor,
                                                 camera: ARCamera,
                                                 worldToCamera: simd_float4x4,
                                                 uiOrientation: UIInterfaceOrientation,
                                                 viewportSize: CGSize,
                                                 focal: (fx: Double, fy: Double)) -> LocalFaceScaleCalibration? {
        let samples = faceAnchor.geometry.vertices.compactMap { vertex in
            makeLocalScaleSample(vertex: vertex,
                                 faceAnchor: faceAnchor,
                                 camera: camera,
                                 worldToCamera: worldToCamera,
                                 uiOrientation: uiOrientation,
                                 viewportSize: viewportSize,
                                 focal: focal)
        }

        guard samples.count >= Constants.minimumLocalSamples else { return nil }
        return groupedLocalCalibration(from: samples)
    }

    private static func makeLocalScaleSample(vertex: simd_float3,
                                             faceAnchor: ARFaceAnchor,
                                             camera: ARCamera,
                                             worldToCamera: simd_float4x4,
                                             uiOrientation: UIInterfaceOrientation,
                                             viewportSize: CGSize,
                                             focal: (fx: Double, fy: Double)) -> LocalFaceScaleSample? {
        let worldPoint = worldPosition(of: vertex, transform: faceAnchor.transform)
        let cameraPoint = cameraSpacePosition(of: worldPoint, worldToCamera: worldToCamera)
        let depthMeters = Double(-cameraPoint.z)

        guard depthMeters.isFinite,
              depthMeters >= Constants.localCalibrationMinimumDepthMeters,
              depthMeters <= Constants.localCalibrationMaximumDepthMeters else {
            return nil
        }

        let projected = camera.projectPoint(worldPoint,
                                            orientation: uiOrientation,
                                            viewportSize: viewportSize)
        guard projected.x.isFinite,
              projected.y.isFinite,
              projected.x >= 0,
              projected.y >= 0,
              projected.x <= CGFloat(viewportSize.width),
              projected.y <= CGFloat(viewportSize.height) else {
            return nil
        }

        let horizontalReference = (depthMeters * 1000.0 / focal.fx) * Double(viewportSize.width)
        let verticalReference = (depthMeters * 1000.0 / focal.fy) * Double(viewportSize.height)
        guard horizontalReference.isFinite,
              verticalReference.isFinite,
              horizontalReference > 0,
              verticalReference > 0 else {
            return nil
        }

        let normalizedPoint = NormalizedPoint.fromAbsolute(CGPoint(x: CGFloat(projected.x),
                                                                   y: CGFloat(projected.y)),
                                                           size: viewportSize)
        return LocalFaceScaleSample(point: normalizedPoint,
                                    horizontalReferenceMM: horizontalReference,
                                    verticalReferenceMM: verticalReference,
                                    depthMM: depthMeters * 1000.0)
    }

    private static func groupedLocalCalibration(from samples: [LocalFaceScaleSample]) -> LocalFaceScaleCalibration? {
        guard !samples.isEmpty else { return nil }

        let columns = Constants.localCalibrationGridColumns
        let rows = Constants.localCalibrationGridRows
        var buckets: [Int: LocalScaleAccumulator] = [:]

        for sample in samples {
            let column = min(max(Int(sample.point.x * CGFloat(columns)), 0), columns - 1)
            let row = min(max(Int(sample.point.y * CGFloat(rows)), 0), rows - 1)
            let key = (row * columns) + column
            var accumulator = buckets[key] ?? LocalScaleAccumulator()
            accumulator.append(sample)
            buckets[key] = accumulator
        }

        let averagedSamples = buckets.values.compactMap { $0.averagedSample() }
        guard averagedSamples.count >= Constants.minimumLocalSamples else { return nil }
        return LocalFaceScaleCalibration(samples: averagedSamples.sorted { first, second in
            first.point.y == second.point.y ? first.point.x < second.point.x : first.point.y < second.point.y
        })
    }

    private static func averageEyeDepth(faceAnchor: ARFaceAnchor,
                                        camera: ARCamera) -> Double {
        let worldToCamera = simd_inverse(camera.transform)
        let leftEyeWorld = simd_mul(faceAnchor.transform, faceAnchor.leftEyeTransform)
        let rightEyeWorld = simd_mul(faceAnchor.transform, faceAnchor.rightEyeTransform)
        let leftEyeCamera = simd_mul(worldToCamera, leftEyeWorld)
        let rightEyeCamera = simd_mul(worldToCamera, rightEyeWorld)

        let leftDepth = Double(-leftEyeCamera.columns.3.z)
        let rightDepth = Double(-rightEyeCamera.columns.3.z)
        let averageDepth = (leftDepth + rightDepth) * 0.5

        guard averageDepth.isFinite, averageDepth > 0 else {
            return 0.30
        }

        return averageDepth
    }

    // MARK: - Helpers geometricos
    private static func orientedViewportSize(resolution: CGSize,
                                             orientation: CGImagePropertyOrientation) -> CGSize {
        orientation.rotatesDimensions ?
            CGSize(width: resolution.height, height: resolution.width) :
            resolution
    }

    private static func orientedFocalLengths(from intrinsics: simd_float3x3,
                                             orientation: CGImagePropertyOrientation) -> (fx: Double, fy: Double) {
        let rawFX = Double(intrinsics.columns.0.x)
        let rawFY = Double(intrinsics.columns.1.y)
        return orientation.rotatesDimensions ? (rawFY, rawFX) : (rawFX, rawFY)
    }

    private static func worldPosition(of vertex: simd_float3,
                                      transform: simd_float4x4) -> simd_float3 {
        let position = simd_mul(transform, SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1))
        return simd_float3(position.x, position.y, position.z)
    }

    private static func worldPosition(from transform: simd_float4x4) -> simd_float3 {
        simd_float3(transform.columns.3.x,
                    transform.columns.3.y,
                    transform.columns.3.z)
    }

    private static func cameraSpacePosition(of worldPoint: simd_float3,
                                            worldToCamera: simd_float4x4) -> simd_float3 {
        let position = simd_mul(worldToCamera, SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1))
        return simd_float3(position.x, position.y, position.z)
    }

    private static func euclideanDistance(_ first: simd_float3,
                                          _ second: simd_float3) -> Double {
        Double(simd_length(first - second))
    }
}

// MARK: - Concurrency
/// O acesso ao estado interno fica protegido pela fila privada do estimador.
extension TrueDepthCalibrationEstimator: @unchecked Sendable {}

// MARK: - Estatistica robusta
private enum Statistics {
    static func robustMean(_ values: [Double]) -> Double? {
        let valid = values.filter { $0.isFinite }
        guard !valid.isEmpty else { return nil }

        let sorted = valid.sorted()
        let trimCount = Int(Double(sorted.count) * 0.10)
        let trimmed = Array(sorted.dropFirst(trimCount).dropLast(trimCount))
        let usable = trimmed.isEmpty ? sorted : trimmed
        let sum = usable.reduce(0, +)
        return sum / Double(usable.count)
    }

    static func normalizedDispersion(_ values: [Double],
                                     center: Double) -> Double {
        let valid = values.filter { $0.isFinite }
        guard !valid.isEmpty, center.isFinite, abs(center) > 0.0001 else { return 0 }

        let deviations = valid.map { abs($0 - center) / abs(center) }
        let sum = deviations.reduce(0, +)
        return sum / Double(deviations.count)
    }
}

// MARK: - Orientacao
private extension CGImagePropertyOrientation {
    var rotatesDimensions: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        default:
            return false
        }
    }
}
