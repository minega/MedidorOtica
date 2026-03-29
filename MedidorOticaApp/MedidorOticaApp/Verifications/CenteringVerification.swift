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
        /// Tolerancia de 0,35 cm convertida para metros.
        static let tolerance: Float = 0.0035

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
    func checkFaceCentering(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> Bool {
        let sensors = preferredSensors(requireFaceAnchor: true,
                                       faceAnchorAvailable: faceAnchor != nil)
        guard !sensors.isEmpty else { return false }

        for sensor in sensors {
            switch sensor {
            case .trueDepth:
                guard let anchor = faceAnchor else { continue }
                return checkCenteringWithTrueDepth(faceAnchor: anchor, frame: frame)
            case .liDAR:
                return checkCenteringWithLiDAR(frame: frame)
            case .none:
                continue
            }
        }

        return false
    }

    private func checkCenteringWithTrueDepth(faceAnchor: ARFaceAnchor, frame: ARFrame) -> Bool {
        guard let metrics = makeAlignedTrueDepthMetrics(faceAnchor: faceAnchor, frame: frame) else {
            print("ERRO: nao foi possivel calcular metricas de centralizacao validas")
            return false
        }

        return evaluateCentering(using: metrics)
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
                                    vertical: reference.eyeCenterCameraPosition.y,
                                    noseAlignment: reference.pcCameraPosition.x)
    }

    private func checkCenteringWithLiDAR(frame: ARFrame) -> Bool {
        guard let depthMap = frame.sceneDepth?.depthMap ?? frame.smoothedSceneDepth?.depthMap else {
            print("ERRO: dados de profundidade LiDAR nao disponiveis")
            return false
        }

        let request = makeLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage,
                                            orientation: currentCGOrientation(),
                                            options: [:])

        do {
            try handler.perform([request])
            guard let face = request.results?.first as? VNFaceObservation,
                  let landmarks = face.landmarks else {
                return false
            }

            let orientation = currentCGOrientation()
            let (depthWidth, depthHeight) = orientedDimensions(for: depthMap,
                                                               orientation: orientation)
            let resolution = frame.camera.imageResolution
            let intrinsics = frame.camera.intrinsics

            let nosePoints = resolvedLandmarkPoints(from: landmarks.nose?.normalizedPoints,
                                                    boundingBox: face.boundingBox,
                                                    imageWidth: Int(resolution.width),
                                                    imageHeight: Int(resolution.height),
                                                    orientation: orientation)
                ?? fallbackResolvedPoint(at: CGPoint(x: face.boundingBox.midX,
                                                     y: face.boundingBox.midY),
                                         imageWidth: Int(resolution.width),
                                         imageHeight: Int(resolution.height),
                                         orientation: orientation)

            let leftEyePoints = resolvedLandmarkPoints(from: landmarks.leftEye?.normalizedPoints,
                                                       boundingBox: face.boundingBox,
                                                       imageWidth: Int(resolution.width),
                                                       imageHeight: Int(resolution.height),
                                                       orientation: orientation)
            let rightEyePoints = resolvedLandmarkPoints(from: landmarks.rightEye?.normalizedPoints,
                                                        boundingBox: face.boundingBox,
                                                        imageWidth: Int(resolution.width),
                                                        imageHeight: Int(resolution.height),
                                                        orientation: orientation)

            guard let leftEyePoints, let rightEyePoints else { return false }

            guard let noseDepth = depthValue(from: depthMap,
                                             at: depthPixel(from: nosePoints.depth,
                                                            width: depthWidth,
                                                            height: depthHeight)),
                  let leftEyeDepth = depthValue(from: depthMap,
                                                at: depthPixel(from: leftEyePoints.depth,
                                                               width: depthWidth,
                                                               height: depthHeight)),
                  let rightEyeDepth = depthValue(from: depthMap,
                                                 at: depthPixel(from: rightEyePoints.depth,
                                                                width: depthWidth,
                                                                height: depthHeight)) else {
                return false
            }

            let noseCamera = cameraCoordinates(from: nosePoints.camera,
                                               depth: noseDepth,
                                               resolution: resolution,
                                               intrinsics: intrinsics)
            let leftEyeCamera = cameraCoordinates(from: leftEyePoints.camera,
                                                  depth: leftEyeDepth,
                                                  resolution: resolution,
                                                  intrinsics: intrinsics)
            let rightEyeCamera = cameraCoordinates(from: rightEyePoints.camera,
                                                   depth: rightEyeDepth,
                                                   resolution: resolution,
                                                   intrinsics: intrinsics)

            guard let noseCamera,
                  let leftEyeCamera,
                  let rightEyeCamera else {
                return false
            }

            let metrics = FaceCenteringMetrics(horizontal: noseCamera.x,
                                               vertical: ((leftEyeCamera + rightEyeCamera) / 2).y,
                                               noseAlignment: noseCamera.x)
            return evaluateCentering(using: metrics)
        } catch {
            print("Erro ao verificar centralizacao com Vision: \(error)")
            return false
        }
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
    private func evaluateCentering(using metrics: FaceCenteringMetrics) -> Bool {
        let isHorizontallyAligned = abs(metrics.horizontal) < CenteringConstants.tolerance
        let isVerticallyAligned = abs(metrics.vertical) < CenteringConstants.tolerance
        let isNoseAligned = abs(metrics.noseAlignment) < CenteringConstants.tolerance
        let isCentered = isHorizontallyAligned && isVerticallyAligned && isNoseAligned

        updateCenteringUI(horizontalOffset: metrics.horizontal,
                          verticalOffset: metrics.vertical,
                          noseOffset: metrics.noseAlignment,
                          isCentered: isCentered)
        return isCentered
    }

    // MARK: - UI
    /// Atualiza a interface com os resultados da verificacao de centralizacao.
    private func updateCenteringUI(horizontalOffset: Float,
                                   verticalOffset: Float,
                                   noseOffset: Float,
                                   isCentered: Bool) {
        let horizontalCm = horizontalOffset * 100
        let verticalCm = verticalOffset * 100
        let noseCm = noseOffset * 100

        print("""
        Centralizacao (cm):
           - Horizontal: \(String(format: "%+.2f", horizontalCm)) cm
           - Vertical:   \(String(format: "%+.2f", verticalCm)) cm
           - PC:         \(String(format: "%+.2f", noseCm)) cm
           - Alinhado:   \(isCentered ? "OK" : "ERRO")
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
