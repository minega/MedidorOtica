//
//  DepthUtils.swift
//  MedidorOticaApp
//
//  Utilitarios de profundidade, orientacao e referencia geometrica do PC.
//

import ARKit
import CoreGraphics
import Vision
import UIKit
import simd

/// Referencia geometrica principal do TrueDepth usada para centralizacao e distancia.
struct TrueDepthMeasurementReference {
    let pcCameraPosition: SIMD3<Float>
    let eyeCenterCameraPosition: SIMD3<Float>
    let noseTipCameraPosition: SIMD3<Float>
    let pcNormalizedPoint: NormalizedPoint
}

extension VerificationManager {
    // MARK: - Referencia do PC
    /// Resolve a referencia do PC no espaco 3D da camera e na imagem orientada.
    func trueDepthMeasurementReference(faceAnchor: ARFaceAnchor,
                                       frame: ARFrame,
                                       noseTipIndex: Int = 9) -> TrueDepthMeasurementReference? {
        let vertices = faceAnchor.geometry.vertices
        guard vertices.count > noseTipIndex else { return nil }

        let orientation = currentCGOrientation()
        let uiOrientation = currentUIOrientation()
        let viewportSize = measurementViewportSize(for: frame.camera.imageResolution,
                                                   orientation: orientation)
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let worldToCamera = simd_inverse(frame.camera.transform)
        let faceInCamera = simd_mul(worldToCamera, faceAnchor.transform)
        guard let noseTipCameraPosition = homogeneousCameraPosition(
            simd_mul(faceInCamera, simd_float4(vertices[noseTipIndex], 1))
        ) else {
            return nil
        }

        let leftEyeCameraTransform = simd_mul(faceInCamera, faceAnchor.leftEyeTransform)
        let rightEyeCameraTransform = simd_mul(faceInCamera, faceAnchor.rightEyeTransform)
        let eyeCenterCameraPosition = (cameraTranslation(from: leftEyeCameraTransform) +
                                      cameraTranslation(from: rightEyeCameraTransform)) / 2

        guard let targetPoint = projectedMeasurementTarget(faceAnchor: faceAnchor,
                                                           frame: frame,
                                                           noseTipIndex: noseTipIndex,
                                                           uiOrientation: uiOrientation,
                                                           viewportSize: viewportSize) else {
            return nil
        }

        let bestCandidate = bridgeMeasurementCandidate(vertices: vertices,
                                                       faceAnchor: faceAnchor,
                                                       frame: frame,
                                                       uiOrientation: uiOrientation,
                                                       viewportSize: viewportSize,
                                                       targetPoint: targetPoint,
                                                       worldToCamera: worldToCamera)

        guard let bestCandidate else { return nil }

        return TrueDepthMeasurementReference(
            pcCameraPosition: bestCandidate.camera,
            eyeCenterCameraPosition: eyeCenterCameraPosition,
            noseTipCameraPosition: noseTipCameraPosition,
            pcNormalizedPoint: NormalizedPoint.fromAbsolute(bestCandidate.projected,
                                                            size: viewportSize).clamped()
        )
    }

    // MARK: - Leitura de profundidade
    /// Retorna a profundidade em um ponto especifico do depth map.
    func depthValue(from depthMap: CVPixelBuffer, at point: CGPoint) -> Float? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard point.x >= 0, point.x < CGFloat(width),
              point.y >= 0, point.y < CGFloat(height) else { return nil }

        guard CVPixelBufferLockBaseAddress(depthMap, .readOnly) == kCVReturnSuccess,
              let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let offset = Int(point.y) * bytesPerRow + Int(point.x) * MemoryLayout<Float>.size
        guard offset + MemoryLayout<Float>.size <= CVPixelBufferGetDataSize(depthMap) else { return nil }

        let value = base.load(fromByteOffset: offset, as: Float.self)
        return value.isFinite ? value : nil
    }

    /// Calcula o ponto medio de uma lista de pontos normalizados.
    func averagePoint(from points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }

        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }

        return CGPoint(x: sumX / CGFloat(points.count),
                       y: sumY / CGFloat(points.count))
    }

    /// Retorna a largura e altura considerando a orientacao fornecida.
    func orientedDimensions(for buffer: CVPixelBuffer,
                            orientation: CGImagePropertyOrientation) -> (width: Int, height: Int) {
        VisionGeometryHelper.orientedDimensions(for: buffer, orientation: orientation)
    }

    /// Versao para `CGImage`.
    func orientedDimensions(for image: CGImage,
                            orientation: CGImagePropertyOrientation) -> (Int, Int) {
        let tuple = VisionGeometryHelper.orientedDimensions(for: image, orientation: orientation)
        return (tuple.width, tuple.height)
    }

    /// Converte um ponto de pixel em coordenadas normalizadas de tela.
    func normalizedPoint(_ pixelPoint: CGPoint,
                         width: Int,
                         height: Int,
                         orientation: CGImagePropertyOrientation) -> CGPoint {
        VisionGeometryHelper.normalizedPoint(pixelPoint,
                                             width: width,
                                             height: height,
                                             orientation: orientation)
    }

    /// Garante que o ponto esteja dentro do intervalo normalizado.
    func clampedNormalizedPoint(_ point: CGPoint) -> CGPoint {
        VisionGeometryHelper.clampedNormalizedPoint(point)
    }

    /// Converte uma regiao de landmarks em um ponto medio normalizado.
    func normalizedPoint(from region: VNFaceLandmarkRegion2D,
                         boundingBox: CGRect,
                         imageWidth: Int,
                         imageHeight: Int,
                         orientation: CGImagePropertyOrientation) -> CGPoint? {
        VisionGeometryHelper.normalizedPoint(from: region,
                                             boundingBox: boundingBox,
                                             imageWidth: imageWidth,
                                             imageHeight: imageHeight,
                                             orientation: orientation)
    }

    /// Cria uma `VNDetectFaceLandmarksRequest` com a revisao mais recente.
    /// - Returns: Requisicao configurada para iOS 17 ou superior.
    func makeLandmarksRequest() -> VNDetectFaceLandmarksRequest {
        VisionGeometryHelper.makeLandmarksRequest()
    }

    /// Retorna a orientacao atual considerando a posicao da camera.
    func currentCGOrientation() -> CGImagePropertyOrientation {
        let position = CameraManager.shared.cameraPosition
        let interfaceOrientation = resolvedInterfaceOrientation()

        switch interfaceOrientation {
        case .landscapeLeft:
            return position == .front ? .upMirrored : .down
        case .landscapeRight:
            return position == .front ? .downMirrored : .up
        case .portraitUpsideDown:
            return position == .front ? .rightMirrored : .left
        default:
            return position == .front ? .leftMirrored : .right
        }
    }

    /// Retorna a orientacao de interface atual para projecoes do ARKit.
    func currentUIOrientation() -> UIInterfaceOrientation {
        resolvedInterfaceOrientation()
    }

    /// Ajusta os desvios horizontal e vertical conforme a orientacao do dispositivo.
    /// - Parameters:
    ///   - horizontal: Desvio horizontal em centimetros.
    ///   - vertical: Desvio vertical em centimetros.
    /// - Returns: Desvios adaptados a orientacao atual.
    func adjustOffsets(horizontal: Float, vertical: Float) -> (Float, Float) {
        let portraitMapped = (horizontal: vertical, vertical: -horizontal)

        switch resolvedInterfaceOrientation() {
        case .landscapeLeft:
            return (portraitMapped.vertical, -portraitMapped.horizontal)
        case .landscapeRight:
            return (-portraitMapped.vertical, portraitMapped.horizontal)
        case .portraitUpsideDown:
            return (-portraitMapped.horizontal, -portraitMapped.vertical)
        default:
            return portraitMapped
        }
    }

    /// Resolve a orientacao da interface considerando cena ativa e fallback para o giroscopio.
    private func resolvedInterfaceOrientation() -> UIInterfaceOrientation {
        func sceneOrientation() -> UIInterfaceOrientation? {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
                .first { $0 != .unknown }
        }

        if Thread.isMainThread {
            if let orientation = sceneOrientation() { return orientation }
        } else {
            var orientation: UIInterfaceOrientation?
            DispatchQueue.main.sync {
                orientation = sceneOrientation()
            }
            if let orientation { return orientation }
        }

        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .portrait:
            return .portrait
        default:
            return .portrait
        }
    }

    /// Converte a resolucao da camera para o viewport efetivo da imagem orientada.
    private func measurementViewportSize(for resolution: CGSize,
                                         orientation: CGImagePropertyOrientation) -> CGSize {
        orientation.isPortrait ?
            CGSize(width: resolution.height, height: resolution.width) :
            resolution
    }

    /// Resolve o alvo 2D do PC usando o dorso do nariz no eixo X e a media das pupilas no eixo Y.
    private func projectedMeasurementTarget(faceAnchor: ARFaceAnchor,
                                            frame: ARFrame,
                                            noseTipIndex: Int,
                                            uiOrientation: UIInterfaceOrientation,
                                            viewportSize: CGSize) -> CGPoint? {
        let vertices = faceAnchor.geometry.vertices
        guard vertices.count > noseTipIndex else { return nil }

        let noseWorldPoint = vertexWorldPoint(of: vertices[noseTipIndex],
                                              transform: faceAnchor.transform)
        let leftEyeWorldPoint = transformWorldPosition(from: simd_mul(faceAnchor.transform,
                                                                      faceAnchor.leftEyeTransform))
        let rightEyeWorldPoint = transformWorldPosition(from: simd_mul(faceAnchor.transform,
                                                                       faceAnchor.rightEyeTransform))

        let projectedLeftEye = frame.camera.projectPoint(leftEyeWorldPoint,
                                                         orientation: uiOrientation,
                                                         viewportSize: viewportSize)
        let projectedRightEye = frame.camera.projectPoint(rightEyeWorldPoint,
                                                          orientation: uiOrientation,
                                                          viewportSize: viewportSize)
        let projectedNose = frame.camera.projectPoint(noseWorldPoint,
                                                      orientation: uiOrientation,
                                                      viewportSize: viewportSize)

        guard projectedNose.x.isFinite,
              projectedNose.y.isFinite,
              projectedLeftEye.x.isFinite,
              projectedRightEye.x.isFinite,
              projectedLeftEye.y.isFinite,
              projectedRightEye.y.isFinite else {
            return nil
        }

        let averageEyeX = CGFloat((projectedLeftEye.x + projectedRightEye.x) / 2)
        let noseBlendX = CGFloat(projectedNose.x)
        let targetX = (averageEyeX * 0.7) + (noseBlendX * 0.3)
        return CGPoint(x: targetX,
                       y: CGFloat((projectedLeftEye.y + projectedRightEye.y) / 2))
    }
}

extension CGImagePropertyOrientation {
    /// Converte `UIImage.Orientation` em `CGImagePropertyOrientation`.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }

    /// Indica se a orientacao e vertical.
    var isPortrait: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        default:
            return false
        }
    }

    /// Indica se a orientacao e espelhada horizontalmente.
    var isMirrored: Bool {
        switch self {
        case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored:
            return true
        default:
            return false
        }
    }

    /// Valor EXIF utilizado por CoreImage para aplicar rotacoes e espelhamentos corretamente.
    var exifOrientation: Int32 {
        Int32(rawValue)
    }
}

// MARK: - Helpers geometricos
private extension VerificationManager {
    /// Escolhe um ponto da malha no dorso do nariz, na altura das pupilas.
    func bridgeMeasurementCandidate(vertices: [simd_float3],
                                    faceAnchor: ARFaceAnchor,
                                    frame: ARFrame,
                                    uiOrientation: UIInterfaceOrientation,
                                    viewportSize: CGSize,
                                    targetPoint: CGPoint,
                                    worldToCamera: simd_float4x4) -> (camera: SIMD3<Float>, projected: CGPoint, distance: CGFloat)? {
        let midlineThreshold: Float = 0.0045
        let verticalTolerance = max(viewportSize.height * 0.08, 24)
        let horizontalTolerance = max(viewportSize.width * 0.12, 36)
        var bestCandidate: (camera: SIMD3<Float>, projected: CGPoint, distance: CGFloat)?

        for vertex in vertices {
            guard abs(vertex.x) <= midlineThreshold else { continue }

            let worldPoint = vertexWorldPoint(of: vertex, transform: faceAnchor.transform)
            let projected = frame.camera.projectPoint(worldPoint,
                                                      orientation: uiOrientation,
                                                      viewportSize: viewportSize)
            guard projected.x.isFinite, projected.y.isFinite else { continue }

            let projectedPoint = CGPoint(x: CGFloat(projected.x),
                                         y: CGFloat(projected.y))
            let verticalDistance = abs(projectedPoint.y - targetPoint.y)
            guard verticalDistance <= verticalTolerance else { continue }

            let horizontalDistance = abs(projectedPoint.x - targetPoint.x)
            guard horizontalDistance <= horizontalTolerance else { continue }

            let distance = (verticalDistance * verticalDistance * 5) +
                (horizontalDistance * horizontalDistance * 0.35) +
                (CGFloat(abs(vertex.x)) * 4000)
            let cameraPoint = cameraPointFromWorldPosition(worldPoint,
                                                           worldToCamera: worldToCamera)
            guard cameraPoint.x.isFinite,
                  cameraPoint.y.isFinite,
                  cameraPoint.z.isFinite else {
                continue
            }

            if let current = bestCandidate, current.distance <= distance {
                continue
            }

            bestCandidate = (cameraPoint, projectedPoint, distance)
        }

        if let bestCandidate {
            return bestCandidate
        }

        for vertex in vertices {
            let worldPoint = vertexWorldPoint(of: vertex, transform: faceAnchor.transform)
            let projected = frame.camera.projectPoint(worldPoint,
                                                      orientation: uiOrientation,
                                                      viewportSize: viewportSize)
            guard projected.x.isFinite, projected.y.isFinite else { continue }

            let projectedPoint = CGPoint(x: CGFloat(projected.x),
                                         y: CGFloat(projected.y))
            let distance = squaredPixelDistance(from: projectedPoint,
                                                to: targetPoint)
            let cameraPoint = cameraPointFromWorldPosition(worldPoint,
                                                           worldToCamera: worldToCamera)
            guard cameraPoint.x.isFinite,
                  cameraPoint.y.isFinite,
                  cameraPoint.z.isFinite else {
                continue
            }

            if let current = bestCandidate, current.distance <= distance {
                continue
            }

            bestCandidate = (cameraPoint, projectedPoint, distance)
        }

        return bestCandidate
    }

    /// Converte um vetor homogeneo em coordenadas usuais da camera.
    func homogeneousCameraPosition(_ vector: simd_float4) -> SIMD3<Float>? {
        guard vector.w.isFinite, abs(vector.w) > Float.ulpOfOne else { return nil }
        return SIMD3<Float>(vector.x / vector.w,
                            vector.y / vector.w,
                            vector.z / vector.w)
    }

    /// Extrai a translacao de uma matriz no espaco da camera.
    func cameraTranslation(from transform: simd_float4x4) -> SIMD3<Float> {
        let translation = transform.columns.3
        return SIMD3<Float>(translation.x, translation.y, translation.z)
    }

    /// Converte um vertice da malha para coordenadas do mundo.
    func vertexWorldPoint(of vertex: simd_float3,
                          transform: simd_float4x4) -> simd_float3 {
        let position = simd_mul(transform, SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1))
        return simd_float3(position.x, position.y, position.z)
    }

    /// Extrai a translacao de uma transformacao no mundo.
    func transformWorldPosition(from transform: simd_float4x4) -> simd_float3 {
        simd_float3(transform.columns.3.x,
                    transform.columns.3.y,
                    transform.columns.3.z)
    }

    /// Converte um ponto do mundo para o espaco da camera.
    func cameraPointFromWorldPosition(_ worldPoint: simd_float3,
                                      worldToCamera: simd_float4x4) -> simd_float3 {
        let position = simd_mul(worldToCamera, SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1))
        return simd_float3(position.x, position.y, position.z)
    }

    /// Mede a distancia quadratica entre dois pontos projetados.
    func squaredPixelDistance(from first: CGPoint,
                              to second: CGPoint) -> CGFloat {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return (deltaX * deltaX) + (deltaY * deltaY)
    }
}
