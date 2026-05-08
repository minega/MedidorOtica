//
//  RearMonoBridgeMeasurementEngine.swift
//  MedidorOticaApp
//
//  Motor traseiro de camera unica que valida captura por Vision e deixa a escala para a ponte manual.
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Vision
import simd

// MARK: - Limites traseiros Mono
/// Limites visuais para manter o rosto em uma faixa pratica sem profundidade real.
struct RearMonoBridgeDistanceLimits {
    static let minCm: Float = 35.0
    static let maxCm: Float = 55.0
}

// MARK: - Precisao traseira Mono
/// Limites exclusivos do modo traseiro de camera unica.
enum RearMonoBridgeCapturePrecisionPolicy {
    /// Tolerancia horizontal final do PC no preview por proporcao da imagem.
    static let horizontalCenteringTolerance: Float = 0.026
    /// Tolerancia vertical final do PC no preview por proporcao da imagem.
    static let verticalCenteringTolerance: Float = 0.032
    /// Faixa horizontal assistida durante alinhamento.
    static let alignmentAssistHorizontalTolerance: Float = 0.040
    /// Faixa vertical assistida durante alinhamento.
    static let alignmentAssistVerticalTolerance: Float = 0.046
    /// Tolerancia de roll com Vision em camera unica.
    static let rollToleranceDegrees: Float = 3.0
    /// Tolerancia de yaw com Vision em camera unica.
    static let yawToleranceDegrees: Float = 3.2
    /// Tolerancia de pitch com Vision em camera unica.
    static let pitchToleranceDegrees: Float = 3.4
    /// Frames bons exigidos no modo Mono.
    static let stableSampleCount = 4
    /// Maior intervalo entre frames bons.
    static let maximumFrameGap: TimeInterval = 0.20
    /// Idade maxima do frame no disparo.
    static let maximumCaptureAge: TimeInterval = 0.18
}

// MARK: - Frame Mono
/// Frame de video entregue pela camera traseira principal sem profundidade.
struct RearMonoBridgeFrame {
    let pixelBuffer: CVPixelBuffer
    let timestamp: TimeInterval
    let cgOrientation: CGImagePropertyOrientation
}

// MARK: - Analise Mono
/// Resultado visual usado para validar a captura traseira de camera unica.
struct RearMonoBridgeFrameAnalysis {
    let faceObservation: VNFaceObservation
    let cgOrientation: CGImagePropertyOrientation
    let faceBounds: NormalizedRect
    let centralPoint: NormalizedPoint
    let strictOffset: SIMD2<Float>
    let assistedOffset: SIMD2<Float>
    let projectedFaceWidthRatio: Float
    let projectedFaceHeightRatio: Float
    let estimatedDistanceCm: Float
    let headPose: HeadPoseSnapshot?
}

// MARK: - Centralizacao assistida
/// Suaviza a centralizacao visual durante a correcao da pose sem liberar a captura final.
enum RearMonoBridgeCenteringAssist {
    /// Combina o PC estrito com uma referencia facial menos sensivel ao giro.
    static func assistedOffset(strictOffset: SIMD2<Float>,
                               neutralOffset: SIMD2<Float>,
                               headPose: HeadPoseSnapshot?) -> SIMD2<Float> {
        guard let headPose,
              headPose.sensor == .rearMonoBridge,
              headPose.isValid else {
            return strictOffset
        }

        let blend = assistanceBlend(for: headPose)
        return strictOffset + ((neutralOffset - strictOffset) * blend)
    }

    /// Aumenta a previsao conforme a pose se afasta do eixo final.
    static func assistanceBlend(for headPose: HeadPoseSnapshot) -> Float {
        guard headPose.sensor == .rearMonoBridge,
              headPose.isValid else {
            return 0
        }

        let rollError = max(abs(headPose.rollDegrees) - RearMonoBridgeCapturePrecisionPolicy.rollToleranceDegrees, 0)
        let yawError = max(abs(headPose.yawDegrees) - RearMonoBridgeCapturePrecisionPolicy.yawToleranceDegrees, 0)
        let pitchError = max(abs(headPose.pitchDegrees) - RearMonoBridgeCapturePrecisionPolicy.pitchToleranceDegrees, 0)
        let normalizedError = max(rollError / 8,
                                  max(yawError / 10,
                                      pitchError / 10))
        return min(max(normalizedError, 0), 1) * 0.85
    }
}

// MARK: - Motor Mono
/// Resolve rosto, PC visual e pose usando apenas a camera traseira principal.
final class RearMonoBridgeMeasurementEngine {
    // MARK: - Constantes
    private enum Constants {
        static let targetFaceHeightRatio: Float = 0.46
        static let minimumFaceHeightRatio: Float = 0.33
        static let maximumFaceHeightRatio: Float = 0.64
    }

    // MARK: - Cache
    private let cacheQueue = DispatchQueue(label: "com.oticaManzolli.rearMono.cache")
    private var cachedTimestamp: TimeInterval?
    private var cachedAnalysis: RearMonoBridgeFrameAnalysis?

    // MARK: - Suporte
    /// Informa se existe camera traseira principal para o fallback por ponte.
    static var isSupported: Bool {
        mainWideCamera() != nil
    }

    /// Retorna sempre a camera principal traseira, sem ultra-wide e sem virtual dual/triple.
    static func mainWideCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera,
                                for: .video,
                                position: .back)
    }

    // MARK: - Analise
    /// Analisa o frame atual e retorna as referencias visuais do modo Mono.
    func analyze(frame: RearMonoBridgeFrame) -> RearMonoBridgeFrameAnalysis? {
        if let cached = cachedFrameAnalysis(timestamp: frame.timestamp) {
            return cached
        }

        for orientation in candidateOrientations(preferred: frame.cgOrientation) {
            if let analysis = makeAnalysis(frame: frame,
                                           cgOrientation: orientation) {
                storeCachedFrameAnalysis(analysis,
                                         timestamp: frame.timestamp)
                return analysis
            }
        }

        return nil
    }

    private func makeAnalysis(frame: RearMonoBridgeFrame,
                              cgOrientation: CGImagePropertyOrientation) -> RearMonoBridgeFrameAnalysis? {
        guard let face = strongestFaceObservation(in: frame.pixelBuffer,
                                                  orientation: cgOrientation) else {
            return nil
        }

        let imageSize = orientedSize(for: frame.pixelBuffer,
                                     orientation: cgOrientation)
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let bounds = VisionGeometryHelper.normalizedRect(from: face.boundingBox,
                                                         imageWidth: Int(imageSize.width),
                                                         imageHeight: Int(imageSize.height),
                                                         orientation: .up)
        guard let centralPoint = resolvedCentralPoint(from: face,
                                                      faceBounds: bounds,
                                                      imageSize: imageSize) else {
            return nil
        }

        let assistPoint = alignmentAssistCentralPoint(from: face,
                                                      faceBounds: bounds,
                                                      centralPoint: centralPoint,
                                                      imageSize: imageSize)
        let strictOffset = normalizedOffset(from: centralPoint)
        let headPose = makeHeadPose(from: face,
                                    timestamp: frame.timestamp)
        let assistedOffset = RearMonoBridgeCenteringAssist.assistedOffset(strictOffset: strictOffset,
                                                                          neutralOffset: normalizedOffset(from: assistPoint),
                                                                          headPose: headPose)
        return RearMonoBridgeFrameAnalysis(faceObservation: face,
                                           cgOrientation: cgOrientation,
                                           faceBounds: bounds,
                                           centralPoint: centralPoint,
                                           strictOffset: strictOffset,
                                           assistedOffset: assistedOffset,
                                           projectedFaceWidthRatio: Float(bounds.width),
                                           projectedFaceHeightRatio: Float(bounds.height),
                                           estimatedDistanceCm: estimatedDistanceCm(faceHeightRatio: Float(bounds.height)),
                                           headPose: headPose)
    }

    // MARK: - Validacoes visuais
    /// Usa tamanho projetado apenas como guia de enquadramento, sem dizer que e profundidade real.
    func projectedDistanceIsValid(_ analysis: RearMonoBridgeFrameAnalysis) -> Bool {
        analysis.projectedFaceHeightRatio >= Constants.minimumFaceHeightRatio &&
            analysis.projectedFaceHeightRatio <= Constants.maximumFaceHeightRatio
    }

    // MARK: - Vision
    private func strongestFaceObservation(in pixelBuffer: CVPixelBuffer,
                                          orientation: CGImagePropertyOrientation) -> VNFaceObservation? {
        let request = VisionGeometryHelper.makeLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation,
                                            options: [:])
        do {
            try handler.perform([request])
            if let face = (request.results as? [VNFaceObservation])?
                .max(by: { $0.confidence < $1.confidence }) {
                return face
            }
            return strongestFaceRectangleObservation(in: pixelBuffer,
                                                     orientation: orientation)
        } catch {
            print("ERRO Vision Mono traseiro: \(error)")
            return strongestFaceRectangleObservation(in: pixelBuffer,
                                                     orientation: orientation)
        }
    }

    private func strongestFaceRectangleObservation(in pixelBuffer: CVPixelBuffer,
                                                   orientation: CGImagePropertyOrientation) -> VNFaceObservation? {
        let request = VisionGeometryHelper.makeFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation,
                                            options: [:])
        do {
            try handler.perform([request])
            return (request.results as? [VNFaceObservation])?
                .max(by: { $0.confidence < $1.confidence })
        } catch {
            print("ERRO Vision retangulo Mono traseiro: \(error)")
            return nil
        }
    }

    private func candidateOrientations(preferred: CGImagePropertyOrientation) -> [CGImagePropertyOrientation] {
        let orientations: [CGImagePropertyOrientation] = [preferred, .right, .left, .up, .down]
        var unique: [CGImagePropertyOrientation] = []
        for orientation in orientations where !unique.contains(orientation) {
            unique.append(orientation)
        }
        return unique
    }

    // MARK: - PC visual
    private func resolvedCentralPoint(from face: VNFaceObservation,
                                      faceBounds: NormalizedRect,
                                      imageSize: CGSize) -> NormalizedPoint? {
        let imageWidth = Int(imageSize.width)
        let imageHeight = Int(imageSize.height)
        guard imageWidth > 0, imageHeight > 0 else { return nil }

        let rightPupil = normalizedPoint(from: face.landmarks?.rightPupil ?? face.landmarks?.rightEye,
                                         face: face,
                                         imageWidth: imageWidth,
                                         imageHeight: imageHeight)
        let leftPupil = normalizedPoint(from: face.landmarks?.leftPupil ?? face.landmarks?.leftEye,
                                        face: face,
                                        imageWidth: imageWidth,
                                        imageHeight: imageHeight)
        let pupilYs = [rightPupil?.y, leftPupil?.y].compactMap { $0 }
        let fallbackEyeLineY = faceBounds.y + (faceBounds.height * 0.42)
        let targetY = pupilYs.isEmpty ?
            min(max(fallbackEyeLineY, 0), 1) :
            pupilYs.reduce(0, +) / CGFloat(pupilYs.count)

        let medianLine = normalizedPoints(from: face.landmarks?.medianLine,
                                          face: face,
                                          imageWidth: imageWidth,
                                          imageHeight: imageHeight)
        let noseCrest = normalizedPoints(from: face.landmarks?.noseCrest,
                                         face: face,
                                         imageWidth: imageWidth,
                                         imageHeight: imageHeight)
        let axisX = interpolatedAxisX(points: medianLine, targetY: targetY) ??
            interpolatedAxisX(points: noseCrest, targetY: targetY) ??
            (faceBounds.x + (faceBounds.width * 0.5))
        return NormalizedPoint(x: axisX, y: targetY).clamped()
    }

    private func alignmentAssistCentralPoint(from face: VNFaceObservation,
                                             faceBounds: NormalizedRect,
                                             centralPoint: NormalizedPoint,
                                             imageSize: CGSize) -> NormalizedPoint {
        let eyePoints = resolvedEyeLandmarkPoints(face: face,
                                                  imageSize: imageSize)
        let faceCenterX = faceBounds.x + (faceBounds.width * 0.5)
        let faceEyeLineY = faceBounds.y + (faceBounds.height * 0.42)
        var weightedX = centralPoint.x * 0.25
        var totalXWeight: CGFloat = 0.25
        var weightedY = centralPoint.y * 0.55
        var totalYWeight: CGFloat = 0.55

        if eyePoints.count >= 2 {
            let eyeMidX = eyePoints.map(\.x).reduce(0, +) / CGFloat(eyePoints.count)
            weightedX += eyeMidX * 0.50
            totalXWeight += 0.50
        }

        weightedX += faceCenterX * 0.25
        totalXWeight += 0.25
        weightedY += faceEyeLineY * 0.45
        totalYWeight += 0.45

        return NormalizedPoint(x: weightedX / totalXWeight,
                               y: weightedY / totalYWeight).clamped()
    }

    private func normalizedPoint(from region: VNFaceLandmarkRegion2D?,
                                 face: VNFaceObservation,
                                 imageWidth: Int,
                                 imageHeight: Int) -> CGPoint? {
        guard let region else { return nil }
        return VisionGeometryHelper.normalizedPoint(from: region,
                                                    boundingBox: face.boundingBox,
                                                    imageWidth: imageWidth,
                                                    imageHeight: imageHeight,
                                                    orientation: .up)
    }

    private func normalizedPoints(from region: VNFaceLandmarkRegion2D?,
                                  face: VNFaceObservation,
                                  imageWidth: Int,
                                  imageHeight: Int) -> [CGPoint] {
        VisionGeometryHelper.normalizedPoints(from: region,
                                              boundingBox: face.boundingBox,
                                              imageWidth: imageWidth,
                                              imageHeight: imageHeight,
                                              orientation: .up)
    }

    private func interpolatedAxisX(points: [CGPoint],
                                   targetY: CGFloat) -> CGFloat? {
        let ordered = points.sorted { $0.y < $1.y }
        guard ordered.count >= 2 else { return ordered.first?.x }

        for index in 0..<(ordered.count - 1) {
            let first = ordered[index]
            let second = ordered[index + 1]
            guard targetY >= min(first.y, second.y),
                  targetY <= max(first.y, second.y) else {
                continue
            }

            let deltaY = second.y - first.y
            guard abs(deltaY) > 0.0001 else { return first.x }
            let progress = (targetY - first.y) / deltaY
            return first.x + ((second.x - first.x) * progress)
        }

        return ordered.min(by: { abs($0.y - targetY) < abs($1.y - targetY) })?.x
    }

    private func resolvedEyeLandmarkPoints(face: VNFaceObservation,
                                           imageSize: CGSize) -> [NormalizedPoint] {
        let imageWidth = Int(imageSize.width)
        let imageHeight = Int(imageSize.height)
        guard imageWidth > 0, imageHeight > 0 else { return [] }

        return [
            normalizedPoint(from: face.landmarks?.rightPupil ?? face.landmarks?.rightEye,
                            face: face,
                            imageWidth: imageWidth,
                            imageHeight: imageHeight),
            normalizedPoint(from: face.landmarks?.leftPupil ?? face.landmarks?.leftEye,
                            face: face,
                            imageWidth: imageWidth,
                            imageHeight: imageHeight)
        ]
            .compactMap { $0 }
            .map { NormalizedPoint(x: $0.x, y: $0.y).clamped() }
    }

    // MARK: - Pose
    private func makeHeadPose(from face: VNFaceObservation,
                              timestamp: TimeInterval) -> HeadPoseSnapshot? {
        let roll = face.roll.map { radiansToDegrees(Float($0.doubleValue)) }
        let yaw = face.yaw.map { radiansToDegrees(Float($0.doubleValue)) }
        let pitch = face.pitch.map { radiansToDegrees(Float($0.doubleValue)) }
        guard let roll, let yaw, let pitch else { return nil }

        let snapshot = HeadPoseSnapshot(rollDegrees: clampedPoseDegrees(roll),
                                        yawDegrees: clampedPoseDegrees(yaw),
                                        pitchDegrees: clampedPoseDegrees(pitch),
                                        timestamp: timestamp,
                                        sensor: .rearMonoBridge)
        return snapshot.isValid ? snapshot : nil
    }

    private func clampedPoseDegrees(_ value: Float) -> Float {
        min(max(value, -45), 45)
    }

    private func radiansToDegrees(_ radians: Float) -> Float {
        radians * 180 / .pi
    }

    // MARK: - Geometria
    private func normalizedOffset(from point: NormalizedPoint) -> SIMD2<Float> {
        let clamped = point.clamped()
        return SIMD2<Float>(Float(clamped.x - 0.5),
                            Float(clamped.y - 0.5))
    }

    private func estimatedDistanceCm(faceHeightRatio: Float) -> Float {
        guard faceHeightRatio.isFinite, faceHeightRatio > 0 else { return 0 }
        let targetDistance = (RearMonoBridgeDistanceLimits.minCm + RearMonoBridgeDistanceLimits.maxCm) * 0.5
        return targetDistance * Constants.targetFaceHeightRatio / faceHeightRatio
    }

    private func orientedSize(for pixelBuffer: CVPixelBuffer,
                              orientation: CGImagePropertyOrientation) -> CGSize {
        let raw = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                         height: CVPixelBufferGetHeight(pixelBuffer))
        return orientation.isPortrait ?
            CGSize(width: raw.height, height: raw.width) :
            raw
    }

    private func cachedFrameAnalysis(timestamp: TimeInterval) -> RearMonoBridgeFrameAnalysis? {
        cacheQueue.sync {
            guard cachedTimestamp == timestamp else { return nil }
            return cachedAnalysis
        }
    }

    private func storeCachedFrameAnalysis(_ analysis: RearMonoBridgeFrameAnalysis,
                                          timestamp: TimeInterval) {
        cacheQueue.sync {
            cachedTimestamp = timestamp
            cachedAnalysis = analysis
        }
    }
}

// MARK: - Concurrency
/// O motor possui cache serializado por fila dedicada.
extension RearMonoBridgeMeasurementEngine: @unchecked Sendable {}

/// O pixel buffer e transportado entre filas de captura e verificacao sem mutacao pelo app.
extension RearMonoBridgeFrame: @unchecked Sendable {}
