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
                                        rightEye: rightEyeData.normalizedOrder(),
                                        leftEye: leftEyeData.normalizedOrder())
    }

    private func initialData(for point: CGPoint?,
                             isRightEye: Bool,
                             centralPoint: NormalizedPoint,
                             mirroredFrom reference: EyeMeasurementData? = nil) -> EyeMeasurementData {
        if !isRightEye, let mirror = reference {
            return mirror.mirrored(around: centralPoint.x).normalizedOrder()
        }

        let pupilPoint = NormalizedPoint(x: point?.x ?? (isRightEye ? 0.35 : 0.65),
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
