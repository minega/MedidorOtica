//
//  PostCaptureProcessor.swift
//  MedidorOticaApp
//
//  Responsável por analisar a imagem capturada e sugerir posicionamentos iniciais.
//

import Foundation
import Vision
import UIKit

// MARK: - Resultado da Análise
struct PostCaptureAnalysisResult {
    /// Indica se o Vision localizou cada pupila individualmente.
    struct DetectedPupils {
        let right: Bool
        let left: Bool
    }

    struct CentralPointCandidates {
        let bridge: NormalizedPoint
        let faceMidline: NormalizedPoint
        let pupilMidline: NormalizedPoint
    }

    let configuration: PostCaptureConfiguration
    let detectedPupils: DetectedPupils
    let centralCandidates: CentralPointCandidates
}

// MARK: - Processor
/// Processa a imagem estática com Vision para localizar pupilas e o ponto central.
final class PostCaptureProcessor {
    // MARK: - Singleton
    static let shared = PostCaptureProcessor()
    private init() {}

    // MARK: - Processamento
    /// Executa a análise assíncrona retornando as posições normalizadas de interesse.
    /// - Parameters:
    ///   - image: Imagem capturada.
    ///   - scale: Escala utilizada para converter milímetros em coordenadas normalizadas.
    /// - Returns: Estrutura com configuração inicial calculada.
    func analyze(image: UIImage,
                 scale: PostCaptureScale,
                 preferredCentralPoint: NormalizedPoint? = nil,
                 isRearLiDARCapture: Bool = false) async throws -> PostCaptureAnalysisResult {
        let orientedImage = image.normalizedOrientation()

        guard let cgImage = orientedImage.cgImage else {
            throw NSError(domain: "PostCaptureProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Imagem inválida para análise"])
        }

        let orientation = CGImagePropertyOrientation.up
        let request = VisionGeometryHelper.makeLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        try handler.perform([request])

        guard let observations = request.results as? [VNFaceObservation],
              let observation = observations.max(by: { $0.confidence < $1.confidence }) else {
            throw NSError(domain: "PostCaptureProcessor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Não foi possível localizar o rosto"])
        }

        let imageSize = orientedImage.size
        let analysis = buildConfiguration(from: observation,
                                          imageSize: imageSize,
                                          orientation: orientation,
                                          scale: scale,
                                          preferredCentralPoint: preferredCentralPoint,
                                          isRearLiDARCapture: isRearLiDARCapture)
        return PostCaptureAnalysisResult(configuration: analysis.configuration,
                                         detectedPupils: analysis.detectedPupils,
                                         centralCandidates: analysis.centralCandidates)
    }

    // MARK: - Montagem da Configuração
    private func buildConfiguration(from observation: VNFaceObservation,
                                    imageSize: CGSize,
                                    orientation: CGImagePropertyOrientation,
                                    scale: PostCaptureScale,
                                    preferredCentralPoint: NormalizedPoint?,
                                    isRearLiDARCapture: Bool) -> (configuration: PostCaptureConfiguration,
                                                                  detectedPupils: PostCaptureAnalysisResult.DetectedPupils,
                                                                  centralCandidates: PostCaptureAnalysisResult.CentralPointCandidates) {
        let landmarks = observation.landmarks
        let box = observation.boundingBox
        let width = Int(imageSize.width)
        let height = Int(imageSize.height)

        let normalizedBounds = refinedFaceBounds(from: observation,
                                                 imageSize: imageSize,
                                                 orientation: orientation)

        // Localiza pupilas utilizando Vision
        let rightPupilPoint = resolvedEyePoint(pupilRegion: landmarks?.rightPupil,
                                               eyeRegion: landmarks?.rightEye,
                                               boundingBox: box,
                                               imageWidth: width,
                                               imageHeight: height,
                                               orientation: orientation)
        let leftPupilPoint = resolvedEyePoint(pupilRegion: landmarks?.leftPupil,
                                              eyeRegion: landmarks?.leftEye,
                                              boundingBox: box,
                                              imageWidth: width,
                                              imageHeight: height,
                                              orientation: orientation)

        let averagePupilY = resolvedCentralY(rightPupilPoint: rightPupilPoint,
                                             leftPupilPoint: leftPupilPoint,
                                             preferredCentralPoint: preferredCentralPoint,
                                             normalizedBounds: normalizedBounds)
        // Resolve a banda optica do PC na altura media das pupilas.
        let axisPoints = resolvedCentralAxisPoints(landmarks: landmarks,
                                                   boundingBox: box,
                                                   imageWidth: width,
                                                   imageHeight: height,
                                                   orientation: orientation,
                                                   targetY: averagePupilY)
        let centralX = resolvedCentralX(axisPoints: axisPoints,
                                        rightPupilPoint: rightPupilPoint,
                                        leftPupilPoint: leftPupilPoint,
                                        normalizedBounds: normalizedBounds)
        let centralPoint = NormalizedPoint(x: centralX, y: averagePupilY).clamped()
        let centralCandidates = makeCentralPointCandidates(axisPoints: axisPoints,
                                                           rightPupilPoint: rightPupilPoint,
                                                           leftPupilPoint: leftPupilPoint,
                                                           normalizedBounds: normalizedBounds,
                                                           averagePupilY: averagePupilY,
                                                           resolvedCentralPoint: centralPoint)
        let resolvedRightPupil = rightPupilPoint ?? leftPupilPoint.map { mirroredPoint($0, around: centralPoint.x) }
        let resolvedLeftPupil = leftPupilPoint ?? rightPupilPoint.map { mirroredPoint($0, around: centralPoint.x) }

        // Monta dados por olho utilizando offsets padrão
        let rightEyeData = initialData(for: resolvedRightPupil,
                                       isRightEye: true,
                                       centralPoint: centralPoint,
                                       scale: scale,
                                       isRearLiDARCapture: isRearLiDARCapture)
        let leftEyeData = initialData(for: resolvedLeftPupil,
                                      isRightEye: false,
                                      centralPoint: centralPoint,
                                      scale: scale,
                                      isRearLiDARCapture: isRearLiDARCapture,
                                      mirroredFrom: rightEyeData)

        let configuration = PostCaptureConfiguration(centralPoint: centralPoint,
                                                     rightEye: rightEyeData.normalized(centralX: centralPoint.x),
                                                     leftEye: leftEyeData.normalized(centralX: centralPoint.x),
                                                     faceBounds: normalizedBounds)

        let detected = PostCaptureAnalysisResult.DetectedPupils(right: rightPupilPoint != nil,
                                                                left: leftPupilPoint != nil)

        return (configuration, detected, centralCandidates)
    }

    private func makeCentralPointCandidates(axisPoints: (bridge: CGPoint?, medianLine: CGPoint?),
                                            rightPupilPoint: CGPoint?,
                                            leftPupilPoint: CGPoint?,
                                            normalizedBounds: NormalizedRect,
                                            averagePupilY: CGFloat,
                                            resolvedCentralPoint: NormalizedPoint) -> PostCaptureAnalysisResult.CentralPointCandidates {
        let faceMidlineX = normalizedBounds.x + (normalizedBounds.width / 2)
        let pupilMidlineX: CGFloat
        if let rightPupilPoint, let leftPupilPoint {
            pupilMidlineX = (rightPupilPoint.x + leftPupilPoint.x) / 2
        } else {
            pupilMidlineX = resolvedCentralPoint.x
        }
        let medianLineX = axisPoints.medianLine?.x ?? faceMidlineX
        let bridgeX = resolvedBridgeCandidateX(bridgeX: axisPoints.bridge?.x,
                                               medianLineX: axisPoints.medianLine?.x,
                                               pupilMidlineX: pupilMidlineX,
                                               faceMidlineX: faceMidlineX,
                                               normalizedBounds: normalizedBounds)
        let opticalFaceMidlineX = resolvedOpticalFaceMidlineX(medianLineX: axisPoints.medianLine?.x,
                                                              pupilMidlineX: pupilMidlineX,
                                                              faceMidlineX: faceMidlineX,
                                                              normalizedBounds: normalizedBounds)

        return PostCaptureAnalysisResult.CentralPointCandidates(
            bridge: NormalizedPoint(x: bridgeX, y: averagePupilY).clamped(),
            faceMidline: NormalizedPoint(x: opticalFaceMidlineX, y: averagePupilY).clamped(),
            pupilMidline: NormalizedPoint(x: pupilMidlineX, y: averagePupilY).clamped()
        )
    }

    /// Resolve a ponte nasal com filtros de simetria para nao deixar nariz torto dominar o eixo.
    private func resolvedBridgeCandidateX(bridgeX: CGFloat?,
                                          medianLineX: CGFloat?,
                                          pupilMidlineX: CGFloat,
                                          faceMidlineX: CGFloat,
                                          normalizedBounds: NormalizedRect) -> CGFloat {
        let tolerance = max(normalizedBounds.width * 0.03, 0.01)
        let baseline = ((pupilMidlineX * 2) + faceMidlineX) / 3

        guard let bridgeX else {
            return medianLineX ?? baseline
        }

        let supportLine = medianLineX ?? baseline
        guard abs(bridgeX - supportLine) <= tolerance else {
            return supportLine
        }

        let blended = (bridgeX * 0.35) + (supportLine * 0.65)
        return min(max(blended, normalizedBounds.x), normalizedBounds.x + normalizedBounds.width)
    }

    /// Resolve o meio do rosto usando a linha mediana facial na mesma banda optica das pupilas.
    private func resolvedOpticalFaceMidlineX(medianLineX: CGFloat?,
                                             pupilMidlineX: CGFloat,
                                             faceMidlineX: CGFloat,
                                             normalizedBounds: NormalizedRect) -> CGFloat {
        let baseline = (pupilMidlineX + faceMidlineX) * 0.5
        let resolved = medianLineX.map { ($0 + baseline) * 0.5 } ?? baseline
        return min(max(resolved, normalizedBounds.x), normalizedBounds.x + normalizedBounds.width)
    }

    private func resolvedCentralX(axisPoints: (bridge: CGPoint?, medianLine: CGPoint?),
                                  rightPupilPoint: CGPoint?,
                                  leftPupilPoint: CGPoint?,
                                  normalizedBounds: NormalizedRect) -> CGFloat {
        let faceMidlineX = normalizedBounds.x + (normalizedBounds.width / 2)
        let candidates = PostCaptureCentralPointResolver.Candidates(
            bridgeX: axisPoints.bridge?.x,
            captureX: nil,
            pupilMidlineX: resolvedPupilMidlineX(rightPupilPoint: rightPupilPoint,
                                                 leftPupilPoint: leftPupilPoint),
            medianLineX: axisPoints.medianLine?.x,
            faceMidlineX: faceMidlineX
        )
        return PostCaptureCentralPointResolver.resolveX(using: candidates,
                                                        within: normalizedBounds)
    }

    private func resolvedPupilMidlineX(rightPupilPoint: CGPoint?,
                                       leftPupilPoint: CGPoint?) -> CGFloat? {
        if let rightPupilPoint, let leftPupilPoint {
            return (rightPupilPoint.x + leftPupilPoint.x) / 2
        }
        return nil
    }

    private func resolvedEyePoint(pupilRegion: VNFaceLandmarkRegion2D?,
                                  eyeRegion: VNFaceLandmarkRegion2D?,
                                  boundingBox: CGRect,
                                  imageWidth: Int,
                                  imageHeight: Int,
                                  orientation: CGImagePropertyOrientation) -> CGPoint? {
        if let pupilRegion {
            return VisionGeometryHelper.normalizedPoint(from: pupilRegion,
                                                        boundingBox: boundingBox,
                                                        imageWidth: imageWidth,
                                                        imageHeight: imageHeight,
                                                        orientation: orientation)
        }

        guard let eyeRegion else { return nil }
        return VisionGeometryHelper.normalizedPoint(from: eyeRegion,
                                                    boundingBox: boundingBox,
                                                    imageWidth: imageWidth,
                                                    imageHeight: imageHeight,
                                                    orientation: orientation)
    }

    private func resolvedCentralAxisPoints(landmarks: VNFaceLandmarks2D?,
                                           boundingBox: CGRect,
                                           imageWidth: Int,
                                           imageHeight: Int,
                                           orientation: CGImagePropertyOrientation,
                                           targetY: CGFloat) -> (bridge: CGPoint?, medianLine: CGPoint?) {
        let crestPoints = VisionGeometryHelper.normalizedPoints(from: landmarks?.noseCrest,
                                                                boundingBox: boundingBox,
                                                                imageWidth: imageWidth,
                                                                imageHeight: imageHeight,
                                                                orientation: orientation)
        let medianPoints = VisionGeometryHelper.normalizedPoints(from: landmarks?.medianLine,
                                                                 boundingBox: boundingBox,
                                                                 imageWidth: imageWidth,
                                                                 imageHeight: imageHeight,
                                                                 orientation: orientation)

        let crestPoint = resolvedAxisPoint(from: crestPoints, targetY: targetY)
        let medianPoint = resolvedAxisPoint(from: medianPoints, targetY: targetY)

        return (bridge: crestPoint, medianLine: medianPoint)
    }

    /// Resolve um ponto ao longo de uma linha de landmarks na altura indicada.
    private func resolvedAxisPoint(from points: [CGPoint],
                                   targetY: CGFloat) -> CGPoint? {
        let orderedPoints = points.sorted { $0.y < $1.y }
        guard !orderedPoints.isEmpty else { return nil }

        if let interpolatedPoint = interpolatedAxisPoint(from: orderedPoints, targetY: targetY) {
            return interpolatedPoint
        }

        return orderedPoints.min { abs($0.y - targetY) < abs($1.y - targetY) }
    }

    /// Interpola a linha de referencia exatamente na altura media das pupilas.
    private func interpolatedAxisPoint(from orderedPoints: [CGPoint],
                                       targetY: CGFloat) -> CGPoint? {
        guard orderedPoints.count >= 2 else { return orderedPoints.first }

        for index in 0..<(orderedPoints.count - 1) {
            let first = orderedPoints[index]
            let second = orderedPoints[index + 1]
            let minimumY = min(first.y, second.y)
            let maximumY = max(first.y, second.y)
            guard targetY >= minimumY, targetY <= maximumY else { continue }

            let deltaY = second.y - first.y
            guard abs(deltaY) > .ulpOfOne else { continue }

            let progress = (targetY - first.y) / deltaY
            let interpolatedX = first.x + ((second.x - first.x) * progress)
            return CGPoint(x: interpolatedX, y: targetY)
        }

        return nil
    }

    private func mirroredPoint(_ point: CGPoint,
                               around centralX: CGFloat) -> CGPoint {
        CGPoint(x: (2 * centralX) - point.x,
                y: point.y)
    }

    private func resolvedCentralY(rightPupilPoint: CGPoint?,
                                  leftPupilPoint: CGPoint?,
                                  preferredCentralPoint: NormalizedPoint?,
                                  normalizedBounds: NormalizedRect) -> CGFloat {
        let detectedPupilYs = [rightPupilPoint?.y, leftPupilPoint?.y].compactMap { $0 }
        guard !detectedPupilYs.isEmpty else {
            if let preferredCentralPoint,
               (normalizedBounds.y...(normalizedBounds.y + normalizedBounds.height)).contains(preferredCentralPoint.y) {
                return preferredCentralPoint.y
            }
            return normalizedBounds.y + (normalizedBounds.height * 0.42)
        }

        return detectedPupilYs.reduce(0, +) / CGFloat(detectedPupilYs.count)
    }

    /// Utiliza os landmarks do Vision para recortar toda a cabeça (orelhas, queixo e topo do cabelo).
    private func refinedFaceBounds(from observation: VNFaceObservation,
                                   imageSize: CGSize,
                                   orientation: CGImagePropertyOrientation) -> NormalizedRect {
        let imageWidth = Int(imageSize.width)
        let imageHeight = Int(imageSize.height)
        let baseBounds = VisionGeometryHelper
            .normalizedRect(from: observation.boundingBox,
                            imageWidth: imageWidth,
                            imageHeight: imageHeight,
                            orientation: orientation)

        guard let landmarks = observation.landmarks else {
            return expanded(bounds: baseBounds,
                            lateralPadding: baseBounds.width * 0.1,
                            topPadding: baseBounds.height * 0.25,
                            bottomPadding: baseBounds.height * 0.08)
        }

        // Converte regiões relevantes para o mesmo espaço normalizado, permitindo calcular extremidades reais da cabeça.
        let boundingBox = observation.boundingBox
        let contourPoints = VisionGeometryHelper.normalizedPoints(from: landmarks.faceContour,
                                                                  boundingBox: boundingBox,
                                                                  imageWidth: imageWidth,
                                                                  imageHeight: imageHeight,
                                                                  orientation: orientation)
        let eyebrowPoints = VisionGeometryHelper.normalizedPoints(from: landmarks.leftEyebrow,
                                                                  boundingBox: boundingBox,
                                                                  imageWidth: imageWidth,
                                                                  imageHeight: imageHeight,
                                                                  orientation: orientation) +
            VisionGeometryHelper.normalizedPoints(from: landmarks.rightEyebrow,
                                                  boundingBox: boundingBox,
                                                  imageWidth: imageWidth,
                                                  imageHeight: imageHeight,
                                                  orientation: orientation)
        let medianPoints = VisionGeometryHelper.normalizedPoints(from: landmarks.medianLine,
                                                                 boundingBox: boundingBox,
                                                                 imageWidth: imageWidth,
                                                                 imageHeight: imageHeight,
                                                                 orientation: orientation)

        // Se os contornos não forem detectados, utiliza o retângulo base expandido como fallback seguro.
        guard !contourPoints.isEmpty else {
            return expanded(bounds: baseBounds,
                            lateralPadding: baseBounds.width * 0.12,
                            topPadding: baseBounds.height * 0.3,
                            bottomPadding: baseBounds.height * 0.1)
        }

        // Calcula as extremidades reais no sistema normalizado com origem no topo.
        let contourLeft = contourPoints.map { $0.x }.min() ?? baseBounds.x
        let contourRight = contourPoints.map { $0.x }.max() ?? (baseBounds.x + baseBounds.width)
        let contourTop = contourPoints.map { $0.y }.min() ?? baseBounds.y
        let contourBottom = contourPoints.map { $0.y }.max() ?? (baseBounds.y + baseBounds.height)

        // Determina o topo facial usando sobrancelhas e linha mediana, caso disponíveis.
        let eyebrowTop = eyebrowPoints.map { $0.y }.min() ?? contourTop
        let medianTop = medianPoints.map { $0.y }.min() ?? contourTop
        let faceTop = min(contourTop, eyebrowTop, medianTop)

        let facialHeight = max(contourBottom - faceTop, baseBounds.height)
        let lateralPadding = max((contourRight - contourLeft) * 0.08, 0.015)
        let topPadding = max(facialHeight * 0.35, 0.05)
        let bottomPadding = max(facialHeight * 0.1, 0.02)

        let finalMinX = max(contourLeft - lateralPadding, 0)
        let finalMaxX = min(contourRight + lateralPadding, 1)
        let finalTop = max(faceTop - topPadding, 0)
        let finalBottom = min(contourBottom + bottomPadding, 1)

        let finalWidth = finalMaxX - finalMinX
        let finalHeight = finalBottom - finalTop

        guard finalWidth > 0, finalHeight > 0 else {
            return baseBounds.clamped()
        }

        return NormalizedRect(x: finalMinX,
                              y: finalTop,
                              width: finalWidth,
                              height: finalHeight).clamped()
    }

    /// Expande o retângulo indicado utilizando margens personalizadas.
    private func expanded(bounds: NormalizedRect,
                          lateralPadding: CGFloat,
                          topPadding: CGFloat,
                          bottomPadding: CGFloat) -> NormalizedRect {
        guard bounds.width > 0, bounds.height > 0 else { return NormalizedRect() }

        let minX = max(bounds.x - lateralPadding, 0)
        let maxX = min(bounds.x + bounds.width + lateralPadding, 1)
        let top = max(bounds.y - topPadding, 0)
        let bottom = min(bounds.y + bounds.height + bottomPadding, 1)

        let width = maxX - minX
        let height = bottom - top
        guard width > 0, height > 0 else { return bounds.clamped() }

        return NormalizedRect(x: minX,
                              y: top,
                              width: width,
                              height: height).clamped()
    }

    private func initialData(for point: CGPoint?,
                             isRightEye: Bool,
                             centralPoint: NormalizedPoint,
                             scale: PostCaptureScale,
                             isRearLiDARCapture: Bool,
                             mirroredFrom reference: EyeMeasurementData? = nil) -> EyeMeasurementData {
        // Quando o olho esquerdo não possuir detecção, espelha o direito para manter simetria.
        if !isRightEye, point == nil, let mirror = reference {
            return mirror.mirrored(around: centralPoint.x).normalized(centralX: centralPoint.x)
        }

        let defaultX: CGFloat = isRightEye ? 0.35 : 0.65
        let defaultY = centralPoint.y
        let pupilPoint = NormalizedPoint(x: point?.x ?? defaultX,
                                         y: point?.y ?? defaultY).clamped()

        // Conversões de milímetros para valores normalizados
        let horizontalOffsets = PostCaptureInitialBarPlacement.horizontalOffsets(centralPoint: centralPoint,
                                                                                pupilPoint: pupilPoint,
                                                                                scale: scale,
                                                                                preferDNPAnchoring: isRearLiDARCapture)
        let nasalOffset = horizontalOffsets.nasal
        let temporalOffset = horizontalOffsets.temporal
        let inferiorOffset = scale.normalizedVertical(PostCaptureScale.inferiorOffsetMM,
                                                      at: pupilPoint)
        let superiorOffset = scale.normalizedVertical(PostCaptureScale.superiorOffsetMM,
                                                      at: pupilPoint)

        let isRightSide: Bool
        if let point {
            isRightSide = point.x >= centralPoint.x
        } else {
            isRightSide = isRightEye
        }

        // Ambas as barras partem do PC em direção ao mesmo olho; a nasal fica mais próxima do PC.
        let sideDirection: CGFloat = isRightSide ? 1 : -1
        let nasal = centralPoint.x + (sideDirection * nasalOffset)
        let temporal = centralPoint.x + (sideDirection * temporalOffset)
        let clampedNasal = min(max(nasal, 0), 1)
        let clampedTemporal = min(max(temporal, 0), 1)

        // Ajusta as barras verticais utilizando os deslocamentos fixos solicitados.
        let inferior = min(max(pupilPoint.y + inferiorOffset, 0), 1)
        let superior = min(max(pupilPoint.y - superiorOffset, 0), 1)

        return EyeMeasurementData(pupil: pupilPoint,
                                  nasalBarX: clampedNasal,
                                  temporalBarX: clampedTemporal,
                                  inferiorBarY: inferior,
                                  superiorBarY: superior)
    }
}

// MARK: - Posicionamento inicial das barras
/// Calcula os offsets iniciais das barras sem alterar a medicao final.
enum PostCaptureInitialBarPlacement {
    private enum Constants {
        static let minimumReliableDNP: Double = 10
        static let maximumReliableDNP: Double = 45
        static let minimumPixelDistance: CGFloat = 0.002
    }

    /// Resolve offsets horizontais para posicionar as barras nasal e temporal a partir do PC.
    static func horizontalOffsets(centralPoint: NormalizedPoint,
                                  pupilPoint: NormalizedPoint,
                                  scale: PostCaptureScale,
                                  preferDNPAnchoring: Bool) -> (nasal: CGFloat, temporal: CGFloat) {
        if preferDNPAnchoring,
           let anchored = dnpAnchoredOffsets(centralPoint: centralPoint,
                                             pupilPoint: pupilPoint,
                                             scale: scale) {
            return anchored
        }

        return (scale.normalizedHorizontal(PostCaptureScale.nasalOffsetMM,
                                           at: centralPoint),
                scale.normalizedHorizontal(PostCaptureScale.temporalOffsetMM,
                                           at: centralPoint))
    }

    private static func dnpAnchoredOffsets(centralPoint: NormalizedPoint,
                                           pupilPoint: NormalizedPoint,
                                           scale: PostCaptureScale) -> (nasal: CGFloat, temporal: CGFloat)? {
        let pixelDistance = abs(pupilPoint.x - centralPoint.x)
        guard pixelDistance >= Constants.minimumPixelDistance else { return nil }

        let dnpMillimeters = scale.horizontalMillimeters(between: pupilPoint.x,
                                                         and: centralPoint.x,
                                                         at: (pupilPoint.y + centralPoint.y) * 0.5)
        guard dnpMillimeters.isFinite,
              dnpMillimeters >= Constants.minimumReliableDNP,
              dnpMillimeters <= Constants.maximumReliableDNP else {
            return nil
        }

        let normalizedPerMillimeter = pixelDistance / CGFloat(dnpMillimeters)
        return (sanitized(offset: normalizedPerMillimeter * PostCaptureScale.nasalOffsetMM),
                sanitized(offset: normalizedPerMillimeter * PostCaptureScale.temporalOffsetMM))
    }

    private static func sanitized(offset: CGFloat) -> CGFloat {
        guard offset.isFinite else { return 0 }
        return min(max(offset, 0), 1)
    }
}

// MARK: - Concurrency
/// O processador e essencialmente sem estado compartilhado mutavel durante a analise.
extension PostCaptureProcessor: @unchecked Sendable {}
