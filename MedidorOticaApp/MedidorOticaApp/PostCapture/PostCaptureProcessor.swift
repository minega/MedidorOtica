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
                 preferredCentralPoint: NormalizedPoint? = nil) async throws -> PostCaptureAnalysisResult {
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
                                          preferredCentralPoint: preferredCentralPoint)
        return PostCaptureAnalysisResult(configuration: analysis.configuration,
                                         detectedPupils: analysis.detectedPupils,
                                         centralCandidates: analysis.centralCandidates)
    }

    // MARK: - Montagem da Configuração
    private func buildConfiguration(from observation: VNFaceObservation,
                                    imageSize: CGSize,
                                    orientation: CGImagePropertyOrientation,
                                    scale: PostCaptureScale,
                                    preferredCentralPoint: NormalizedPoint?) -> (configuration: PostCaptureConfiguration,
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
        // Localiza o eixo nasal na altura media das pupilas combinando dorso do nariz e linha mediana.
        let nosePoint = resolvedBridgeAxisPoint(landmarks: landmarks,
                                                boundingBox: box,
                                                imageWidth: width,
                                                imageHeight: height,
                                                orientation: orientation,
                                                targetY: averagePupilY)
        let centralX = resolvedCentralX(nosePoint: nosePoint,
                                        preferredCentralPoint: preferredCentralPoint,
                                        rightPupilPoint: rightPupilPoint,
                                        leftPupilPoint: leftPupilPoint,
                                        normalizedBounds: normalizedBounds)
        let centralPoint = NormalizedPoint(x: centralX, y: averagePupilY).clamped()
        let centralCandidates = makeCentralPointCandidates(nosePoint: nosePoint,
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
                                       scale: scale)
        let leftEyeData = initialData(for: resolvedLeftPupil,
                                      isRightEye: false,
                                      centralPoint: centralPoint,
                                      scale: scale,
                                      mirroredFrom: rightEyeData)

        let configuration = PostCaptureConfiguration(centralPoint: centralPoint,
                                                     rightEye: rightEyeData.normalized(centralX: centralPoint.x),
                                                     leftEye: leftEyeData.normalized(centralX: centralPoint.x),
                                                     faceBounds: normalizedBounds)

        let detected = PostCaptureAnalysisResult.DetectedPupils(right: rightPupilPoint != nil,
                                                                left: leftPupilPoint != nil)

        return (configuration, detected, centralCandidates)
    }

    private func makeCentralPointCandidates(nosePoint: CGPoint?,
                                            rightPupilPoint: CGPoint?,
                                            leftPupilPoint: CGPoint?,
                                            normalizedBounds: NormalizedRect,
                                            averagePupilY: CGFloat,
                                            resolvedCentralPoint: NormalizedPoint) -> PostCaptureAnalysisResult.CentralPointCandidates {
        let bridgeX = nosePoint?.x ?? resolvedCentralPoint.x
        let faceMidlineX = normalizedBounds.x + (normalizedBounds.width / 2)
        let pupilMidlineX: CGFloat
        if let rightPupilPoint, let leftPupilPoint {
            pupilMidlineX = (rightPupilPoint.x + leftPupilPoint.x) / 2
        } else {
            pupilMidlineX = resolvedCentralPoint.x
        }

        return PostCaptureAnalysisResult.CentralPointCandidates(
            bridge: NormalizedPoint(x: bridgeX, y: averagePupilY).clamped(),
            faceMidline: NormalizedPoint(x: faceMidlineX, y: averagePupilY).clamped(),
            pupilMidline: NormalizedPoint(x: pupilMidlineX, y: averagePupilY).clamped()
        )
    }

    private func resolvedCentralX(nosePoint: CGPoint?,
                                  preferredCentralPoint: NormalizedPoint?,
                                  rightPupilPoint: CGPoint?,
                                  leftPupilPoint: CGPoint?,
                                  normalizedBounds: NormalizedRect) -> CGFloat {
        let faceMidlineX = normalizedBounds.x + (normalizedBounds.width / 2)
        let candidates = PostCaptureCentralPointResolver.Candidates(
            bridgeX: nosePoint?.x,
            captureX: preferredCentralPoint?.x,
            pupilMidlineX: resolvedPupilMidlineX(rightPupilPoint: rightPupilPoint,
                                                 leftPupilPoint: leftPupilPoint),
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

    private func resolvedBridgeAxisPoint(landmarks: VNFaceLandmarks2D?,
                                         boundingBox: CGRect,
                                         imageWidth: Int,
                                         imageHeight: Int,
                                         orientation: CGImagePropertyOrientation,
                                         targetY: CGFloat) -> CGPoint? {
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

        switch (crestPoint, medianPoint) {
        case let (crest?, median?):
            let blendedX = (crest.x * 0.7) + (median.x * 0.3)
            return CGPoint(x: blendedX, y: targetY)
        case let (crest?, nil):
            return crest
        case let (nil, median?):
            return median
        default:
            return nil
        }
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
        let nasalOffset = scale.normalizedHorizontal(PostCaptureScale.nasalOffsetMM,
                                                     at: centralPoint)
        let temporalOffset = scale.normalizedHorizontal(PostCaptureScale.temporalOffsetMM,
                                                        at: centralPoint)
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

// MARK: - Concurrency
/// O processador e essencialmente sem estado compartilhado mutavel durante a analise.
extension PostCaptureProcessor: @unchecked Sendable {}
