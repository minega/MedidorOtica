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

    /// Estrutura auxiliar que consolida medições de pares da malha facial.
    private struct PairMeasurement {
        let mmDistance: Double
        let pixelDX: Double
        let pixelDY: Double
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
        guard !aggregatedSamples.isEmpty else { return nil }

        let mmPerPixelX = Self.stabilizedMean(aggregatedSamples.map { $0.mmPerPixelX })
        let mmPerPixelY = Self.stabilizedMean(aggregatedSamples.map { $0.mmPerPixelY })

        guard mmPerPixelX.isFinite, mmPerPixelY.isFinite, mmPerPixelX > 0, mmPerPixelY > 0 else { return nil }

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

    // MARK: - Utilidades estáticas
    private static func makeSample(from frame: ARFrame,
                                   cgOrientation: CGImagePropertyOrientation,
                                   uiOrientation: UIInterfaceOrientation) -> CalibrationSample? {
        guard case .normal = frame.camera.trackingState else { return nil }
        guard let faceAnchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first,
              faceAnchor.isTracked else { return nil }

        let viewportSize = orientedViewportSize(resolution: frame.camera.imageResolution,
                                                orientation: cgOrientation)

        var horizontalCandidates: [Double] = []
        var verticalCandidates: [Double] = []

        if let ipdCandidate = interPupillaryCandidate(faceAnchor: faceAnchor,
                                                      camera: frame.camera,
                                                      uiOrientation: uiOrientation,
                                                      viewportSize: viewportSize) {
            horizontalCandidates.append(ipdCandidate)
        }

        let meshCandidates = meshBasedCandidates(faceAnchor: faceAnchor,
                                                 camera: frame.camera,
                                                 uiOrientation: uiOrientation,
                                                 viewportSize: viewportSize)
        horizontalCandidates.append(contentsOf: meshCandidates.horizontal)
        verticalCandidates.append(contentsOf: meshCandidates.vertical)

        guard !horizontalCandidates.isEmpty else { return nil }

        let focal = orientedFocalLengths(from: frame.camera.intrinsics,
                                         orientation: cgOrientation)
        let ratio = focal.fy > 0 ? focal.fx / focal.fy : 1

        let mmPerPixelX = stabilizedMean(horizontalCandidates)
        verticalCandidates.append(mmPerPixelX * ratio)

        let mmPerPixelY = stabilizedMean(verticalCandidates)

        guard mmPerPixelX.isFinite, mmPerPixelY.isFinite, mmPerPixelX > 0, mmPerPixelY > 0 else { return nil }

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

        guard let sample = Self.makeSample(from: frame,
                                           cgOrientation: cgOrientation,
                                           uiOrientation: uiOrientation) else { return nil }

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
        guard distanceMM.isFinite, distanceMM > 40, distanceMM < 80 else { return nil }

        let projectedLeft = camera.projectPoint(leftPosition,
                                                orientation: uiOrientation,
                                                viewportSize: viewportSize)
        let projectedRight = camera.projectPoint(rightPosition,
                                                 orientation: uiOrientation,
                                                 viewportSize: viewportSize)

        let pixelDiffX = Double(abs(projectedRight.x - projectedLeft.x))
        guard pixelDiffX.isFinite, pixelDiffX > 2 else { return nil }

        let mmPerPixelX = distanceMM / pixelDiffX
        guard mmPerPixelX.isFinite, mmPerPixelX > 0.01, mmPerPixelX < 0.2 else { return nil }

        return mmPerPixelX
    }

    /// Calcula múltiplos candidatos de mm/pixel combinando pares opostos da malha facial.
    private static func meshBasedCandidates(faceAnchor: ARFaceAnchor,
                                            camera: ARCamera,
                                            uiOrientation: UIInterfaceOrientation,
                                            viewportSize: CGSize) -> (horizontal: [Double], vertical: [Double]) {
        let vertices = faceAnchor.geometry.vertices
        guard vertices.count >= 2 else { return ([], []) }

        typealias IndexedVertex = (index: Int, vertex: simd_float3)
        let enumerated: [IndexedVertex] = vertices.enumerated().map { ($0.offset, $0.element) }

        let sortedByX = enumerated.sorted { $0.vertex.x < $1.vertex.x }
        let sortedByY = enumerated.sorted { $0.vertex.y < $1.vertex.y }

        let horizontalPairs = candidatePairs(from: sortedByX)
        let verticalPairs = candidatePairs(from: sortedByY)

        var horizontal: [Double] = []
        var vertical: [Double] = []

        for pair in horizontalPairs {
            guard let measurement = measurePair(first: pair.0,
                                                second: pair.1,
                                                faceAnchor: faceAnchor,
                                                camera: camera,
                                                uiOrientation: uiOrientation,
                                                viewportSize: viewportSize) else { continue }

            guard measurement.mmDistance > 60, measurement.mmDistance < 240 else { continue }

            if measurement.pixelDX > 4 {
                let value = measurement.mmDistance / measurement.pixelDX
                if value.isFinite, value > 0.01, value < 0.3 {
                    horizontal.append(value)
                }
            }
        }

        for pair in verticalPairs {
            guard let measurement = measurePair(first: pair.0,
                                                second: pair.1,
                                                faceAnchor: faceAnchor,
                                                camera: camera,
                                                uiOrientation: uiOrientation,
                                                viewportSize: viewportSize) else { continue }

            guard measurement.mmDistance > 60, measurement.mmDistance < 240 else { continue }

            if measurement.pixelDY > 4 {
                let value = measurement.mmDistance / measurement.pixelDY
                if value.isFinite, value > 0.01, value < 0.3 {
                    vertical.append(value)
                }
            }
        }

        return (horizontal, vertical)
    }

    /// Gera pares de vértices opostos após descartar extremos potencialmente ruidosos.
    private static func candidatePairs(from sortedVertices: [(index: Int, vertex: simd_float3)]) -> [(simd_float3, simd_float3)] {
        guard sortedVertices.count >= 2 else { return [] }

        let trimCount = max(1, sortedVertices.count / 20)
        let trimmed = Array(sortedVertices.dropFirst(trimCount).dropLast(trimCount))
        let workingVertices = trimmed.count >= 2 ? trimmed : sortedVertices

        let pairCount = min(6, workingVertices.count / 2)
        guard pairCount > 0 else { return [] }

        var result: [(simd_float3, simd_float3)] = []
        for index in 0..<pairCount {
            let first = workingVertices[index].vertex
            let second = workingVertices[workingVertices.count - 1 - index].vertex
            result.append((first, second))
        }

        return result
    }

    /// Mede a distância em milímetros e pixels entre dois vértices projetados.
    private static func measurePair(first: simd_float3,
                                    second: simd_float3,
                                    faceAnchor: ARFaceAnchor,
                                    camera: ARCamera,
                                    uiOrientation: UIInterfaceOrientation,
                                    viewportSize: CGSize) -> PairMeasurement? {
        // Converte os vértices para coordenadas reais considerando a escala do rosto detectado.
        let worldFirst = worldPosition(of: first, transform: faceAnchor.transform)
        let worldSecond = worldPosition(of: second, transform: faceAnchor.transform)

        let distanceMeters = euclideanDistance(worldFirst, worldSecond)
        guard distanceMeters.isFinite, distanceMeters > 0 else { return nil }

        let projectedFirst = camera.projectPoint(worldFirst,
                                                 orientation: uiOrientation,
                                                 viewportSize: viewportSize)
        let projectedSecond = camera.projectPoint(worldSecond,
                                                  orientation: uiOrientation,
                                                  viewportSize: viewportSize)

        let pixelDX = Double(abs(projectedSecond.x - projectedFirst.x))
        let pixelDY = Double(abs(projectedSecond.y - projectedFirst.y))

        guard pixelDX.isFinite, pixelDY.isFinite else { return nil }

        return PairMeasurement(mmDistance: distanceMeters * 1000,
                               pixelDX: pixelDX,
                               pixelDY: pixelDY)
    }

    /// Converte um vértice da malha facial para coordenadas de mundo.
    private static func worldPosition(of vertex: simd_float3,
                                      transform: simd_float4x4) -> simd_float3 {
        let position = simd_mul(transform, SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1))
        return simd_float3(position.x, position.y, position.z)
    }

    /// Extrai a posição no espaço tridimensional a partir de uma matriz de transformação.
    private static func worldPosition(from transform: simd_float4x4) -> simd_float3 {
        simd_float3(transform.columns.3.x,
                    transform.columns.3.y,
                    transform.columns.3.z)
    }

    /// Calcula a distância euclidiana entre dois vértices em metros.
    private static func euclideanDistance(_ a: simd_float3, _ b: simd_float3) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        let dz = Double(a.z - b.z)
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private static func orientedFocalLengths(from intrinsics: simd_float3x3,
                                             orientation: CGImagePropertyOrientation) -> (fx: Double, fy: Double) {
        let rawFx = Double(intrinsics.columns.0.x)
        let rawFy = Double(intrinsics.columns.1.y)
        if orientation.rotatesDimensions {
            return (fx: rawFy, fy: rawFx)
        }
        return (fx: rawFx, fy: rawFy)
    }

    private static func stabilizedMean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let trimCount = Int(Double(sorted.count) * 0.1)
        let trimmed = sorted.dropFirst(trimCount).dropLast(trimCount)
        let target = trimmed.isEmpty ? sorted : Array(trimmed)
        let sum = target.reduce(0, +)
        return sum / Double(target.count)
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
