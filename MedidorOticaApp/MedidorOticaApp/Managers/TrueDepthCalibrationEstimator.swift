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
    /// Representa uma amostra de calibração com metadados suficientes para validar seu reaproveitamento.
    private struct CalibrationSample {
        let mmPerPixelX: Double
        let mmPerPixelY: Double
        let timestamp: TimeInterval
        let context: CalibrationContext
    }

    /// Contexto utilizado para invalidar amostras após alterações de sensor ou orientação da sessão.
    private struct CalibrationContext: Equatable {
        let orientedWidth: Int
        let orientedHeight: Int
        let cgOrientationRaw: UInt32
        let uiOrientationRaw: Int
        let focalXSignature: Int
        let focalYSignature: Int
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
    /// Mantém o contexto mais recente persistido para facilitar a remoção de dados obsoletos.
    private var latestContext: CalibrationContext?

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

        let context = Self.makeContext(for: frame,
                                       cgOrientation: cgOrientation,
                                       uiOrientation: uiOrientation)

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
            samples.filter {
                $0.context == context &&
                referenceTime - $0.timestamp <= sampleLifetime
            }
        }

        aggregatedSamples.append(contentsOf: filteredSamples)
        if aggregatedSamples.isEmpty,
           let fallback = mostRecentSample(referenceTime: referenceTime,
                                           context: context) {
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
            if self.latestContext != sample.context {
                self.samples.removeAll()
                self.latestContext = sample.context
            }
            self.samples.append(sample)
            self.pruneSamples(referenceTime: sample.timestamp)
        }
    }

    private func pruneSamples(referenceTime: TimeInterval) {
        samples.removeAll { referenceTime - $0.timestamp > sampleLifetime }
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        if samples.isEmpty {
            latestContext = nil
        }
    }

    /// Retorna a amostra confiável mais recente dentro da janela aceitável.
    private func mostRecentSample(referenceTime: TimeInterval,
                                  context: CalibrationContext) -> CalibrationSample? {
        accessQueue.sync {
            samples.reversed().first {
                $0.context == context &&
                CalibrationBounds.isRecent($0,
                                           referenceTime: referenceTime,
                                           lifetime: sampleLifetime)
            }
        }
    }

    // MARK: - Utilidades estáticas
    private static func makeSample(from frame: ARFrame,
                                   cgOrientation: CGImagePropertyOrientation,
                                   uiOrientation: UIInterfaceOrientation) -> CalibrationSample? {
        let context = makeContext(for: frame,
                                  cgOrientation: cgOrientation,
                                  uiOrientation: uiOrientation)
        guard case .normal = frame.camera.trackingState else { return nil }
        guard let faceAnchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first,
              faceAnchor.isTracked else { return nil }

        let viewportSize = orientedViewportSize(resolution: frame.camera.imageResolution,
                                                orientation: cgOrientation)

        let depthCandidates = depthSamples(faceAnchor: faceAnchor,
                                           cameraTransform: frame.camera.transform)
        guard let depth = stabilizedMean(depthCandidates),
              CalibrationBounds.depthRange.contains(depth) else { return nil }

        var horizontalCandidates: [Double] = []
        var verticalCandidates: [Double] = []

        let focal = orientedFocalLengths(from: frame.camera.intrinsics,
                                         orientation: cgOrientation)
        let depthHorizontal = (depth * 1000) / focal.fx
        let depthVertical = (depth * 1000) / focal.fy

        if CalibrationBounds.isValid(mmPerPixel: depthHorizontal) {
            horizontalCandidates.append(depthHorizontal)
        }

        if CalibrationBounds.isValid(mmPerPixel: depthVertical) {
            verticalCandidates.append(depthVertical)
        }

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
                                 timestamp: frame.timestamp,
                                 context: context)
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

        let context = Self.makeContext(for: frame,
                                       cgOrientation: cgOrientation,
                                       uiOrientation: uiOrientation)

        var referenceSample: CalibrationSample?

        if let current = Self.makeSample(from: frame,
                                         cgOrientation: cgOrientation,
                                         uiOrientation: uiOrientation) {
            referenceSample = current
            store(current)
        } else {
            referenceSample = mostRecentSample(referenceTime: frame.timestamp,
                                               context: context)
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

    /// Gera uma assinatura que descreve o contexto da calibração para evitar reuso indevido de dados antigos.
    private static func makeContext(for frame: ARFrame,
                                    cgOrientation: CGImagePropertyOrientation,
                                    uiOrientation: UIInterfaceOrientation) -> CalibrationContext {
        let orientedSize = orientedViewportSize(resolution: frame.camera.imageResolution,
                                                orientation: cgOrientation)
        let focalLengths = orientedFocalLengths(from: frame.camera.intrinsics,
                                                orientation: cgOrientation)

        return CalibrationContext(orientedWidth: Int(orientedSize.width.rounded()),
                                  orientedHeight: Int(orientedSize.height.rounded()),
                                  cgOrientationRaw: cgOrientation.rawValue,
                                  uiOrientationRaw: uiOrientation.rawValue,
                                  focalXSignature: quantize(focalLengths.fx),
                                  focalYSignature: quantize(focalLengths.fy))
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

    /// Calcula profundidades confiáveis do rosto no espaço da câmera.
    private static func depthSamples(faceAnchor: ARFaceAnchor,
                                     cameraTransform: simd_float4x4) -> [Double] {
        let worldPoints: [simd_float3] = [
            worldPosition(from: faceAnchor.transform),
            worldPosition(from: simd_mul(faceAnchor.transform, faceAnchor.leftEyeTransform)),
            worldPosition(from: simd_mul(faceAnchor.transform, faceAnchor.rightEyeTransform))
        ]

        return worldPoints.compactMap { depthInCameraSpace(of: $0, cameraTransform: cameraTransform) }
    }

    /// Extrai a posição no espaço tridimensional a partir de uma matriz de transformação.
    private static func worldPosition(from transform: simd_float4x4) -> simd_float3 {
        simd_float3(transform.columns.3.x,
                    transform.columns.3.y,
                    transform.columns.3.z)
    }

    /// Retorna a profundidade em metros no espaço da câmera a partir de um ponto no mundo.
    private static func depthInCameraSpace(of worldPoint: simd_float3,
                                           cameraTransform: simd_float4x4) -> Double? {
        let worldToCamera = cameraTransform.inverse
        let homogeneous = simd_float4(worldPoint.x, worldPoint.y, worldPoint.z, 1)
        let cameraSpace = simd_mul(worldToCamera, homogeneous)
        let depth = Double(abs(cameraSpace.z))
        guard depth.isFinite, depth > 0 else { return nil }
        return depth
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

    /// Normaliza valores contínuos para comparação estável entre diferentes amostras.
    private static func quantize(_ value: Double) -> Int {
        Int((value * 1_000).rounded())
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
