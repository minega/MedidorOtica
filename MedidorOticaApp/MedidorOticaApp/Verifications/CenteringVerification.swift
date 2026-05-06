//
//  CenteringVerification.swift
//  MedidorOticaApp
//
//  Verificacao de centralizacao do rosto pelo PC.
//

import Foundation
import ARKit
import Vision
import simd
import CoreGraphics

// MARK: - Notificacoes
extension Notification.Name {
    /// Notificacao enviada quando o status de centralizacao do rosto e atualizado.
    static let faceCenteringUpdated = Notification.Name("faceCenteringUpdated")
}

// MARK: - Centralizacao
extension VerificationManager {

    // MARK: - Constantes
    private enum CenteringConstants {
        /// Tolerancia horizontal final para reduzir erro na DNP sem tornar a captura impraticavel.
        static let horizontalTolerance = CapturePrecisionPolicy.horizontalCenteringTolerance
        /// Tolerancia vertical final para manter a camera na altura do PC.
        static let verticalTolerance = CapturePrecisionPolicy.verticalCenteringTolerance
        /// O eixo X do PC exige a mesma rigidez horizontal.
        static let centralPointTolerance: Float = horizontalTolerance

        struct FaceIndices {
            static let noseTip = 9
        }
    }

    /// Medidas calculadas para orientar o ajuste da camera em relacao ao PC.
    private struct FaceCenteringMetrics {
        let horizontal: Float
        let vertical: Float
        let noseAlignment: Float
    }

    // MARK: - Verificacao
    /// Verifica se o rosto esta corretamente centralizado na camera.
    func checkFaceCentering(using frame: ARFrame,
                            faceAnchor: ARFaceAnchor?,
                            allowAlignmentAssist: Bool = false) -> Bool {
        let sensors = preferredSensors(requireFaceAnchor: true,
                                       faceAnchorAvailable: faceAnchor != nil)
        guard !sensors.isEmpty else { return false }

        for sensor in sensors {
            switch sensor {
            case .trueDepth:
                guard let anchor = faceAnchor else { continue }
                return checkCenteringWithTrueDepth(faceAnchor: anchor,
                                                   frame: frame,
                                                   allowAlignmentAssist: allowAlignmentAssist)
            case .liDAR:
                return checkCenteringWithLiDAR(frame: frame,
                                               allowAlignmentAssist: allowAlignmentAssist)
            case .none:
                continue
            }
        }

        return false
    }

    private func checkCenteringWithTrueDepth(faceAnchor: ARFaceAnchor,
                                             frame: ARFrame,
                                             allowAlignmentAssist: Bool) -> Bool {
        guard let metrics = makeAlignedTrueDepthMetrics(faceAnchor: faceAnchor, frame: frame) else {
            print("ERRO: nao foi possivel calcular metricas de centralizacao validas")
            return false
        }

        return evaluateCentering(using: metrics,
                                 allowAlignmentAssist: allowAlignmentAssist)
    }

    /// Calcula metricas de centralizacao ancoradas no PC real do TrueDepth.
    private func makeAlignedTrueDepthMetrics(faceAnchor: ARFaceAnchor,
                                             frame: ARFrame) -> FaceCenteringMetrics? {
        guard let reference = trueDepthMeasurementReference(faceAnchor: faceAnchor,
                                                            frame: frame,
                                                            noseTipIndex: CenteringConstants.FaceIndices.noseTip) else {
            return nil
        }

        return FaceCenteringMetrics(horizontal: reference.pcCameraPosition.x,
                                    vertical: reference.pcCameraPosition.y,
                                    noseAlignment: reference.pcCameraPosition.x)
    }

    private func checkCenteringWithLiDAR(frame: ARFrame,
                                         allowAlignmentAssist: Bool) -> Bool {
        guard let analysis = CameraManager.shared.rearLiDARMeasurementEngine
            .analyze(frame: frame, cgOrientation: currentCGOrientation()) else {
            print("ERRO: nao foi possivel calcular centralizacao LiDAR")
            return false
        }

        let metrics = FaceCenteringMetrics(horizontal: analysis.centralCameraPoint.x,
                                           vertical: analysis.centralCameraPoint.y,
                                           noseAlignment: analysis.centralCameraPoint.x)
        return evaluateCentering(using: metrics,
                                 allowAlignmentAssist: allowAlignmentAssist)
    }

    /// Calcula pontos medios convertidos para o espaco da camera e para o depth map.
    private func resolvedLandmarkPoints(from points: [CGPoint]?,
                                        boundingBox: CGRect,
                                        imageWidth: Int,
                                        imageHeight: Int,
                                        orientation: CGImagePropertyOrientation) -> (camera: CGPoint, depth: CGPoint)? {
        guard let points, !points.isEmpty else { return nil }

        var accumulator = CGPoint.zero
        for point in points {
            accumulator.x += point.x
            accumulator.y += point.y
        }

        let average = CGPoint(x: accumulator.x / CGFloat(points.count),
                              y: accumulator.y / CGFloat(points.count))
        return fallbackResolvedPoint(at: CGPoint(x: boundingBox.origin.x + average.x * boundingBox.width,
                                                 y: boundingBox.origin.y + average.y * boundingBox.height),
                                     imageWidth: imageWidth,
                                     imageHeight: imageHeight,
                                     orientation: orientation)
    }

    /// Converte um ponto normalizado generico para coordenadas da camera e do depth map.
    private func fallbackResolvedPoint(at normalizedLocation: CGPoint,
                                       imageWidth: Int,
                                       imageHeight: Int,
                                       orientation: CGImagePropertyOrientation) -> (camera: CGPoint, depth: CGPoint) {
        let pixelPoint = VNImagePointForNormalizedPoint(normalizedLocation,
                                                        imageWidth,
                                                        imageHeight)
        let rawCameraNormalized = CGPoint(x: pixelPoint.x / CGFloat(imageWidth),
                                          y: pixelPoint.y / CGFloat(imageHeight))
        let cameraNormalized = clampedNormalizedPoint(rawCameraNormalized)
        let depthNormalized = normalizedPoint(pixelPoint,
                                              width: imageWidth,
                                              height: imageHeight,
                                              orientation: orientation)
        return (camera: cameraNormalized, depth: depthNormalized)
    }

    // MARK: - Avaliacao
    /// Avalia se o rosto esta centralizado com base nas metricas calculadas.
    private func evaluateCentering(using metrics: FaceCenteringMetrics,
                                   allowAlignmentAssist: Bool) -> Bool {
        let horizontalTolerance = activeSensor == .liDAR ? Float(0.0035) : CenteringConstants.horizontalTolerance
        let verticalTolerance = activeSensor == .liDAR ? Float(0.0040) : CenteringConstants.verticalTolerance
        let centralPointTolerance = activeSensor == .liDAR ? Float(0.0035) : CenteringConstants.centralPointTolerance
        let isHorizontallyAligned = abs(metrics.horizontal) < horizontalTolerance
        let isVerticallyAligned = abs(metrics.vertical) < verticalTolerance
        let isNoseAligned = abs(metrics.noseAlignment) < centralPointTolerance
        let isStrictlyCentered = isHorizontallyAligned && isVerticallyAligned && isNoseAligned
        let isAssistedDuringHeadAlignment = activeSensor == .trueDepth &&
            allowAlignmentAssist &&
            abs(metrics.horizontal) < CapturePrecisionPolicy.alignmentAssistHorizontalTolerance &&
            abs(metrics.vertical) < CapturePrecisionPolicy.alignmentAssistVerticalTolerance &&
            abs(metrics.noseAlignment) < CapturePrecisionPolicy.alignmentAssistHorizontalTolerance
        let isCentered = isStrictlyCentered || isAssistedDuringHeadAlignment

        updateCenteringUI(horizontalOffset: metrics.horizontal,
                          verticalOffset: metrics.vertical,
                          noseOffset: metrics.noseAlignment,
                          isCentered: isCentered,
                          isStrictlyCentered: isStrictlyCentered,
                          isAssistedDuringHeadAlignment: isAssistedDuringHeadAlignment)
        return isCentered
    }

    // MARK: - UI
    /// Atualiza a interface com os resultados da verificacao de centralizacao.
    private func updateCenteringUI(horizontalOffset: Float,
                                   verticalOffset: Float,
                                   noseOffset: Float,
                                   isCentered: Bool,
                                   isStrictlyCentered: Bool,
                                   isAssistedDuringHeadAlignment: Bool) {
        let horizontalCm = horizontalOffset * 100
        let verticalCm = verticalOffset * 100
        let noseCm = noseOffset * 100

        print("""
        Centralizacao (cm):
           - Horizontal: \(String(format: "%+.2f", horizontalCm)) cm
           - Vertical:   \(String(format: "%+.2f", verticalCm)) cm
           - PC:         \(String(format: "%+.2f", noseCm)) cm
           - Alinhado:   \(isCentered ? "OK" : "ERRO")
           - Estrito:    \(isStrictlyCentered ? "OK" : "ERRO")
           - Assistido:  \(isAssistedDuringHeadAlignment ? "SIM" : "NAO")
        """)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let wasCentered = self.faceAligned
            self.faceAligned = isCentered
            self.facePosition = [
                "x": horizontalCm,
                "y": verticalCm,
                "z": noseCm
            ]

            if wasCentered != isCentered {
                self.updateVerificationStatus(throttled: true)
            }

            self.notifyCenteringUpdate(isCentered: isCentered)
        }
    }

    /// Notifica a interface sobre a atualizacao do status de centralizacao.
    private func notifyCenteringUpdate(isCentered: Bool) {
        NotificationCenter.default.post(name: .faceCenteringUpdated,
                                        object: nil,
                                        userInfo: [
                                            "isCentered": isCentered,
                                            "offsets": facePosition,
                                            "timestamp": Date().timeIntervalSince1970
                                        ])
    }
}

// MARK: - Conversores auxiliares
private extension VerificationManager {
    /// Converte um ponto normalizado (0...1) e sua profundidade em coordenadas da camera.
    func cameraCoordinates(from normalizedPoint: CGPoint,
                           depth: Float,
                           resolution: CGSize,
                           intrinsics: simd_float3x3) -> SIMD3<Float>? {
        guard depth.isFinite, depth > 0 else { return nil }

        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        let cx = intrinsics.columns.2.x
        let cy = intrinsics.columns.2.y
        guard fx > 0, fy > 0 else { return nil }

        let pixelX = Float(normalizedPoint.x) * Float(resolution.width)
        let pixelY = Float(normalizedPoint.y) * Float(resolution.height)
        let x = (pixelX - cx) / fx * depth
        let y = (pixelY - cy) / fy * depth

        return SIMD3<Float>(x, y, depth)
    }

    /// Converte um ponto normalizado em coordenadas de pixel considerando a orientacao do depth map.
    func depthPixel(from normalizedPoint: CGPoint,
                    width: Int,
                    height: Int) -> CGPoint {
        CGPoint(x: normalizedPoint.x * CGFloat(width),
                y: normalizedPoint.y * CGFloat(height))
    }
}
