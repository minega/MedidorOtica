//
//  RearLiDARMeasurementEngine.swift
//  MedidorOticaApp
//
//  Motor de medicao traseira que funde landmarks do Vision com profundidade LiDAR.
//

import ARKit
import CoreGraphics
import Foundation
import ImageIO
import Vision
import simd

// MARK: - Limites traseiros
/// Limites de distancia para o fluxo traseiro com LiDAR.
struct RearLiDARDistanceLimits {
    static let minCm: Float = 60.0
    static let maxCm: Float = 100.0
}

// MARK: - Analise traseira
/// Resultado metrico extraido de um frame traseiro.
struct RearLiDARFrameAnalysis {
    let faceObservation: VNFaceObservation
    let cgOrientation: CGImagePropertyOrientation
    let faceBounds: NormalizedRect
    let centralPoint: NormalizedPoint
    let centralCameraPoint: SIMD3<Float>
    let averageEyeDepthMeters: Float
    let projectedFaceWidthRatio: Float
    let projectedFaceHeightRatio: Float
    let headPose: HeadPoseSnapshot?
}

/// Calibracao final gerada para a foto traseira.
struct RearLiDARCaptureCalibration {
    let global: PostCaptureCalibration
    let local: LocalFaceScaleCalibration
    let centralPoint: NormalizedPoint
    let warning: String?
}

// MARK: - Motor LiDAR
/// Resolve escala, PC e pose a partir da camera traseira com LiDAR.
final class RearLiDARMeasurementEngine {
    // MARK: - Constantes
    private enum Constants {
        static let minimumReadableDepthMeters: Float = 0.20
        static let maximumValidDepthMeters: Float = 2.0
        static let localGridColumns = 9
        static let localGridRows = 7
        static let localDepthRadius = 2
        static let minimumLocalSamples = 24
    }

    // MARK: - Cache
    private let cacheQueue = DispatchQueue(label: "com.oticaManzolli.rearLiDAR.cache")
    private var cachedTimestamp: TimeInterval?
    private var cachedOrientation: CGImagePropertyOrientation?
    private var cachedAnalysis: RearLiDARFrameAnalysis?

    // MARK: - Suporte
    /// Informa se o dispositivo expõe profundidade de cena para a camera traseira.
    static var isSupported: Bool {
        guard ARWorldTrackingConfiguration.isSupported else { return false }
        if #available(iOS 14.0, *),
           ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            return true
        }
        if #available(iOS 13.4, *) {
            return ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        }
        return false
    }

    // MARK: - Analise de frame
    /// Detecta apenas a presenca de rosto no RGB traseiro, sem exigir profundidade.
    func detectsFace(frame: ARFrame,
                     cgOrientation: CGImagePropertyOrientation) -> Bool {
        candidateOrientations(preferred: cgOrientation).contains { orientation in
            strongestFaceRectangleObservation(in: frame.capturedImage,
                                               orientation: orientation) != nil
        }
    }

    /// Analisa o frame atual e retorna referencias metricas para verificacoes e captura.
    func analyze(frame: ARFrame,
                 cgOrientation: CGImagePropertyOrientation) -> RearLiDARFrameAnalysis? {
        if let cached = cachedFrameAnalysis(timestamp: frame.timestamp,
                                            orientation: cgOrientation) {
            return cached
        }

        for orientation in candidateOrientations(preferred: cgOrientation) {
            if let analysis = makeAnalysis(frame: frame,
                                           cgOrientation: orientation) {
                storeCachedFrameAnalysis(analysis,
                                         timestamp: frame.timestamp,
                                         orientation: cgOrientation)
                return analysis
            }
        }

        return nil
    }

    private func makeAnalysis(frame: ARFrame,
                              cgOrientation: CGImagePropertyOrientation) -> RearLiDARFrameAnalysis? {
        guard let face = strongestFaceObservation(in: frame.capturedImage,
                                                  orientation: cgOrientation) else {
            return nil
        }

        guard let depthMap = resolvedDepthMap(from: frame) else { return nil }

        let imageSize = orientedSize(for: frame.capturedImage,
                                     orientation: cgOrientation)
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let bounds = VisionGeometryHelper.normalizedRect(from: face.boundingBox,
                                                         imageWidth: Int(imageSize.width),
                                                         imageHeight: Int(imageSize.height),
                                                         orientation: .up)
        guard let centralPoint = resolvedCentralPoint(from: face,
                                                      faceBounds: bounds,
                                                      imageSize: imageSize),
              let eyeDepth = resolvedEyeDepth(from: face,
                                              faceBounds: bounds,
                                              centralPoint: centralPoint,
                                              depthMap: depthMap,
                                              imageSize: imageSize,
                                              orientation: cgOrientation),
              let centralDepth = medianDepth(from: depthMap,
                                             at: centralPoint,
                                             orientation: cgOrientation,
                                             radius: Constants.localDepthRadius),
              let centralCameraPoint = cameraPoint(for: centralPoint,
                                                   depth: centralDepth,
                                                   frame: frame,
                                                   orientation: cgOrientation) else {
            return nil
        }

        let headPose = makeHeadPose(from: face, timestamp: frame.timestamp)
        let analysis = RearLiDARFrameAnalysis(faceObservation: face,
                                              cgOrientation: cgOrientation,
                                              faceBounds: bounds,
                                              centralPoint: centralPoint,
                                              centralCameraPoint: centralCameraPoint,
                                              averageEyeDepthMeters: eyeDepth,
                                              projectedFaceWidthRatio: Float(bounds.width),
                                              projectedFaceHeightRatio: Float(bounds.height),
                                              headPose: headPose)
        return analysis
    }

    /// Gera a calibracao final para a imagem capturada no frame traseiro.
    func captureCalibration(frame: ARFrame,
                            imageSize: CGSize,
                            cgOrientation: CGImagePropertyOrientation) -> RearLiDARCaptureCalibration? {
        guard let depthMap = resolvedDepthMap(from: frame),
              let analysis = analyze(frame: frame, cgOrientation: cgOrientation) else {
            return nil
        }

        let local = makeLocalCalibration(faceBounds: analysis.faceBounds,
                                         frame: frame,
                                         depthMap: depthMap,
                                         imageSize: imageSize,
                                         orientation: analysis.cgOrientation)
        guard local.isReliable,
              let global = local.globalCalibration,
              global.isReliable else {
            return nil
        }

        let warning = "Modo LiDAR traseiro: revise pupilas, PC e DNP longe antes de salvar."
        return RearLiDARCaptureCalibration(global: global,
                                           local: local,
                                           centralPoint: analysis.centralPoint,
                                           warning: warning)
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
                .max { first, second in first.confidence < second.confidence }
            {
                return face
            }
            return strongestFaceRectangleObservation(in: pixelBuffer,
                                                     orientation: orientation)
        } catch {
            print("ERRO Vision LiDAR: \(error)")
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
                .max { first, second in first.confidence < second.confidence }
        } catch {
            print("ERRO Vision retangulo LiDAR: \(error)")
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
            guard abs(deltaY) > .ulpOfOne else { continue }
            let progress = (targetY - first.y) / deltaY
            return first.x + ((second.x - first.x) * progress)
        }

        return ordered.min { abs($0.y - targetY) < abs($1.y - targetY) }?.x
    }

    // MARK: - Profundidade
    private func resolvedDepthMap(from frame: ARFrame) -> CVPixelBuffer? {
        if #available(iOS 14.0, *),
           let smoothed = frame.smoothedSceneDepth?.depthMap {
            return smoothed
        }
        if #available(iOS 13.4, *) {
            return frame.sceneDepth?.depthMap
        }
        return nil
    }

    private func resolvedEyeDepth(from face: VNFaceObservation,
                                  faceBounds: NormalizedRect,
                                  centralPoint: NormalizedPoint,
                                  depthMap: CVPixelBuffer,
                                  imageSize: CGSize,
                                  orientation: CGImagePropertyOrientation) -> Float? {
        let imageWidth = Int(imageSize.width)
        let imageHeight = Int(imageSize.height)
        let points = [
            normalizedPoint(from: face.landmarks?.leftEye,
                            face: face,
                            imageWidth: imageWidth,
                            imageHeight: imageHeight),
            normalizedPoint(from: face.landmarks?.rightEye,
                            face: face,
                            imageWidth: imageWidth,
                            imageHeight: imageHeight)
        ].compactMap { $0 }
        let fallbackPoints = [
            centralPoint,
            NormalizedPoint(x: faceBounds.x + (faceBounds.width * 0.5),
                            y: faceBounds.y + (faceBounds.height * 0.5)).clamped()
        ]

        let samplePoints = points.map { NormalizedPoint(x: $0.x, y: $0.y) } + fallbackPoints
        let depths = samplePoints.compactMap { point in
            medianDepth(from: depthMap,
                        at: point,
                        orientation: orientation,
                        radius: Constants.localDepthRadius)
        }
        guard !depths.isEmpty else { return nil }
        return depths.reduce(0, +) / Float(depths.count)
    }

    private func medianDepth(from depthMap: CVPixelBuffer,
                             at point: NormalizedPoint,
                             orientation: CGImagePropertyOrientation,
                             radius: Int) -> Float? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 0, height > 0 else { return nil }

        let rawPoint = rawDepthPoint(from: point,
                                     orientation: orientation)
        let centerX = Int(rawPoint.x * CGFloat(width - 1))
        let centerY = Int(rawPoint.y * CGFloat(height - 1))
        var values: [Float] = []
        values.reserveCapacity((radius * 2 + 1) * (radius * 2 + 1))

        guard CVPixelBufferLockBaseAddress(depthMap, .readOnly) == kCVReturnSuccess,
              let base = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let dataSize = CVPixelBufferGetDataSize(depthMap)
        for y in max(0, centerY - radius)...min(height - 1, centerY + radius) {
            for x in max(0, centerX - radius)...min(width - 1, centerX + radius) {
                let offset = y * bytesPerRow + x * MemoryLayout<Float>.size
                guard offset + MemoryLayout<Float>.size <= dataSize else { continue }
                let value = base.load(fromByteOffset: offset, as: Float.self)
                guard value.isFinite,
                      value >= Constants.minimumReadableDepthMeters,
                      value <= Constants.maximumValidDepthMeters else {
                    continue
                }
                values.append(value)
            }
        }

        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    // MARK: - Calibracao
    private func makeLocalCalibration(faceBounds: NormalizedRect,
                                      frame: ARFrame,
                                      depthMap: CVPixelBuffer,
                                      imageSize: CGSize,
                                      orientation: CGImagePropertyOrientation) -> LocalFaceScaleCalibration {
        let focal = orientedFocalLengths(from: frame.camera.intrinsics,
                                         orientation: orientation)
        guard focal.fx > 0, focal.fy > 0 else { return .empty }

        var samples: [LocalFaceScaleSample] = []
        samples.reserveCapacity(Constants.localGridColumns * Constants.localGridRows)
        let clampedBounds = faceBounds.clamped()

        for row in 0..<Constants.localGridRows {
            for column in 0..<Constants.localGridColumns {
                let xProgress = CGFloat(column + 1) / CGFloat(Constants.localGridColumns + 1)
                let yProgress = CGFloat(row + 1) / CGFloat(Constants.localGridRows + 1)
                let point = NormalizedPoint(x: clampedBounds.x + clampedBounds.width * xProgress,
                                            y: clampedBounds.y + clampedBounds.height * yProgress).clamped()
                guard let depth = medianDepth(from: depthMap,
                                              at: point,
                                              orientation: orientation,
                                              radius: Constants.localDepthRadius) else {
                    continue
                }

                let horizontalReference = Double(depth) * 1000.0 / focal.fx * Double(imageSize.width)
                let verticalReference = Double(depth) * 1000.0 / focal.fy * Double(imageSize.height)
                guard horizontalReference.isFinite,
                      verticalReference.isFinite,
                      horizontalReference > 0,
                      verticalReference > 0 else {
                    continue
                }

                samples.append(LocalFaceScaleSample(point: point,
                                                    horizontalReferenceMM: horizontalReference,
                                                    verticalReferenceMM: verticalReference,
                                                    depthMM: Double(depth) * 1000.0))
            }
        }

        guard samples.count >= Constants.minimumLocalSamples else { return .empty }
        return LocalFaceScaleCalibration(samples: filtered(samples))
    }

    private func filtered(_ samples: [LocalFaceScaleSample]) -> [LocalFaceScaleSample] {
        guard let centerDepth = robustMean(samples.map(\.depthMM)),
              let centerHorizontal = robustMean(samples.map(\.horizontalReferenceMM)),
              let centerVertical = robustMean(samples.map(\.verticalReferenceMM)) else {
            return samples
        }

        let filteredSamples = samples.filter { sample in
            let depthDelta = abs(sample.depthMM - centerDepth)
            let horizontalRatio = abs(sample.horizontalReferenceMM - centerHorizontal) / max(centerHorizontal, 0.001)
            let verticalRatio = abs(sample.verticalReferenceMM - centerVertical) / max(centerVertical, 0.001)
            return depthDelta <= 80 &&
                horizontalRatio <= 0.18 &&
                verticalRatio <= 0.18
        }
        return filteredSamples.count >= Constants.minimumLocalSamples ? filteredSamples : samples
    }

    // MARK: - Geometria
    private func cameraPoint(for point: NormalizedPoint,
                             depth: Float,
                             frame: ARFrame,
                             orientation: CGImagePropertyOrientation) -> SIMD3<Float>? {
        let rawPoint = rawDepthPoint(from: point,
                                     orientation: orientation)
        let rawImageSize = CGSize(width: CVPixelBufferGetWidth(frame.capturedImage),
                                  height: CVPixelBufferGetHeight(frame.capturedImage))
        let focal = (fx: Double(frame.camera.intrinsics.columns.0.x),
                     fy: Double(frame.camera.intrinsics.columns.1.y))
        let principal = CGPoint(x: CGFloat(frame.camera.intrinsics.columns.2.x),
                                y: CGFloat(frame.camera.intrinsics.columns.2.y))
        guard focal.fx > 0, focal.fy > 0 else { return nil }

        let pixelX = Float(rawPoint.x * rawImageSize.width)
        let pixelY = Float(rawPoint.y * rawImageSize.height)
        let x = (pixelX - Float(principal.x)) / Float(focal.fx) * depth
        let y = (pixelY - Float(principal.y)) / Float(focal.fy) * depth
        return orientedCameraPoint(rawX: x,
                                   rawY: y,
                                   depth: depth,
                                   orientation: orientation)
    }

    private func makeHeadPose(from face: VNFaceObservation,
                              timestamp: TimeInterval) -> HeadPoseSnapshot? {
        guard face.roll != nil || face.yaw != nil || face.pitch != nil else {
            return nil
        }

        let roll = radiansToDegrees(Float(face.roll?.doubleValue ?? 0))
        let yaw = radiansToDegrees(Float(face.yaw?.doubleValue ?? 0))
        let pitch = radiansToDegrees(Float(face.pitch?.doubleValue ?? 0))
        let snapshot = HeadPoseSnapshot(rollDegrees: roll,
                                        yawDegrees: yaw,
                                        pitchDegrees: pitch,
                                        timestamp: timestamp,
                                        sensor: .liDAR)
        return snapshot.isValid ? snapshot : nil
    }

    private func orientedSize(for pixelBuffer: CVPixelBuffer,
                              orientation: CGImagePropertyOrientation) -> CGSize {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        return orientation.isPortrait ?
            CGSize(width: height, height: width) :
            CGSize(width: width, height: height)
    }

    private func orientedFocalLengths(from intrinsics: simd_float3x3,
                                      orientation: CGImagePropertyOrientation) -> (fx: Double, fy: Double) {
        let rawFX = Double(intrinsics.columns.0.x)
        let rawFY = Double(intrinsics.columns.1.y)
        return orientation.isPortrait ? (rawFY, rawFX) : (rawFX, rawFY)
    }

    private func radiansToDegrees(_ radians: Float) -> Float {
        radians * (180.0 / .pi)
    }

    private func rawDepthPoint(from point: NormalizedPoint,
                               orientation: CGImagePropertyOrientation) -> NormalizedPoint {
        let clamped = point.clamped()
        switch orientation {
        case .right:
            return NormalizedPoint(x: clamped.y,
                                   y: 1 - clamped.x).clamped()
        case .left:
            return NormalizedPoint(x: 1 - clamped.y,
                                   y: clamped.x).clamped()
        case .down:
            return NormalizedPoint(x: 1 - clamped.x,
                                   y: 1 - clamped.y).clamped()
        case .rightMirrored:
            return NormalizedPoint(x: 1 - clamped.y,
                                   y: 1 - clamped.x).clamped()
        case .leftMirrored:
            return NormalizedPoint(x: clamped.y,
                                   y: clamped.x).clamped()
        case .upMirrored:
            return NormalizedPoint(x: 1 - clamped.x,
                                   y: clamped.y).clamped()
        case .downMirrored:
            return NormalizedPoint(x: clamped.x,
                                   y: 1 - clamped.y).clamped()
        default:
            return clamped
        }
    }

    private func orientedCameraPoint(rawX: Float,
                                     rawY: Float,
                                     depth: Float,
                                     orientation: CGImagePropertyOrientation) -> SIMD3<Float> {
        switch orientation {
        case .right, .rightMirrored:
            return SIMD3<Float>(-rawY, rawX, depth)
        case .left, .leftMirrored:
            return SIMD3<Float>(rawY, -rawX, depth)
        case .down, .downMirrored:
            return SIMD3<Float>(-rawX, -rawY, depth)
        default:
            return SIMD3<Float>(rawX, rawY, depth)
        }
    }

    private func robustMean(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let trim = Int(Double(sorted.count) * 0.10)
        let usable = Array(sorted.dropFirst(trim).dropLast(trim))
        let finalValues = usable.isEmpty ? sorted : usable
        return finalValues.reduce(0, +) / Double(finalValues.count)
    }

    private func cachedFrameAnalysis(timestamp: TimeInterval,
                                     orientation: CGImagePropertyOrientation) -> RearLiDARFrameAnalysis? {
        cacheQueue.sync {
            guard cachedTimestamp == timestamp,
                  cachedOrientation == orientation else {
                return nil
            }
            return cachedAnalysis
        }
    }

    private func storeCachedFrameAnalysis(_ analysis: RearLiDARFrameAnalysis,
                                          timestamp: TimeInterval,
                                          orientation: CGImagePropertyOrientation) {
        cacheQueue.sync {
            cachedTimestamp = timestamp
            cachedOrientation = orientation
            cachedAnalysis = analysis
        }
    }
}

// MARK: - Concurrency
/// O motor nao mantem estado mutavel entre frames.
extension RearLiDARMeasurementEngine: @unchecked Sendable {}
