//
//  TrueDepthCalibrationEstimator.swift
//  MedidorOticaApp
//
//  Estimador responsável por estabilizar a calibração a partir do sensor TrueDepth.
//

import Foundation
import ARKit
import UIKit

// MARK: - Estimador de Calibração TrueDepth
/// Consolida múltiplas amostras do sensor TrueDepth para gerar uma calibração submilimétrica.
final class TrueDepthCalibrationEstimator {
    // MARK: - Amostra interna
    private struct CalibrationSample {
        let mmPerPixelX: Double
        let mmPerPixelY: Double
        let horizontalWeight: Double
        let verticalWeight: Double
        let timestamp: TimeInterval
    }

    /// Valores consolidados do mapa de profundidade convertidos em mm/pixel.
    private struct DepthCalibrationCandidates {
        let horizontal: [Double]
        let vertical: [Double]
        let meanDepth: Double // Profundidade média em metros.
        let diagnostics: DepthFrameDiagnostics
    }

    // MARK: - Estruturas de Diagnóstico
    /// Estatísticas extraídas do mapa de profundidade durante a geração das amostras.
    private struct DepthFrameDiagnostics {
        let evaluatedPixelCount: Int
        let rawCandidateCount: Int
        let filteredCandidateCount: Int
        let highConfidencePixelCount: Int
    }

    /// Pacote com o resultado da amostra e os diagnósticos usados para auditoria.
    private struct SampleComputation {
        let sample: CalibrationSample
        let diagnostics: FrameDiagnostics
    }

    /// Últimas métricas extraídas do frame processado para rastrear a saúde do sensor.
    private struct FrameDiagnostics {
        let timestamp: TimeInterval
        let mmPerPixelX: Double
        let mmPerPixelY: Double
        let meanDepth: Double
        let horizontalWeight: Double
        let verticalWeight: Double
        let evaluatedPixelCount: Int
        let rawCandidateCount: Int
        let filteredCandidateCount: Int
        let highConfidencePixelCount: Int
    }

    /// Diagnóstico público resumido que permite verificar a integridade da calibração.
    struct EstimatorDiagnostics {
        let storedSampleCount: Int
        let recentSampleCount: Int
        let lastTimestamp: TimeInterval?
        let lastHorizontalMMPerPixel: Double?
        let lastVerticalMMPerPixel: Double?
        let lastMeanDepth: Double?
        let lastHorizontalWeight: Double?
        let lastVerticalWeight: Double?
        let evaluatedPixelCount: Int
        let rawCandidateCount: Int
        let filteredCandidateCount: Int
        let highConfidencePixelCount: Int
    }

    /// Resultado estatístico robusto para um eixo da calibração.
    private struct AxisEstimate {
        let mean: Double
        let weight: Double
    }

    /// Valor ponderado utilizado para médias robustas.
    private struct WeightedValue {
        let value: Double
        let weight: Double
    }

    /// Representa uma fonte de profundidade válida já com fatores de escala prontos para conversão.
    private struct DepthSource {
        let depthMap: CVPixelBuffer
        let confidenceMap: CVPixelBuffer?
        let scaleX: Double
        let scaleY: Double
        let inverseFx: Double
        let inverseFy: Double
    }

    /// Faixas utilizadas para validar as amostras provenientes do TrueDepth.
    private enum CalibrationBounds {
        static let interpupillaryRange = 40.0...80.0
        static let depthRange = 0.08...1.2
        static let mmPerPixelRange = 0.015...0.8
        static let minimumPupilPixels: Double = 2
        static let minimumAxisSamples = 24
        static let analysisMarginFraction = 0.08
        static let minimumAxisWeight: Double = 25
        static let maximumAxisWeight: Double = 6000
        static let agreementToleranceFactor = 0.12
        static let minimumAgreementTolerance = 0.002

        static func isValid(mmPerPixel value: Double) -> Bool {
            mmPerPixelRange.contains(value) && value.isFinite
        }

        static func clampedWeight(_ weight: Double) -> Double {
            guard weight.isFinite else { return minimumAxisWeight }
            return min(max(weight, minimumAxisWeight), maximumAxisWeight)
        }

        static func hasSufficientWeight(_ weight: Double) -> Bool {
            weight.isFinite && weight >= minimumAxisWeight
        }

        static func isRecent(_ sample: CalibrationSample,
                             referenceTime: TimeInterval,
                             lifetime: TimeInterval) -> Bool {
            referenceTime - sample.timestamp <= lifetime * 1.5
        }
    }

    // MARK: - Parâmetros de suavização
    private let maxSamples = 90
    private let sampleLifetime: TimeInterval = 1.5
    private let accessQueue = DispatchQueue(label: "com.oticaManzolli.trueDepthEstimator", qos: .userInitiated, attributes: .concurrent)

    private var samples: [CalibrationSample] = []
    private var lastFrameDiagnostics: FrameDiagnostics?

    // MARK: - Entrada de dados
    /// Armazena uma nova amostra obtida a partir do frame informado.
    /// - Parameters:
    ///   - frame: Frame atual da sessão AR.
    ///   - cgOrientation: Orientação utilizada para gerar a imagem final.
    ///   - uiOrientation: Orientação da interface utilizada para projeção.
    func ingest(frame: ARFrame,
                cgOrientation: CGImagePropertyOrientation,
                uiOrientation: UIInterfaceOrientation) {
        guard let computation = Self.computeSample(from: frame,
                                                   cgOrientation: cgOrientation,
                                                   uiOrientation: uiOrientation) else { return }
        store(computation.sample, diagnostics: computation.diagnostics)
    }

    // MARK: - Calibração refinada
    /// Retorna uma calibração estabilizada considerando múltiplas amostras recentes.
    /// - Parameters:
    ///   - frame: Frame utilizado na captura atual.
    ///   - cropRect: Recorte aplicado à imagem final.
    ///   - orientedSize: Tamanho da imagem já orientada (antes do recorte).
    ///   - cgOrientation: Orientação utilizada para converter o buffer.
    ///   - uiOrientation: Orientação atual da interface.
    /// - Returns: Calibração refinada ou `nil` quando não há dados confiáveis.
    func refinedCalibration(for frame: ARFrame,
                            cropRect: CGRect,
                            cgOrientation: CGImagePropertyOrientation,
                            uiOrientation: UIInterfaceOrientation) -> PostCaptureCalibration? {
        guard cropRect.width > 0, cropRect.height > 0 else { return nil }

        var aggregatedSamples: [CalibrationSample] = []
        // Garante que a amostra do frame atual também seja considerada imediatamente.
        if let computation = Self.computeSample(from: frame,
                                                cgOrientation: cgOrientation,
                                                uiOrientation: uiOrientation) {
            aggregatedSamples.append(computation.sample)
            store(computation.sample, diagnostics: computation.diagnostics)
        }

        let referenceTime = frame.timestamp
        let filteredSamples = accessQueue.sync {
            samples.filter { referenceTime - $0.timestamp <= sampleLifetime }
        }

        aggregatedSamples.append(contentsOf: filteredSamples)
        if aggregatedSamples.isEmpty,
           let fallback = mostRecentSample(referenceTime: referenceTime) {
            aggregatedSamples.append(fallback)
        }
        guard !aggregatedSamples.isEmpty else { return nil }

        guard let mmPerPixelX = Self.stabilizedMean(for: aggregatedSamples,
                                                    valueKeyPath: \.mmPerPixelX,
                                                    weightKeyPath: \.horizontalWeight),
              let mmPerPixelY = Self.stabilizedMean(for: aggregatedSamples,
                                                    valueKeyPath: \.mmPerPixelY,
                                                    weightKeyPath: \.verticalWeight),
              CalibrationBounds.isValid(mmPerPixel: mmPerPixelX),
              CalibrationBounds.isValid(mmPerPixel: mmPerPixelY) else { return nil }

        let horizontalReference = mmPerPixelX * Double(cropRect.width)
        let verticalReference = mmPerPixelY * Double(cropRect.height)

        guard horizontalReference.isFinite, verticalReference.isFinite,
              horizontalReference > 0, verticalReference > 0 else { return nil }

        return PostCaptureCalibration(horizontalReferenceMM: horizontalReference,
                                      verticalReferenceMM: verticalReference)
    }

    // MARK: - Armazenamento interno
    private func store(_ sample: CalibrationSample, diagnostics: FrameDiagnostics) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.lastFrameDiagnostics = diagnostics
            guard CalibrationBounds.hasSufficientWeight(sample.horizontalWeight),
                  CalibrationBounds.hasSufficientWeight(sample.verticalWeight) else { return }
            self.samples.append(sample)
            self.pruneSamples(referenceTime: sample.timestamp)
        }
    }

    private func pruneSamples(referenceTime: TimeInterval) {
        samples.removeAll { referenceTime - $0.timestamp > sampleLifetime }
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    /// Remove todas as amostras e diagnósticos acumulados, útil ao reiniciar a sessão.
    func reset() {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.samples.removeAll(keepingCapacity: false)
            self.lastFrameDiagnostics = nil
        }
    }

    /// Retorna a amostra confiável mais recente dentro da janela aceitável.
    private func mostRecentSample(referenceTime: TimeInterval) -> CalibrationSample? {
        accessQueue.sync {
            samples.reversed().first { CalibrationBounds.isRecent($0,
                                                                  referenceTime: referenceTime,
                                                                  lifetime: sampleLifetime) &&
                                       CalibrationBounds.hasSufficientWeight($0.horizontalWeight) &&
                                       CalibrationBounds.hasSufficientWeight($0.verticalWeight) }
        }
    }

    // MARK: - Diagnóstico Público
    /// Retorna estatísticas atualizadas permitindo validar se o TrueDepth está entregando dados consistentes.
    func diagnostics() -> EstimatorDiagnostics {
        accessQueue.sync {
            let storedCount = samples.count
            let lastFrame = lastFrameDiagnostics
            let referenceTime = lastFrame?.timestamp ?? samples.last?.timestamp

            let recentCount: Int
            if let referenceTime {
                recentCount = samples.filter {
                    CalibrationBounds.isRecent($0,
                                               referenceTime: referenceTime,
                                               lifetime: sampleLifetime)
                }.count
            } else {
                recentCount = 0
            }

            return EstimatorDiagnostics(storedSampleCount: storedCount,
                                         recentSampleCount: recentCount,
                                         lastTimestamp: lastFrame?.timestamp,
                                         lastHorizontalMMPerPixel: lastFrame?.mmPerPixelX,
                                         lastVerticalMMPerPixel: lastFrame?.mmPerPixelY,
                                         lastMeanDepth: lastFrame?.meanDepth,
                                         lastHorizontalWeight: lastFrame?.horizontalWeight,
                                         lastVerticalWeight: lastFrame?.verticalWeight,
                                         evaluatedPixelCount: lastFrame?.evaluatedPixelCount ?? 0,
                                         rawCandidateCount: lastFrame?.rawCandidateCount ?? 0,
                                         filteredCandidateCount: lastFrame?.filteredCandidateCount ?? 0,
                                         highConfidencePixelCount: lastFrame?.highConfidencePixelCount ?? 0)
        }
    }

    // MARK: - Utilidades estáticas
    private static func computeSample(from frame: ARFrame,
                                      cgOrientation: CGImagePropertyOrientation,
                                      uiOrientation: UIInterfaceOrientation) -> SampleComputation? {
        guard case .normal = frame.camera.trackingState else { return nil }
        guard let faceAnchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first,
              faceAnchor.isTracked else { return nil }

        let viewportSize = orientedViewportSize(resolution: frame.camera.imageResolution,
                                                orientation: cgOrientation)

        guard let depthCandidates = perPixelCandidates(from: frame,
                                                       cgOrientation: cgOrientation) else { return nil }
        guard CalibrationBounds.depthRange.contains(depthCandidates.meanDepth) else { return nil }

        guard let horizontalEstimate = robustAxisEstimate(from: depthCandidates.horizontal),
              let verticalEstimate = robustAxisEstimate(from: depthCandidates.vertical) else { return nil }

        let ipdCandidate = interPupillaryCandidate(faceAnchor: faceAnchor,
                                                   camera: frame.camera,
                                                   uiOrientation: uiOrientation,
                                                   viewportSize: viewportSize)
        let refinedHorizontal = mergeHorizontalEstimate(base: horizontalEstimate,
                                                        ipdCandidate: ipdCandidate)

        let mmPerPixelX = refinedHorizontal.mean
        let mmPerPixelY = verticalEstimate.mean

        guard CalibrationBounds.isValid(mmPerPixel: mmPerPixelX),
              CalibrationBounds.isValid(mmPerPixel: mmPerPixelY),
              CalibrationBounds.hasSufficientWeight(refinedHorizontal.weight),
              CalibrationBounds.hasSufficientWeight(verticalEstimate.weight) else { return nil }

        let sample = CalibrationSample(mmPerPixelX: mmPerPixelX,
                                       mmPerPixelY: mmPerPixelY,
                                       horizontalWeight: refinedHorizontal.weight,
                                       verticalWeight: verticalEstimate.weight,
                                       timestamp: frame.timestamp)

        let frameDiagnostics = FrameDiagnostics(timestamp: frame.timestamp,
                                                mmPerPixelX: mmPerPixelX,
                                                mmPerPixelY: mmPerPixelY,
                                                meanDepth: depthCandidates.meanDepth,
                                                horizontalWeight: refinedHorizontal.weight,
                                                verticalWeight: verticalEstimate.weight,
                                                evaluatedPixelCount: depthCandidates.diagnostics.evaluatedPixelCount,
                                                rawCandidateCount: depthCandidates.diagnostics.rawCandidateCount,
                                                filteredCandidateCount: depthCandidates.diagnostics.filteredCandidateCount,
                                                highConfidencePixelCount: depthCandidates.diagnostics.highConfidencePixelCount)

        return SampleComputation(sample: sample, diagnostics: frameDiagnostics)
    }

    /// Gera uma calibração imediata utilizando apenas o frame atual.
    /// - Parameters:
    ///   - frame: Frame atual da sessão AR.
    ///   - cropRect: Recorte aplicado à imagem final.
    ///   - cgOrientation: Orientação utilizada para o buffer de imagem.
    ///   - uiOrientation: Orientação atual da interface.
    /// - Returns: Calibração calculada a partir dos dados mais recentes ou `nil` se não for possível calcular.
    func instantCalibration(for frame: ARFrame,
                            cropRect: CGRect,
                            cgOrientation: CGImagePropertyOrientation,
                            uiOrientation: UIInterfaceOrientation) -> PostCaptureCalibration? {
        guard cropRect.width > 0, cropRect.height > 0 else { return nil }

        var referenceSample: CalibrationSample?

        if let computation = Self.computeSample(from: frame,
                                                cgOrientation: cgOrientation,
                                                uiOrientation: uiOrientation) {
            referenceSample = computation.sample
            store(computation.sample, diagnostics: computation.diagnostics)
        } else {
            referenceSample = mostRecentSample(referenceTime: frame.timestamp)
        }

        guard let sample = referenceSample else { return nil }

        let mmPerPixelX = sample.mmPerPixelX
        let mmPerPixelY = sample.mmPerPixelY

        guard mmPerPixelX.isFinite, mmPerPixelY.isFinite, mmPerPixelX > 0, mmPerPixelY > 0 else { return nil }

        let horizontalReference = sample.mmPerPixelX * Double(cropRect.width)
        let verticalReference = sample.mmPerPixelY * Double(cropRect.height)

        guard horizontalReference.isFinite, verticalReference.isFinite,
              horizontalReference > 0, verticalReference > 0 else { return nil }

        return PostCaptureCalibration(horizontalReferenceMM: horizontalReference,
                                      verticalReferenceMM: verticalReference)
    }

    private static func orientedViewportSize(resolution: CGSize,
                                             orientation: CGImagePropertyOrientation) -> CGSize {
        if orientation.rotatesDimensions {
            return CGSize(width: resolution.height, height: resolution.width)
        }
        return resolution
    }

    /// Calcula um candidato de mm/pixel horizontal utilizando a distância interpupilar.
    private static func interPupillaryCandidate(faceAnchor: ARFaceAnchor,
                                                camera: ARCamera,
                                                uiOrientation: UIInterfaceOrientation,
                                                viewportSize: CGSize) -> Double? {
        let leftTransform = simd_mul(faceAnchor.transform, faceAnchor.leftEyeTransform)
        let rightTransform = simd_mul(faceAnchor.transform, faceAnchor.rightEyeTransform)

        let leftPosition = worldPosition(from: leftTransform)
        let rightPosition = worldPosition(from: rightTransform)

        let distanceMM = Double(simd_distance(leftPosition, rightPosition)) * 1000
        guard CalibrationBounds.interpupillaryRange.contains(distanceMM) else { return nil }

        let projectedLeft = camera.projectPoint(leftPosition,
                                                orientation: uiOrientation,
                                                viewportSize: viewportSize)
        let projectedRight = camera.projectPoint(rightPosition,
                                                 orientation: uiOrientation,
                                                 viewportSize: viewportSize)

        let pixelDiffX = Double(abs(projectedRight.x - projectedLeft.x))
        guard pixelDiffX.isFinite, pixelDiffX > CalibrationBounds.minimumPupilPixels else { return nil }

        let mmPerPixelX = distanceMM / pixelDiffX
        guard CalibrationBounds.isValid(mmPerPixel: mmPerPixelX) else { return nil }

        return mmPerPixelX
    }

    /// Extrai a posição no espaço tridimensional a partir de uma matriz de transformação.
    private static func worldPosition(from transform: simd_float4x4) -> simd_float3 {
        simd_float3(transform.columns.3.x,
                    transform.columns.3.y,
                    transform.columns.3.z)
    }

    // MARK: - Estatística robusta
    /// Calcula uma média ponderada robusta a partir da lista de amostras informada.
    private static func stabilizedMean(for samples: [CalibrationSample],
                                       valueKeyPath: KeyPath<CalibrationSample, Double>,
                                       weightKeyPath: KeyPath<CalibrationSample, Double>) -> Double? {
        let entries: [WeightedValue] = samples.compactMap { sample in
            let value = sample[keyPath: valueKeyPath]
            let weight = sample[keyPath: weightKeyPath]
            guard CalibrationBounds.isValid(mmPerPixel: value),
                  CalibrationBounds.hasSufficientWeight(weight) else { return nil }
            return WeightedValue(value: value, weight: weight)
        }
        return stabilizedWeightedMean(entries)
    }

    /// Calcula média ponderada descartando outliers com base no desvio absoluto mediano.
    private static func stabilizedWeightedMean(_ entries: [WeightedValue]) -> Double? {
        let valid = entries.filter { $0.weight > 0 && $0.value.isFinite }
        guard !valid.isEmpty else { return nil }

        let sortedValues = valid.map { $0.value }.sorted()
        guard let medianValue = median(of: sortedValues) else { return nil }

        let deviations = sortedValues.map { abs($0 - medianValue) }
        let mad = median(of: deviations) ?? 0
        let threshold = max(mad * 3, 0.0002)

        let filtered = valid.filter { abs($0.value - medianValue) <= threshold }
        let candidates = filtered.isEmpty ? valid : filtered
        return weightedMean(candidates)
    }

    /// Média ponderada simples.
    private static func weightedMean(_ values: [WeightedValue]) -> Double? {
        let totalWeight = values.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let weightedSum = values.reduce(0) { $0 + ($1.value * $1.weight) }
        return weightedSum / totalWeight
    }

    /// Calcula a mediana de um conjunto de valores.
    private static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let midIndex = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[midIndex - 1] + sorted[midIndex]) / 2
        } else {
            return sorted[midIndex]
        }
    }

    /// Gera uma estimativa robusta para um eixo considerando as leituras do mapa de profundidade.
    private static func robustAxisEstimate(from values: [Double]) -> AxisEstimate? {
        let valid = values.filter { CalibrationBounds.isValid(mmPerPixel: $0) }
        guard valid.count >= CalibrationBounds.minimumAxisSamples else { return nil }

        let sorted = valid.sorted()
        guard let medianValue = median(of: sorted) else { return nil }

        let deviations = sorted.map { abs($0 - medianValue) }
        let mad = median(of: deviations) ?? 0
        let sigma = mad * 1.4826
        let rejectionThreshold = max(sigma * 3, 0.0002)
        let filtered = sorted.filter { abs($0 - medianValue) <= rejectionThreshold }
        let candidates = filtered.isEmpty ? sorted : filtered
        guard !candidates.isEmpty else { return nil }

        let mean = candidates.reduce(0, +) / Double(candidates.count)
        let varianceDenominator = max(candidates.count - 1, 1)
        let variance = candidates.reduce(0) { $0 + pow($1 - mean, 2) } / Double(varianceDenominator)
        let standardDeviation = sqrt(max(variance, 0))

        let densityFactor = sqrt(Double(candidates.count))
        let stabilityFactor = 1.0 / max(standardDeviation, 0.0003)
        let weight = CalibrationBounds.clampedWeight(densityFactor * stabilityFactor)

        return AxisEstimate(mean: mean, weight: weight)
    }

    /// Ajusta a estimativa horizontal utilizando a distância interpupilar quando ela estiver alinhada.
    private static func mergeHorizontalEstimate(base: AxisEstimate,
                                                ipdCandidate: Double?) -> AxisEstimate {
        guard let ipdCandidate else { return base }
        guard CalibrationBounds.isValid(mmPerPixel: ipdCandidate) else { return base }

        let tolerance = max(base.mean * CalibrationBounds.agreementToleranceFactor,
                            CalibrationBounds.minimumAgreementTolerance)
        guard abs(ipdCandidate - base.mean) <= tolerance else { return base }

        let ipdWeight = CalibrationBounds.clampedWeight(base.weight * 0.45)
        let combinedWeight = CalibrationBounds.clampedWeight(base.weight + ipdWeight)
        let combinedMean = ((base.mean * base.weight) + (ipdCandidate * ipdWeight)) / combinedWeight

        return AxisEstimate(mean: combinedMean,
                            weight: combinedWeight)
    }

    // MARK: - Análise do Mapa de Profundidade
    /// Converte os dados do mapa de profundidade em candidatos de mm/pixel analisando cada ponto válido.
    private static func perPixelCandidates(from frame: ARFrame,
                                           cgOrientation: CGImagePropertyOrientation) -> DepthCalibrationCandidates? {
        guard let depthSource = makeDepthSource(from: frame) else { return nil }

        let depthBuffer = depthSource.depthMap
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let depthWidth = CVPixelBufferGetWidth(depthBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthBuffer)
        guard depthWidth > 1, depthHeight > 1 else { return nil }

        let rawMarginX = Int(Double(depthWidth) * CalibrationBounds.analysisMarginFraction)
        let rawMarginY = Int(Double(depthHeight) * CalibrationBounds.analysisMarginFraction)
        let marginX = rawMarginX * 2 < depthWidth ? rawMarginX : 0
        let marginY = rawMarginY * 2 < depthHeight ? rawMarginY : 0

        guard let depthBaseMutable = CVPixelBufferGetBaseAddress(depthBuffer)?.assumingMemoryBound(to: Float32.self) else {
            return nil
        }
        let depthBase = UnsafePointer<Float32>(depthBaseMutable)
        let depthStride = CVPixelBufferGetBytesPerRow(depthBuffer) / MemoryLayout<Float32>.size

        // Garante leitura segura do mapa de confiança, que pode não ser enviado pelo sensor.
        var lockedConfidenceBuffer: CVPixelBuffer?
        let confidenceBuffer = depthSource.confidenceMap
        var confidenceStride = 0
        var confidenceBase: UnsafePointer<UInt8>?
        if let buffer = confidenceBuffer,
           CVPixelBufferGetWidth(buffer) == depthWidth,
           CVPixelBufferGetHeight(buffer) == depthHeight {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            lockedConfidenceBuffer = buffer
            confidenceStride = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<UInt8>.size
            if let mutableConfidence = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) {
                confidenceBase = UnsafePointer<UInt8>(mutableConfidence)
            }
        }
        defer {
            if let buffer = lockedConfidenceBuffer {
                CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            }
        }

        // Apenas considera pixels classificados com confiança alta pelo hardware.
        let minimumConfidence: UInt8 = 2

        let scaleX = depthSource.scaleX
        let scaleY = depthSource.scaleY
        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0 else { return nil }

        // Armazena candidatos convertidos diretamente de profundidade para mm/pixel.
        struct DepthPixelCandidate {
            let mmHorizontal: Double
            let mmVertical: Double
            let depth: Double
        }

        let fullCapacity = max(depthWidth * depthHeight, 1)
        var candidates = ContiguousArray<DepthPixelCandidate>()
        candidates.reserveCapacity(fullCapacity)

        var evaluatedPixels = 0
        var highConfidencePixels = 0

        for y in 0..<depthHeight {
            if y < marginY || y >= depthHeight - marginY { continue }
            let rowPointer = depthBase.advanced(by: y * depthStride)
            let confidenceRow = confidenceBase.map { $0.advanced(by: y * confidenceStride) }

            for x in 0..<depthWidth {
                if x < marginX || x >= depthWidth - marginX { continue }
                let depthValue = rowPointer[x]
                guard depthValue.isFinite, depthValue > 0 else { continue }
                evaluatedPixels += 1

                if let confidence = confidenceRow, confidence[x] < minimumConfidence { continue }
                highConfidencePixels += 1

                let depthMeters = Double(depthValue)
                let mmHorizontal = millimetersPerPixel(depth: depthMeters,
                                                       inverseFocal: depthSource.inverseFx,
                                                       scale: scaleX)
                let mmVertical = millimetersPerPixel(depth: depthMeters,
                                                     inverseFocal: depthSource.inverseFy,
                                                     scale: scaleY)

                guard CalibrationBounds.isValid(mmPerPixel: mmHorizontal),
                      CalibrationBounds.isValid(mmPerPixel: mmVertical) else { continue }

                candidates.append(DepthPixelCandidate(mmHorizontal: mmHorizontal,
                                                      mmVertical: mmVertical,
                                                      depth: depthMeters))
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Filtra ruídos extremos em torno da mediana para garantir profundidade estável.
        let depthValues = candidates.map { $0.depth }
        guard let medianDepth = median(of: depthValues) else { return nil }
        let depthDeviations = depthValues.map { abs($0 - medianDepth) }
        let depthMad = median(of: depthDeviations) ?? 0
        let depthThreshold = max(depthMad * 2.5, 0.0005)

        let stableCandidates = candidates.filter { abs($0.depth - medianDepth) <= depthThreshold }
        let effectiveCandidates = stableCandidates.isEmpty ? candidates : stableCandidates

        let meanDepth = effectiveCandidates.reduce(0) { $0 + $1.depth } / Double(effectiveCandidates.count)

        // Separa os valores de mm/pixel por eixo após a filtragem robusta.
        let rawHorizontal = effectiveCandidates.map { $0.mmHorizontal }
        let rawVertical = effectiveCandidates.map { $0.mmVertical }

        let horizontal = cgOrientation.rotatesDimensions ? rawVertical : rawHorizontal
        let vertical = cgOrientation.rotatesDimensions ? rawHorizontal : rawVertical

        guard !horizontal.isEmpty, !vertical.isEmpty else { return nil }

        let diagnostics = DepthFrameDiagnostics(evaluatedPixelCount: evaluatedPixels,
                                                rawCandidateCount: candidates.count,
                                                filteredCandidateCount: effectiveCandidates.count,
                                                highConfidencePixelCount: highConfidencePixels)

        return DepthCalibrationCandidates(horizontal: horizontal,
                                           vertical: vertical,
                                           meanDepth: meanDepth,
                                           diagnostics: diagnostics)
    }

    /// Seleciona a fonte de profundidade mais confiável disponível no frame atual.
    private static func makeDepthSource(from frame: ARFrame) -> DepthSource? {
        if let sceneDepth = frame.sceneDepth ?? frame.smoothedSceneDepth {
            let depthBuffer = sceneDepth.depthMap
            let resolution = frame.camera.imageResolution
            let width = CVPixelBufferGetWidth(depthBuffer)
            let height = CVPixelBufferGetHeight(depthBuffer)
            let scaleX = Double(resolution.width) / Double(width)
            let scaleY = Double(resolution.height) / Double(height)
            guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0 else { return nil }

            let intrinsics = scaledDepthIntrinsics(cameraIntrinsics: frame.camera.intrinsics,
                                                   imageResolution: resolution,
                                                   depthWidth: width,
                                                   depthHeight: height)

            guard intrinsics.fx.isFinite, intrinsics.fy.isFinite,
                  intrinsics.fx > 0, intrinsics.fy > 0 else { return nil }
            let inverseFx = 1.0 / Double(intrinsics.fx)
            let inverseFy = 1.0 / Double(intrinsics.fy)

            return DepthSource(depthMap: depthBuffer,
                               confidenceMap: sceneDepth.confidenceMap,
                               scaleX: scaleX,
                               scaleY: scaleY,
                               inverseFx: inverseFx,
                               inverseFy: inverseFy)
        }

        guard let capturedDepth = frame.capturedDepthData else { return nil }
        let depthData = capturedDepth.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let depthBuffer = depthData.depthDataMap
        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        guard width > 1, height > 1 else { return nil }

        let intrinsics: DepthIntrinsics
        if let calibration = depthData.cameraCalibrationData?.intrinsicMatrix {
            intrinsics = DepthIntrinsics(fx: calibration.columns.0.x,
                                         fy: calibration.columns.1.y)
        } else {
            let resolution = frame.camera.imageResolution
            intrinsics = scaledDepthIntrinsics(cameraIntrinsics: frame.camera.intrinsics,
                                               imageResolution: resolution,
                                               depthWidth: width,
                                               depthHeight: height)
        }

        guard intrinsics.fx.isFinite, intrinsics.fy.isFinite,
              intrinsics.fx > 0, intrinsics.fy > 0 else { return nil }
        let inverseFx = 1.0 / Double(intrinsics.fx)
        let inverseFy = 1.0 / Double(intrinsics.fy)

        let resolution = frame.camera.imageResolution
        let scaleX = Double(resolution.width) / Double(width)
        let scaleY = Double(resolution.height) / Double(height)
        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0 else { return nil }

        // AVDepthData não oferece mapa de confiança dedicado, portanto mantemos `nil`
        // e deixamos o filtro confiar apenas nos valores válidos do mapa de profundidade.
        return DepthSource(depthMap: depthBuffer,
                           confidenceMap: nil,
                           scaleX: scaleX,
                           scaleY: scaleY,
                           inverseFx: inverseFx,
                           inverseFy: inverseFy)
    }

    /// Ajusta os intrínsecos originais da câmera para o tamanho do mapa de profundidade atual.
    private static func scaledDepthIntrinsics(cameraIntrinsics: simd_float3x3,
                                              imageResolution: CGSize,
                                              depthWidth: Int,
                                              depthHeight: Int) -> DepthIntrinsics {
        let scaleX = Float(depthWidth) / Float(imageResolution.width)
        let scaleY = Float(depthHeight) / Float(imageResolution.height)

        return DepthIntrinsics(fx: cameraIntrinsics.columns.0.x * scaleX,
                               fy: cameraIntrinsics.columns.1.y * scaleY)
    }

    /// Representa os intrínsecos utilizados para reprojetar os pixels do mapa de profundidade.
    private struct DepthIntrinsics {
        let fx: Float
        let fy: Float
    }

    /// Converte profundidade e intrínsecos em milímetros por pixel para o eixo informado.
    private static func millimetersPerPixel(depth: Double,
                                            inverseFocal: Double,
                                            scale: Double) -> Double {
        let mmPerDepthPixel = depth * inverseFocal * 1000.0
        return mmPerDepthPixel / scale
    }
}

// MARK: - Orientação auxiliar
extension CGImagePropertyOrientation {
    /// Indica quando a orientação aplica rotação de 90º, invertendo largura e altura.
    var rotatesDimensions: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        default:
            return false
        }
    }
}
