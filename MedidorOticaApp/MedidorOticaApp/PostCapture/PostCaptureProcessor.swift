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
    let configuration: PostCaptureConfiguration
}

// MARK: - Processor
/// Processa a imagem estática com Vision para localizar pupilas e o ponto central.
final class PostCaptureProcessor {
    // MARK: - Singleton
    static let shared = PostCaptureProcessor()
    private init() {}

    // MARK: - Processamento
    /// Executa a análise assíncrona retornando as posições normalizadas de interesse.
    /// - Parameter image: Imagem capturada.
    /// - Returns: Estrutura com configuração inicial calculada.
    func analyze(image: UIImage) async throws -> PostCaptureAnalysisResult {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "PostCaptureProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Imagem inválida para análise"])
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let request = VisionGeometryHelper.makeLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        try handler.perform([request])

        guard let observations = request.results as? [VNFaceObservation],
              let observation = observations.max(by: { $0.confidence < $1.confidence }) else {
            throw NSError(domain: "PostCaptureProcessor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Não foi possível localizar o rosto"])
        }

        let dimensions = VisionGeometryHelper.orientedDimensions(for: cgImage, orientation: orientation)
        let imageSize = CGSize(width: dimensions.width, height: dimensions.height)
        let configuration = buildConfiguration(from: observation,
                                               imageSize: imageSize,
                                               orientation: orientation)
        return PostCaptureAnalysisResult(configuration: configuration)
    }

    // MARK: - Montagem da Configuração
    private func buildConfiguration(from observation: VNFaceObservation,
                                    imageSize: CGSize,
                                    orientation: CGImagePropertyOrientation) -> PostCaptureConfiguration {
        let landmarks = observation.landmarks
        let box = observation.boundingBox
        let width = Int(imageSize.width)
        let height = Int(imageSize.height)

        let normalizedBounds = refinedFaceBounds(from: observation,
                                                 imageSize: imageSize,
                                                 orientation: orientation)

        // Localiza pupilas utilizando Vision
        let rightPupilPoint = landmarks?.rightPupil.flatMap {
            VisionGeometryHelper.normalizedPoint(from: $0,
                                                 boundingBox: box,
                                                 imageWidth: width,
                                                 imageHeight: height,
                                                 orientation: orientation)
        }
        let leftPupilPoint = landmarks?.leftPupil.flatMap {
            VisionGeometryHelper.normalizedPoint(from: $0,
                                                 boundingBox: box,
                                                 imageWidth: width,
                                                 imageHeight: height,
                                                 orientation: orientation)
        }

        // Localiza o dorso do nariz (noseCrest) para definir PC.
        let nosePoint = landmarks?.noseCrest.flatMap {
            VisionGeometryHelper.normalizedPoint(from: $0,
                                                 boundingBox: box,
                                                 imageWidth: width,
                                                 imageHeight: height,
                                                 orientation: orientation)
        }

        let pupilsY = [rightPupilPoint?.y ?? 0.5, leftPupilPoint?.y ?? 0.5]
        let averagePupilY = pupilsY.reduce(0, +) / CGFloat(pupilsY.count)
        let centralPoint = NormalizedPoint(x: nosePoint?.x ?? 0.5, y: averagePupilY).clamped()

        // Monta dados por olho utilizando offsets padrão
        let rightEyeData = initialData(for: rightPupilPoint,
                                       isRightEye: true,
                                       centralPoint: centralPoint)
        let leftEyeData = initialData(for: leftPupilPoint,
                                      isRightEye: false,
                                      centralPoint: centralPoint,
                                      mirroredFrom: rightEyeData)

        return PostCaptureConfiguration(centralPoint: centralPoint,
                                        rightEye: rightEyeData.normalized(centralX: centralPoint.x),
                                        leftEye: leftEyeData.normalized(centralX: centralPoint.x),
                                        faceBounds: normalizedBounds)
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
                             mirroredFrom reference: EyeMeasurementData? = nil) -> EyeMeasurementData {
        // Quando o olho esquerdo não possuir detecção, espelha o direito para manter simetria.
        if !isRightEye, point == nil, let mirror = reference {
            return mirror.mirrored(around: centralPoint.x).normalized(centralX: centralPoint.x)
        }

        let defaultX: CGFloat = isRightEye ? 0.35 : 0.65
        let pupilPoint = NormalizedPoint(x: point?.x ?? defaultX,
                                         y: point?.y ?? 0.5).clamped()

        // Conversões de milímetros para valores normalizados
        let nasalOffset = PostCaptureScale.normalizedHorizontal(PostCaptureScale.nasalOffsetMM)
        let temporalOffset = PostCaptureScale.normalizedHorizontal(PostCaptureScale.horizontalGapMM)
        let inferiorOffset = PostCaptureScale.normalizedVertical(PostCaptureScale.inferiorOffsetMM)
        let superiorOffset = PostCaptureScale.normalizedVertical(PostCaptureScale.superiorOffsetMM)

        let nasal: CGFloat
        let temporal: CGFloat

        if isRightEye {
            nasal = (centralPoint.x - nasalOffset)
            temporal = nasal - temporalOffset
        } else {
            nasal = (centralPoint.x + nasalOffset)
            temporal = nasal + temporalOffset
        }

        let inferior = (pupilPoint.y + inferiorOffset)
        let superior = (pupilPoint.y - superiorOffset)

        return EyeMeasurementData(pupil: pupilPoint,
                                  nasalBarX: nasal,
                                  temporalBarX: temporal,
                                  inferiorBarY: inferior,
                                  superiorBarY: superior)
    }
}
