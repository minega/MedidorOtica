//
//  PupilTrackingVerification.swift
//  MedidorOticaApp
//
//  Verificação dedicada ao rastreamento das pupilas para sobreposição visual.
//

import ARKit
import Vision
import UIKit

extension VerificationManager {

    // MARK: - Rastreamento de Pupilas
    /// Atualiza o estado `pupilCenters` projetando as pupilas conforme o sensor disponível.
    /// - Parameters:
    ///   - frame: Frame atual da sessão AR utilizado para projeção.
    ///   - faceAnchor: Âncora de rosto encontrada pela câmera TrueDepth.
    func updatePupilTracking(using frame: ARFrame, faceAnchor: ARFaceAnchor?) {
        let updated: Bool

        if hasTrueDepth, let anchor = faceAnchor {
            updated = updateTrueDepthPupilCenters(faceAnchor: anchor, frame: frame)
        } else if hasLiDAR {
            updated = updateLiDARPupilCenters(frame: frame)
        } else {
            updated = false
        }

        if !updated {
            DispatchQueue.main.async { [weak self] in self?.pupilCenters = nil }
        }
    }

    // MARK: - TrueDepth
    /// Projeta as coordenadas das pupilas usando a malha de rosto do TrueDepth.
    private func updateTrueDepthPupilCenters(faceAnchor: ARFaceAnchor, frame: ARFrame) -> Bool {
        let viewportSize = frame.camera.imageResolution
        guard viewportSize.width > 0, viewportSize.height > 0 else { return false }

        let leftEyeWorld = worldPosition(for: faceAnchor.leftEyeTransform,
                                         faceTransform: faceAnchor.transform)
        let rightEyeWorld = worldPosition(for: faceAnchor.rightEyeTransform,
                                          faceTransform: faceAnchor.transform)

        let orientation = currentUIOrientation()
        let leftProjected = frame.camera.projectPoint(leftEyeWorld,
                                                      orientation: orientation,
                                                      viewportSize: viewportSize)
        let rightProjected = frame.camera.projectPoint(rightEyeWorld,
                                                       orientation: orientation,
                                                       viewportSize: viewportSize)

        guard leftProjected.x.isFinite, leftProjected.y.isFinite,
              rightProjected.x.isFinite, rightProjected.y.isFinite else { return false }

        let leftNormalized = clampedNormalizedPoint(CGPoint(x: leftProjected.x / viewportSize.width,
                                                            y: leftProjected.y / viewportSize.height))
        let rightNormalized = clampedNormalizedPoint(CGPoint(x: rightProjected.x / viewportSize.width,
                                                             y: rightProjected.y / viewportSize.height))

        DispatchQueue.main.async { [weak self] in
            self?.pupilCenters = (left: leftNormalized, right: rightNormalized)
        }
        return true
    }

    /// Converte uma transformação do olho em coordenadas do mundo AR.
    private func worldPosition(for eyeTransform: simd_float4x4,
                               faceTransform: simd_float4x4) -> simd_float3 {
        let combined = simd_mul(faceTransform, eyeTransform)
        let translation = combined.columns.3
        return simd_float3(translation.x, translation.y, translation.z)
    }

    // MARK: - LiDAR
    /// Atualiza as pupilas usando landmarks faciais extraídos com Vision.
    private func updateLiDARPupilCenters(frame: ARFrame) -> Bool {
        let orientation = currentCGOrientation()
        let request = makeLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage,
                                            orientation: orientation,
                                            options: [:])

        do {
            try handler.perform([request])

            guard let observations = request.results as? [VNFaceObservation],
                  let bestObservation = observations.max(by: { $0.confidence < $1.confidence }) else {
                return false
            }

            let imageSize = orientedDimensions(for: frame.capturedImage, orientation: orientation)
            guard let centers = extractPupilCenters(from: bestObservation,
                                                    imageWidth: imageSize.width,
                                                    imageHeight: imageSize.height,
                                                    orientation: orientation) else {
                return false
            }

            DispatchQueue.main.async { [weak self] in
                self?.pupilCenters = centers
            }
            return true
        } catch {
            print("ERRO ao detectar pupilas com LiDAR: \(error)")
            return false
        }
    }

    /// Extrai as pupilas a partir das landmarks retornadas pelo Vision.
    private func extractPupilCenters(from observation: VNFaceObservation,
                                     imageWidth: Int,
                                     imageHeight: Int,
                                     orientation: CGImagePropertyOrientation) -> (left: CGPoint, right: CGPoint)? {
        guard let landmarks = observation.landmarks,
              let leftRegion = landmarks.leftPupil,
              let rightRegion = landmarks.rightPupil else {
            return nil
        }

        guard let leftPoint = normalizedPoint(from: leftRegion,
                                              boundingBox: observation.boundingBox,
                                              imageWidth: imageWidth,
                                              imageHeight: imageHeight,
                                              orientation: orientation),
              let rightPoint = normalizedPoint(from: rightRegion,
                                               boundingBox: observation.boundingBox,
                                               imageWidth: imageWidth,
                                               imageHeight: imageHeight,
                                               orientation: orientation) else {
            return nil
        }

        return (left: leftPoint, right: rightPoint)
    }
}
