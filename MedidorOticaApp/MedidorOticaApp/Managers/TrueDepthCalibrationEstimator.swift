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

    /// Valores coletados diretamente do mapa de profundidade ponto a ponto.
    private struct DepthCalibrationCandidates {
        let horizontal: [Double]
        let vertical: [Double]
        let meanDepth: Double
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

    /// Representa uma fonte de profundidade válida para o sensor TrueDepth.
    private struct DepthSource {
        let depthMap: CVPixelBuffer
        let confidenceMap: CVPixelBuffer?
        let intrinsics: DepthIntrinsics
        let scaleX: Double
        let scaleY: Double
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

    // MARK: - Entrada de dados
    /// Armazena uma nova amostra obtida a partir do frame informado.
    /// - Parameters:
    ///   - frame: Frame atual da sessão AR.
    ///   - cgOrientation: Orientação utilizada para gerar a imagem final.
    ///   - uiOrientation: Orientação da interface utilizada para projeção.
    func ingest(frame: ARFrame,
                cgOrientation: CGImagePropertyOrientation,
                uiOrientation: UIInterfaceOrientation) {
        guard let sample = Self.makeSample(from: frame,
                                           cgOrientation: cgOrientation,
                                           uiOrientation: uiOrientation) else { return }
        store(sample)
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
        if let currentSample = Self.makeSample(from: frame,
                                               cgOrientation: cgOrientation,
                                               uiOrientation: uiOrientation) {
            aggregatedSamples.append(currentSample)
            store(currentSample)
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
    private func store(_ sample: CalibrationSample) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
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

    // MARK: - Utilidades estáticas
    private static func makeSample(from frame: ARFrame,
                                   cgOrientation: CGImagePropertyOrientation,
                                   uiOrientation: UIInterfaceOrientation) -> CalibrationSample? {
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

        return CalibrationSample(mmPerPixelX: mmPerPixelX,
                                 mmPerPixelY: mmPerPixelY,
                                 horizontalWeight: refinedHorizontal.weight,
                                 verticalWeight: verticalEstimate.weight,
                                 timestamp: frame.timestamp)
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

        if let current = Self.makeSample(from: frame,
                                         cgOrientation: cgOrientation,
                                         uiOrientation: uiOrientation) {
            referenceSample = current
            store(current)
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

        let intrinsics = depthSource.intrinsics

        // Analisa o mapa completo sem amostragem para aproveitar cada pixel válido fornecido pelo TrueDepth.
        let fullCapacity = max(depthWidth * depthHeight, 1)

        var rawHorizontal: [Double] = []
        rawHorizontal.reserveCapacity(fullCapacity)
        var rawVertical: [Double] = []
        rawVertical.reserveCapacity(fullCapacity)

        var depthSum: Double = 0
        var depthCount: Int = 0

        for y in 0..<depthHeight {
            if y < marginY || y >= depthHeight - marginY { continue }
            // Linha atual do mapa de profundidade em formato contíguo.
            let rowPointer = depthBase.advanced(by: y * depthStride)
            // Linha subsequente, utilizada para medir vizinhos verticais.
            let nextRowPointer: UnsafePointer<Float32>? = (y + 1) < depthHeight ? depthBase.advanced(by: (y + 1) * depthStride) : nil

            // Confiança para a linha corrente e subsequente, quando disponível.
            let confidenceRow = confidenceBase.map { $0.advanced(by: y * confidenceStride) }
            let nextConfidenceRow: UnsafePointer<UInt8>? = {
                guard let base = confidenceBase, (y + 1) < depthHeight else { return nil }
                return base.advanced(by: (y + 1) * confidenceStride)
            }()

            for x in 0..<depthWidth {
                if x < marginX || x >= depthWidth - marginX { continue }
                let depthValue = rowPointer[x]
                guard depthValue.isFinite, depthValue > 0 else { continue }
                if let confidence = confidenceRow, confidence[x] < minimumConfidence { continue }

                depthSum += Double(depthValue)
                depthCount += 1

                if x + 1 < depthWidth && (x + 1) < depthWidth - marginX {
                    let neighborDepth = rowPointer[x + 1]
                    guard neighborDepth.isFinite, neighborDepth > 0 else { continue }
                    if let confidence = confidenceRow, confidence[x + 1] < minimumConfidence { continue }

                    let distance = millimetersBetween(x0: x,
                                                      y0: y,
                                                      depth0: depthValue,
                                                      x1: x + 1,
                                                      y1: y,
                                                      depth1: neighborDepth,
                                                      intrinsics: intrinsics)
                    let mmPerPixel = distance / scaleX
                    if CalibrationBounds.isValid(mmPerPixel: mmPerPixel) {
                        rawHorizontal.append(mmPerPixel)
                    }
                }

                if let nextRowPointer, (y + 1) < depthHeight - marginY {
                    let neighborDepth = nextRowPointer[x]
                    guard neighborDepth.isFinite, neighborDepth > 0 else { continue }
                    if let nextConfidence = nextConfidenceRow, nextConfidence[x] < minimumConfidence { continue }

                    let distance = millimetersBetween(x0: x,
                                                      y0: y,
                                                      depth0: depthValue,
                                                      x1: x,
                                                      y1: y + 1,
                                                      depth1: neighborDepth,
                                                      intrinsics: intrinsics)
                    let mmPerPixel = distance / scaleY
                    if CalibrationBounds.isValid(mmPerPixel: mmPerPixel) {
                        rawVertical.append(mmPerPixel)
                    }
                }
            }
        }

        guard depthCount > 0 else { return nil }

        let meanDepth = depthSum / Double(depthCount)
        let horizontal = cgOrientation.rotatesDimensions ? rawVertical : rawHorizontal
        let vertical = cgOrientation.rotatesDimensions ? rawHorizontal : rawVertical

        guard !horizontal.isEmpty, !vertical.isEmpty else { return nil }

        return DepthCalibrationCandidates(horizontal: horizontal,
                                           vertical: vertical,
                                           meanDepth: meanDepth)
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

            return DepthSource(depthMap: depthBuffer,
                               confidenceMap: sceneDepth.confidenceMap,
                               intrinsics: intrinsics,
                               scaleX: scaleX,
                               scaleY: scaleY)
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
                                         fy: calibration.columns.1.y,
                                         cx: calibration.columns.2.x,
                                         cy: calibration.columns.2.y)
        } else {
            let resolution = frame.camera.imageResolution
            intrinsics = scaledDepthIntrinsics(cameraIntrinsics: frame.camera.intrinsics,
                                               imageResolution: resolution,
                                               depthWidth: width,
                                               depthHeight: height)
        }

        let resolution = frame.camera.imageResolution
        let scaleX = Double(resolution.width) / Double(width)
        let scaleY = Double(resolution.height) / Double(height)
        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0 else { return nil }

        // AVDepthData não oferece mapa de confiança dedicado, portanto mantemos `nil`
        // e deixamos o filtro confiar apenas nos valores válidos do mapa de profundidade.
        return DepthSource(depthMap: depthBuffer,
                           confidenceMap: nil,
                           intrinsics: intrinsics,
                           scaleX: scaleX,
                           scaleY: scaleY)
    }

    /// Ajusta os intrínsecos originais da câmera para o tamanho do mapa de profundidade atual.
    private static func scaledDepthIntrinsics(cameraIntrinsics: simd_float3x3,
                                              imageResolution: CGSize,
                                              depthWidth: Int,
                                              depthHeight: Int) -> DepthIntrinsics {
        let scaleX = Float(depthWidth) / Float(imageResolution.width)
        let scaleY = Float(depthHeight) / Float(imageResolution.height)

        return DepthIntrinsics(fx: cameraIntrinsics.columns.0.x * scaleX,
                               fy: cameraIntrinsics.columns.1.y * scaleY,
                               cx: cameraIntrinsics.columns.2.x * scaleX,
                               cy: cameraIntrinsics.columns.2.y * scaleY)
    }

    /// Representa os intrínsecos utilizados para reprojetar os pixels do mapa de profundidade.
    private struct DepthIntrinsics {
        let fx: Float
        let fy: Float
        let cx: Float
        let cy: Float
    }

    /// Calcula a distância milimétrica entre dois pixels adjacentes no espaço da câmera.
    private static func millimetersBetween(x0: Int,
                                           y0: Int,
                                           depth0: Float32,
                                           x1: Int,
                                           y1: Int,
                                           depth1: Float32,
                                           intrinsics: DepthIntrinsics) -> Double {
        let pointA = unproject(pixelX: x0, pixelY: y0, depth: depth0, intrinsics: intrinsics)
        let pointB = unproject(pixelX: x1, pixelY: y1, depth: depth1, intrinsics: intrinsics)
        return Double(simd_distance(pointA, pointB)) * 1000
    }

    /// Converte um pixel do mapa de profundidade em coordenadas no espaço da câmera.
    private static func unproject(pixelX: Int,
                                  pixelY: Int,
                                  depth: Float32,
                                  intrinsics: DepthIntrinsics) -> simd_float3 {
        let z = max(depth, 0.0001)
        let x = (Float(pixelX) - intrinsics.cx) * z / intrinsics.fx
        let y = (Float(pixelY) - intrinsics.cy) * z / intrinsics.fy
        return simd_float3(x, y, z)
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
