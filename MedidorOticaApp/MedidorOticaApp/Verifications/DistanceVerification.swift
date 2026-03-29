//
//  DistanceVerification.swift
//  MedidorOticaApp
//
//  Verificacao de distancia do rosto ate o plano do PC.
//

import ARKit
import Vision
import simd

/// Limites globais de distancia em centimetros.
struct DistanceLimits {
    static let minCm: Float = 28.0
    static let maxCm: Float = 45.0
}

// MARK: - Distancia
extension VerificationManager {

    // MARK: - Constantes
    private enum DistanceConstants {
        static let minDistanceMeters: Float = DistanceLimits.minCm / 100
        static let maxDistanceMeters: Float = DistanceLimits.maxCm / 100
        static let maxValidDepth: Float = 10.0
        static let minProjectedFaceWidthRatio: Float = 0.22
        static let minProjectedFaceHeightRatio: Float = 0.30
    }

    /// Resultado completo da verificacao de distancia.
    private struct DistanceMeasurement {
        let distance: Float
        let projectedFaceWidthRatio: Float
        let projectedFaceHeightRatio: Float

        var projectedFaceTooSmall: Bool {
            projectedFaceWidthRatio < DistanceConstants.minProjectedFaceWidthRatio ||
            projectedFaceHeightRatio < DistanceConstants.minProjectedFaceHeightRatio
        }

        var hasValidDepth: Bool {
            distance > 0 && distance < DistanceConstants.maxValidDepth
        }
    }

    // MARK: - Verificacao
    /// Verifica se o rosto esta a uma distancia adequada da camera.
    func checkDistance(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> Bool {
        guard let measurement = getDistanceMeasurement(using: frame, faceAnchor: faceAnchor) else {
            handleDistanceVerificationError(reason: "Sensores de profundidade indisponiveis")
            return false
        }

        let isWithinRange = (DistanceConstants.minDistanceMeters...DistanceConstants.maxDistanceMeters)
            .contains(measurement.distance)
        let isWithinProjectedRange = !measurement.projectedFaceTooSmall
        let isValid = measurement.hasValidDepth && isWithinProjectedRange

        updateDistanceUI(distance: measurement.distance,
                         isValid: isWithinRange && isValid,
                         projectedFaceWidthRatio: measurement.projectedFaceWidthRatio,
                         projectedFaceHeightRatio: measurement.projectedFaceHeightRatio,
                         projectedFaceTooSmall: measurement.projectedFaceTooSmall)

        return isWithinRange && isValid
    }

    // MARK: - Medicao
    /// Obtém a medicao usando o sensor apropriado.
    private func getDistanceMeasurement(using frame: ARFrame,
                                        faceAnchor: ARFaceAnchor?) -> DistanceMeasurement? {
        let sensors = preferredSensors(requireFaceAnchor: true,
                                       faceAnchorAvailable: faceAnchor != nil)
        guard !sensors.isEmpty else { return nil }

        for sensor in sensors {
            switch sensor {
            case .trueDepth:
                guard let anchor = faceAnchor else { continue }
                return makeTrueDepthMeasurement(faceAnchor: anchor, frame: frame)
            case .liDAR:
                let distance = getMeasuredDistanceWithLiDAR(frame: frame)
                return DistanceMeasurement(distance: distance,
                                           projectedFaceWidthRatio: 1,
                                           projectedFaceHeightRatio: 1)
            case .none:
                continue
            }
        }

        return nil
    }

    /// Consolida a distancia e o tamanho projetado do rosto para a camera frontal.
    private func makeTrueDepthMeasurement(faceAnchor: ARFaceAnchor,
                                          frame: ARFrame) -> DistanceMeasurement {
        let distance = getMeasuredDistanceWithTrueDepth(faceAnchor: faceAnchor, frame: frame)
        let projectedSize = projectedFaceSizeWithTrueDepth(faceAnchor: faceAnchor, frame: frame)

        return DistanceMeasurement(distance: distance,
                                   projectedFaceWidthRatio: projectedSize?.widthRatio ?? 0,
                                   projectedFaceHeightRatio: projectedSize?.heightRatio ?? 0)
    }

    // MARK: - UI
    /// Atualiza a interface do usuario com o resultado da medicao.
    private func updateDistanceUI(distance: Float,
                                  isValid: Bool,
                                  projectedFaceWidthRatio: Float,
                                  projectedFaceHeightRatio: Float,
                                  projectedFaceTooSmall: Bool) {
        let distanceInCm = distance * 100.0
        print("Distancia medida: \(String(format: "%.1f", distanceInCm)) cm")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.lastMeasuredDistance = Float(distanceInCm)
            self.projectedFaceTooSmall = projectedFaceTooSmall
            self.projectedFaceWidthRatio = projectedFaceWidthRatio
            self.projectedFaceHeightRatio = projectedFaceHeightRatio

            if !isValid {
                let message: String
                if projectedFaceTooSmall {
                    message = "Face ainda pequena no enquadramento"
                } else {
                    message = distance < DistanceConstants.minDistanceMeters ? "Muito perto" : "Muito longe"
                }
                print("Aviso: \(message): \(String(format: "%.1f", distanceInCm)) cm")
            }
        }
    }

    // MARK: - TrueDepth
    /// Mede a distancia do plano do PC ao sensor TrueDepth.
    private func getMeasuredDistanceWithTrueDepth(faceAnchor: ARFaceAnchor,
                                                  frame: ARFrame) -> Float {
        if let reference = trueDepthMeasurementReference(faceAnchor: faceAnchor, frame: frame) {
            let pcDistance = abs(reference.pcCameraPosition.z)
            guard pcDistance > 0, pcDistance < DistanceConstants.maxValidDepth else {
                print("ERRO: distancia TrueDepth do PC fora do intervalo valido: \(pcDistance)m")
                return 0
            }

            print("TrueDepth PC: \(String(format: "%.1f", pcDistance * 100)) cm")
            return pcDistance
        }

        // Fallback curto apenas para nao derrubar a verificacao em um frame ruim.
        let worldToCamera = simd_inverse(frame.camera.transform)
        let leftEyeWorld = simd_mul(faceAnchor.transform, faceAnchor.leftEyeTransform)
        let rightEyeWorld = simd_mul(faceAnchor.transform, faceAnchor.rightEyeTransform)
        let leftEye = simd_mul(worldToCamera, leftEyeWorld)
        let rightEye = simd_mul(worldToCamera, rightEyeWorld)
        let average = (abs(leftEye.columns.3.z) + abs(rightEye.columns.3.z)) / 2

        guard average > 0, average < DistanceConstants.maxValidDepth else {
            print("ERRO: distancia TrueDepth dos olhos fora do intervalo valido: \(average)m")
            return 0
        }

        print("TrueDepth olhos: \(String(format: "%.1f", average * 100)) cm")
        return average
    }

    // MARK: - LiDAR
    /// Mede a distancia usando o sensor LiDAR.
    private func getMeasuredDistanceWithLiDAR(frame: ARFrame) -> Float {
        guard let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth else {
            print("ERRO: dados de profundidade LiDAR nao disponiveis")
            return 0
        }

        let request = makeLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage,
                                            orientation: currentCGOrientation(),
                                            options: [:])
        do {
            try handler.perform([request])
            guard let face = request.results?.first as? VNFaceObservation,
                  let landmarks = face.landmarks,
                  let leftEye = landmarks.leftEye,
                  let rightEye = landmarks.rightEye else {
                print("Aviso: olhos nao detectados com LiDAR")
                return 0
            }

            let width = CVPixelBufferGetWidth(depthData.depthMap)
            let height = CVPixelBufferGetHeight(depthData.depthMap)
            let leftCenter = averagePoint(from: leftEye.normalizedPoints)
            let rightCenter = averagePoint(from: rightEye.normalizedPoints)

            func convert(_ point: CGPoint) -> CGPoint {
                CGPoint(x: point.x * CGFloat(width),
                        y: (1 - point.y) * CGFloat(height))
            }

            var depths: [Float] = []
            if let depth = depthValue(from: depthData.depthMap, at: convert(leftCenter)) {
                depths.append(depth)
            }
            if let depth = depthValue(from: depthData.depthMap, at: convert(rightCenter)) {
                depths.append(depth)
            }

            guard !depths.isEmpty else {
                print("Aviso: nao foi possivel medir a profundidade dos olhos")
                return 0
            }

            let averageDepth = depths.reduce(0, +) / Float(depths.count)
            guard averageDepth > 0, averageDepth < DistanceConstants.maxValidDepth else {
                return 0
            }

            print("LiDAR olhos: \(String(format: "%.1f", averageDepth * 100)) cm")
            return averageDepth
        } catch {
            print("ERRO na medicao de distancia com LiDAR: \(error)")
            return 0
        }
    }

    /// Mede o tamanho projetado do rosto na tela a partir da malha facial do TrueDepth.
    private func projectedFaceSizeWithTrueDepth(faceAnchor: ARFaceAnchor,
                                                frame: ARFrame) -> (widthRatio: Float, heightRatio: Float)? {
        let orientation = currentCGOrientation()
        let viewport = orientedViewportSize(for: frame.camera.imageResolution,
                                            orientation: orientation)
        let uiOrientation = currentUIOrientation()
        let projectedPoints = faceAnchor.geometry.vertices.compactMap { vertex -> CGPoint? in
            let worldPoint = worldPosition(of: vertex, transform: faceAnchor.transform)
            let projected = frame.camera.projectPoint(worldPoint,
                                                     orientation: uiOrientation,
                                                     viewportSize: viewport)
            guard projected.x.isFinite, projected.y.isFinite else { return nil }
            return CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
        }

        guard let minX = projectedPoints.map(\.x).min(),
              let maxX = projectedPoints.map(\.x).max(),
              let minY = projectedPoints.map(\.y).min(),
              let maxY = projectedPoints.map(\.y).max(),
              viewport.width > 0,
              viewport.height > 0 else {
            return nil
        }

        let widthRatio = Float(max(0, maxX - minX) / viewport.width)
        let heightRatio = Float(max(0, maxY - minY) / viewport.height)
        return (widthRatio, heightRatio)
    }

    // MARK: - Erros
    /// Publica erro de verificacao de distancia para a UI.
    private func handleDistanceVerificationError(reason: String) {
        print("ERRO na verificacao de distancia: \(reason)")

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("DistanceVerificationError"),
                                            object: nil,
                                            userInfo: [
                                                "reason": reason,
                                                "timestamp": Date().timeIntervalSince1970
                                            ])
        }
    }
}

// MARK: - Helpers geometricos
private extension VerificationManager {
    /// Converte a resolucao da camera para o viewport efetivo considerando a orientacao atual.
    func orientedViewportSize(for resolution: CGSize,
                              orientation: CGImagePropertyOrientation) -> CGSize {
        orientation.isPortrait ?
            CGSize(width: resolution.height, height: resolution.width) :
            resolution
    }

    /// Converte um vertice da malha em ponto 3D no mundo.
    func worldPosition(of vertex: simd_float3,
                       transform: simd_float4x4) -> simd_float3 {
        let position = simd_mul(transform, SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1))
        return simd_float3(position.x, position.y, position.z)
    }
}
