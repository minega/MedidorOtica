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
        let timestamp: TimeInterval
    }

    /// Valores coletados diretamente do mapa de profundidade ponto a ponto.
    private struct DepthCalibrationCandidates {
        let horizontal: [Double]
        let vertical: [Double]
        let meanDepth: Double
    }

    /// Faixas utilizadas para validar as amostras provenientes do TrueDepth.
    private enum CalibrationBounds {
        static let interpupillaryRange = 40.0...80.0
        static let depthRange = 0.08...1.2
        static let mmPerPixelRange = 0.015...0.8
        static let minimumPupilPixels: Double = 2

        static func isValid(mmPerPixel value: Double) -> Bool {
            mmPerPixelRange.contains(value) && value.isFinite
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

        guard let mmPerPixelX = Self.stabilizedMean(aggregatedSamples.map { $0.mmPerPixelX }),
              let mmPerPixelY = Self.stabilizedMean(aggregatedSamples.map { $0.mmPerPixelY }),
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
                                                                  lifetime: sampleLifetime) }
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

        var horizontalCandidates = depthCandidates.horizontal
        var verticalCandidates = depthCandidates.vertical

        if let ipdCandidate = interPupillaryCandidate(faceAnchor: faceAnchor,
                                                      camera: frame.camera,
                                                      uiOrientation: uiOrientation,
                                                      viewportSize: viewportSize) {
            horizontalCandidates.append(ipdCandidate)
        }

        guard let mmPerPixelX = stabilizedMean(horizontalCandidates),
              let mmPerPixelY = stabilizedMean(verticalCandidates),
              CalibrationBounds.isValid(mmPerPixel: mmPerPixelX),
              CalibrationBounds.isValid(mmPerPixel: mmPerPixelY) else { return nil }

        return CalibrationSample(mmPerPixelX: mmPerPixelX,
                                 mmPerPixelY: mmPerPixelY,
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

    private static func stabilizedMean(_ values: [Double]) -> Double? {
        let valid = values.filter { $0.isFinite }
        guard !valid.isEmpty else { return nil }
        let sorted = valid.sorted()
        let trimCount = Int(Double(sorted.count) * 0.1)
        let trimmed = sorted.dropFirst(trimCount).dropLast(trimCount)
        let target = trimmed.isEmpty ? sorted : Array(trimmed)
        guard !target.isEmpty else { return nil }
        let sum = target.reduce(0, +)
        return sum / Double(target.count)
    }

    // MARK: - Análise do Mapa de Profundidade
    /// Converte os dados do mapa de profundidade em candidatos de mm/pixel analisando cada ponto válido.
    private static func perPixelCandidates(from frame: ARFrame,
                                           cgOrientation: CGImagePropertyOrientation) -> DepthCalibrationCandidates? {
        guard let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth else { return nil }

        let depthBuffer = depthData.depthMap
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let depthWidth = CVPixelBufferGetWidth(depthBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthBuffer)
        guard depthWidth > 1, depthHeight > 1 else { return nil }

        guard let depthBase = CVPixelBufferGetBaseAddress(depthBuffer)?.assumingMemoryBound(to: Float32.self) else {
            return nil
        }
        let depthStride = CVPixelBufferGetBytesPerRow(depthBuffer) / MemoryLayout<Float32>.size

        let confidenceBuffer = depthData.confidenceMap
        CVPixelBufferLockBaseAddress(confidenceBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceBuffer, .readOnly) }

        let hasConfidence = CVPixelBufferGetWidth(confidenceBuffer) == depthWidth &&
            CVPixelBufferGetHeight(confidenceBuffer) == depthHeight
        let confidenceStride = CVPixelBufferGetBytesPerRow(confidenceBuffer) / MemoryLayout<UInt8>.size
        let confidenceBase = hasConfidence ? CVPixelBufferGetBaseAddress(confidenceBuffer)?.assumingMemoryBound(to: UInt8.self) : nil
        // Apenas considera pixels classificados com confiança alta pelo hardware.
        let minimumConfidence: UInt8 = 2

        let resolution = frame.camera.imageResolution
        let scaleX = Double(resolution.width) / Double(depthWidth)
        let scaleY = Double(resolution.height) / Double(depthHeight)
        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0 else { return nil }
        let intrinsics = scaledDepthIntrinsics(cameraIntrinsics: frame.camera.intrinsics,
                                               imageResolution: resolution,
                                               depthWidth: depthWidth,
                                               depthHeight: depthHeight)

        // Analisa o mapa completo sem amostragem para aproveitar cada pixel válido fornecido pelo TrueDepth.
        let fullCapacity = max(depthWidth * depthHeight, 1)

        var rawHorizontal: [Double] = []
        rawHorizontal.reserveCapacity(fullCapacity)
        var rawVertical: [Double] = []
        rawVertical.reserveCapacity(fullCapacity)

        var depthSum: Double = 0
        var depthCount: Int = 0

        for y in 0..<depthHeight {
            let rowPointer = depthBase + y * depthStride
            let nextRowPointer: UnsafePointer<Float32>? = (y + 1) < depthHeight ? depthBase + (y + 1) * depthStride : nil
            let confidenceRow = confidenceBase.map { $0 + y * confidenceStride }
            let nextConfidenceRow: UnsafePointer<UInt8>? = {
                guard let base = confidenceBase, (y + 1) < depthHeight else { return nil }
                return base + (y + 1) * confidenceStride
            }()

            for x in 0..<depthWidth {
                let depthValue = rowPointer[x]
                guard depthValue.isFinite, depthValue > 0 else { continue }
                if let confidence = confidenceRow, confidence[x] < minimumConfidence { continue }

                depthSum += Double(depthValue)
                depthCount += 1

                if x + 1 < depthWidth {
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

                if let nextRowPointer {
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
