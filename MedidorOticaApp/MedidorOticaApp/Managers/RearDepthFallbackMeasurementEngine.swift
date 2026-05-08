//
//  RearDepthFallbackMeasurementEngine.swift
//  MedidorOticaApp
//
//  Motor traseiro separado que usa AVDepthData de cameras duplas, sem LiDAR.
//

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Vision
import simd

// MARK: - Modo traseiro por profundidade estimada
/// Estado selecionado para a camera traseira.
enum RearDepthMode: Equatable {
    case liDAR
    case estimatedDepth

    /// Nome curto exibido no topo da camera.
    var sensorName: String {
        switch self {
        case .liDAR:
            return "LiDAR"
        case .estimatedDepth:
            return "Depth"
        }
    }

    /// Mensagem curta exibida ao alternar o modo.
    var toggleMessage: String {
        switch self {
        case .liDAR:
            return "LiDAR ativo. A traseira usa profundidade real do sensor LiDAR."
        case .estimatedDepth:
            return "LiDAR desligado. A traseira usa profundidade estimada da camera dupla."
        }
    }
}

// MARK: - Limites traseiros sem LiDAR
/// Limites de distancia para o fluxo traseiro com profundidade estimada.
struct RearDepthDistanceLimits {
    static let minCm: Float = 35.0
    static let maxCm: Float = 55.0
}

// MARK: - Precisao traseira sem LiDAR
/// Limites exclusivos do fluxo traseiro com AVDepthData.
enum RearDepthCapturePrecisionPolicy {
    /// Tolerancia horizontal final do PC para profundidade estimada.
    static let horizontalCenteringTolerance: Float = 0.0090
    /// Tolerancia vertical final do PC para profundidade estimada.
    static let verticalCenteringTolerance: Float = 0.0100
    /// Faixa horizontal assistida durante alinhamento.
    static let alignmentAssistHorizontalTolerance: Float = 0.0170
    /// Faixa vertical assistida durante alinhamento.
    static let alignmentAssistVerticalTolerance: Float = 0.0190
    /// Tolerancia de roll da cabeca.
    static let rollToleranceDegrees: Float = 2.4
    /// Tolerancia de yaw da cabeca.
    static let yawToleranceDegrees: Float = 2.5
    /// Tolerancia de pitch da cabeca.
    static let pitchToleranceDegrees: Float = 2.7
    /// Quantidade de frames bons exigida no modo depth.
    static let stableSampleCount = 4
    /// Maior intervalo aceito entre frames sincronizados.
    static let maximumFrameGap: TimeInterval = 0.20
    /// Idade maxima do frame para captura.
    static let maximumCaptureAge: TimeInterval = 0.18
}

// MARK: - Frame sincronizado
/// Frame sincronizado de video e profundidade entregue pelo fluxo sem LiDAR.
struct RearDepthFrame {
    let pixelBuffer: CVPixelBuffer
    let depthData: AVDepthData
    let timestamp: TimeInterval
    let cgOrientation: CGImagePropertyOrientation
}

// MARK: - Analise de frame
/// Resultado metrico extraido de um frame traseiro sem LiDAR.
struct RearDepthFrameAnalysis {
    let faceObservation: VNFaceObservation
    let cgOrientation: CGImagePropertyOrientation
    let faceBounds: NormalizedRect
    let centralPoint: NormalizedPoint
    let centralCameraPoint: SIMD3<Float>
    let centralDepthMeters: Float
    let previewCenterOffsetMeters: SIMD2<Float>
    let alignmentAssistCenterOffsetMeters: SIMD2<Float>
    let projectedFaceWidthRatio: Float
    let projectedFaceHeightRatio: Float
    let headPose: HeadPoseSnapshot?
}

/// Calibracao final gerada pelo fluxo traseiro sem LiDAR.
struct RearDepthCaptureCalibration {
    let global: PostCaptureCalibration
    let local: LocalFaceScaleCalibration
    let centralPoint: NormalizedPoint
    let cgOrientation: CGImagePropertyOrientation
    let eyeGeometrySnapshot: CaptureEyeGeometrySnapshot?
    let warning: String?
}

private struct RearDepthHeadPoseAngles {
    let roll: Float?
    let yaw: Float?
    let pitch: Float?
}

private struct RearDepthEyeGeometryPoint {
    let normalizedPoint: NormalizedPoint
    let cameraPoint: SIMD3<Float>
}

// MARK: - Formato de camera traseira
/// Par de formatos necessario para ativar video e profundidade estimada juntos.
struct RearDepthDeviceFormatSelection {
    let videoFormat: AVCaptureDevice.Format
    let depthFormat: AVCaptureDevice.Format
}

// MARK: - Centralizacao assistida
/// Suaviza a centralizacao do modo depth durante a correcao da pose.
enum RearDepthCenteringAssist {
    /// Combina o PC estrito com uma referencia visual menos sensivel ao giro.
    static func assistedOffset(strictOffset: SIMD2<Float>,
                               neutralOffset: SIMD2<Float>,
                               headPose: HeadPoseSnapshot?) -> SIMD2<Float> {
        guard let headPose,
              headPose.sensor == .rearDepth,
              headPose.isValid else {
            return strictOffset
        }

        let blend = assistanceBlend(for: headPose)
        return strictOffset + ((neutralOffset - strictOffset) * blend)
    }

    /// Aumenta a previsao conforme a pose se afasta dos eixos finais.
    static func assistanceBlend(for headPose: HeadPoseSnapshot) -> Float {
        guard headPose.sensor == .rearDepth,
              headPose.isValid else {
            return 0
        }

        let rollError = max(abs(headPose.rollDegrees) - RearDepthCapturePrecisionPolicy.rollToleranceDegrees, 0)
        let yawError = max(abs(headPose.yawDegrees) - RearDepthCapturePrecisionPolicy.yawToleranceDegrees, 0)
        let pitchError = max(abs(headPose.pitchDegrees) - RearDepthCapturePrecisionPolicy.pitchToleranceDegrees, 0)
        let normalizedError = max(rollError / 8,
                                  max(yawError / 10,
                                      pitchError / 10))
        return min(max(normalizedError, 0), 1) * 0.65
    }
}

// MARK: - Motor AVDepthData
/// Resolve escala, PC e pose usando depth map traseiro sem LiDAR.
final class RearDepthFallbackMeasurementEngine {
    // MARK: - Constantes
    private enum Constants {
        static let minimumReadableDepthMeters: Float = 0.20
        static let maximumValidDepthMeters: Float = 2.0
        static let localGridColumns = 9
        static let localGridRows = 7
        static let localDepthRadius = 2
        static let minimumLocalSamples = 18
        static let localScaleToleranceRatio = 0.18
        static let localDepthToleranceMM = 70.0
        static let rearGeometryFixationConfidence = 0.50
        static let maximumFallbackPoseDegrees: Float = 30
    }

    // MARK: - Cache
    private let cacheQueue = DispatchQueue(label: "com.oticaManzolli.rearDepth.cache")
    private var cachedTimestamp: TimeInterval?
    private var cachedAnalysis: RearDepthFrameAnalysis?

    // MARK: - Suporte
    /// Informa se existe camera traseira com depth de disparidade/profundidade sem exigir LiDAR.
    static var isSupported: Bool {
        supportedDepthDevice() != nil
    }

    /// Retorna a melhor camera traseira com suporte a depth que nao seja o dispositivo LiDAR.
    static func supportedDepthDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: preferredDepthDeviceTypes,
                                                         mediaType: .video,
                                                         position: .back)
        return discovery.devices.first { device in
            bestFormatSelection(for: device) != nil
        }
    }

    private static var preferredDepthDeviceTypes: [AVCaptureDevice.DeviceType] {
        [
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInTripleCamera,
            .builtInWideAngleCamera
        ]
    }

    /// Escolhe o par video/depth com maior resolucao de profundidade util.
    static func bestFormatSelection(for device: AVCaptureDevice) -> RearDepthDeviceFormatSelection? {
        device.formats
            .compactMap { videoFormat -> RearDepthDeviceFormatSelection? in
                guard let depthFormat = videoFormat.supportedDepthDataFormats
                    .sorted(by: hasHigherDepthResolution)
                    .first else {
                    return nil
                }

                return RearDepthDeviceFormatSelection(videoFormat: videoFormat,
                                                      depthFormat: depthFormat)
            }
            .sorted { first, second in
                hasHigherDepthResolution(first.depthFormat,
                                         second.depthFormat)
            }
            .first
    }

    /// Mantido para chamadas legadas que precisam apenas do formato de profundidade.
    static func bestDepthFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        bestFormatSelection(for: device)?.depthFormat
    }

    private static func hasHigherDepthResolution(_ first: AVCaptureDevice.Format,
                                                 _ second: AVCaptureDevice.Format) -> Bool {
        let firstDimensions = CMVideoFormatDescriptionGetDimensions(first.formatDescription)
        let secondDimensions = CMVideoFormatDescriptionGetDimensions(second.formatDescription)
        return Int(firstDimensions.width) * Int(firstDimensions.height) >
            Int(secondDimensions.width) * Int(secondDimensions.height)
    }

    // MARK: - Analise
    /// Detecta rosto no RGB traseiro sem exigir profundidade valida.
    func detectsFace(frame: RearDepthFrame) -> Bool {
        candidateOrientations(preferred: frame.cgOrientation).contains { orientation in
            strongestFaceRectangleObservation(in: frame.pixelBuffer,
                                               orientation: orientation) != nil
        }
    }

    /// Analisa o frame atual e retorna referencias metricas para verificacoes e captura.
    func analyze(frame: RearDepthFrame) -> RearDepthFrameAnalysis? {
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

    private func makeAnalysis(frame: RearDepthFrame,
                              cgOrientation: CGImagePropertyOrientation) -> RearDepthFrameAnalysis? {
        guard let face = strongestFaceObservation(in: frame.pixelBuffer,
                                                  orientation: cgOrientation) else {
            return nil
        }

        let depthData = frame.depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        guard let calibrationData = depthData.cameraCalibrationData else { return nil }

        let imageSize = orientedSize(for: frame.pixelBuffer,
                                     orientation: cgOrientation)
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let bounds = VisionGeometryHelper.normalizedRect(from: face.boundingBox,
                                                         imageWidth: Int(imageSize.width),
                                                         imageHeight: Int(imageSize.height),
                                                         orientation: .up)
        guard let centralPoint = resolvedCentralPoint(from: face,
                                                      faceBounds: bounds,
                                                      imageSize: imageSize),
              let centralDepth = medianDepth(from: depthData.depthDataMap,
                                             at: centralPoint,
                                             orientation: cgOrientation,
                                             radius: Constants.localDepthRadius),
              let centralCameraPoint = cameraPoint(for: centralPoint,
                                                   depth: centralDepth,
                                                   frame: frame,
                                                   calibrationData: calibrationData,
                                                   orientation: cgOrientation),
              let previewOffset = previewCenterOffsetMeters(for: centralPoint,
                                                            depth: centralDepth,
                                                            imageSize: imageSize,
                                                            frame: frame,
                                                            calibrationData: calibrationData,
                                                            orientation: cgOrientation) else {
            return nil
        }

        let assistPoint = alignmentAssistCentralPoint(from: face,
                                                      faceBounds: bounds,
                                                      centralPoint: centralPoint,
                                                      imageSize: imageSize)
        let assistOffset = previewCenterOffsetMeters(for: assistPoint,
                                                     depth: centralDepth,
                                                     imageSize: imageSize,
                                                     frame: frame,
                                                     calibrationData: calibrationData,
                                                     orientation: cgOrientation) ?? previewOffset
        let headPose = makeHeadPose(from: face,
                                    centralPoint: centralPoint,
                                    centralCameraPoint: centralCameraPoint,
                                    frame: frame,
                                    depthMap: depthData.depthDataMap,
                                    calibrationData: calibrationData,
                                    imageSize: imageSize,
                                    orientation: cgOrientation,
                                    timestamp: frame.timestamp)
        return RearDepthFrameAnalysis(faceObservation: face,
                                      cgOrientation: cgOrientation,
                                      faceBounds: bounds,
                                      centralPoint: centralPoint,
                                      centralCameraPoint: centralCameraPoint,
                                      centralDepthMeters: centralDepth,
                                      previewCenterOffsetMeters: previewOffset,
                                      alignmentAssistCenterOffsetMeters: assistOffset,
                                      projectedFaceWidthRatio: Float(bounds.width),
                                      projectedFaceHeightRatio: Float(bounds.height),
                                      headPose: headPose)
    }

    /// Gera a calibracao final para a imagem capturada no frame depth.
    func captureCalibration(frame: RearDepthFrame,
                            imageSize: CGSize) -> RearDepthCaptureCalibration? {
        let depthData = frame.depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        guard let calibrationData = depthData.cameraCalibrationData,
              let analysis = analyze(frame: frame) else {
            return nil
        }

        let local = makeLocalCalibration(faceBounds: analysis.faceBounds,
                                         depthMap: depthData.depthDataMap,
                                         frame: frame,
                                         calibrationData: calibrationData,
                                         imageSize: imageSize,
                                         orientation: analysis.cgOrientation)
        guard local.isReliable,
              let global = local.globalCalibration,
              global.isReliable,
              isPlausibleRearDepthCaptureScale(global) else {
            return nil
        }

        let eyeGeometrySnapshot = makeEyeGeometrySnapshot(frame: frame,
                                                          analysis: analysis,
                                                          depthMap: depthData.depthDataMap,
                                                          calibrationData: calibrationData,
                                                          imageSize: imageSize)
        let warning = "Modo Depth traseiro: profundidade estimada pela camera dupla. Revise pupilas, PC e ponte antes de salvar."
        return RearDepthCaptureCalibration(global: global,
                                           local: local,
                                           centralPoint: analysis.centralPoint,
                                           cgOrientation: analysis.cgOrientation,
                                           eyeGeometrySnapshot: eyeGeometrySnapshot,
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
                .max(by: { $0.confidence < $1.confidence }) {
                return face
            }
            return strongestFaceRectangleObservation(in: pixelBuffer,
                                                     orientation: orientation)
        } catch {
            print("ERRO Vision Depth traseiro: \(error)")
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
            print("ERRO Vision retangulo Depth traseiro: \(error)")
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

    private func alignmentAssistCentralPoint(from face: VNFaceObservation,
                                             faceBounds: NormalizedRect,
                                             centralPoint: NormalizedPoint,
                                             imageSize: CGSize) -> NormalizedPoint {
        let eyePoints = resolvedEyeLandmarkPoints(face: face,
                                                  imageSize: imageSize)
        let faceCenterX = faceBounds.x + (faceBounds.width * 0.5)
        let faceEyeLineY = faceBounds.y + (faceBounds.height * 0.42)
        var weightedX = centralPoint.x * 0.50
        var totalXWeight: CGFloat = 0.50
        var weightedY = centralPoint.y * 0.75
        var totalYWeight: CGFloat = 0.75

        if eyePoints.count >= 2 {
            let eyeMidX = eyePoints.map(\.x).reduce(0, +) / CGFloat(eyePoints.count)
            weightedX += eyeMidX * 0.35
            totalXWeight += 0.35
        }

        weightedX += faceCenterX * 0.15
        totalXWeight += 0.15
        weightedY += faceEyeLineY * 0.25
        totalYWeight += 0.25

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
            guard abs(deltaY) > .ulpOfOne else { continue }
            let progress = (targetY - first.y) / deltaY
            return first.x + ((second.x - first.x) * progress)
        }

        return ordered.min { abs($0.y - targetY) < abs($1.y - targetY) }?.x
    }

    // MARK: - Profundidade e escala
    private func medianDepth(from depthMap: CVPixelBuffer,
                             at point: NormalizedPoint,
                             orientation: CGImagePropertyOrientation,
                             radius: Int) -> Float? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 0, height > 0 else { return nil }

        let rawPoint = rawDepthPoint(from: point,
                                     orientation: orientation)
        let centerX = Int((rawPoint.x * CGFloat(width)).rounded())
        let centerY = Int((rawPoint.y * CGFloat(height)).rounded())
        var values: [Float] = []

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32,
              let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        for y in max(0, centerY - radius)...min(height - 1, centerY + radius) {
            let row = baseAddress.advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: Float32.self)
            for x in max(0, centerX - radius)...min(width - 1, centerX + radius) {
                let value = Float(row[x])
                if value.isFinite,
                   value >= Constants.minimumReadableDepthMeters,
                   value <= Constants.maximumValidDepthMeters {
                    values.append(value)
                }
            }
        }

        return robustDepth(from: values)
    }

    private func makeLocalCalibration(faceBounds: NormalizedRect,
                                      depthMap: CVPixelBuffer,
                                      frame: RearDepthFrame,
                                      calibrationData: AVCameraCalibrationData,
                                      imageSize: CGSize,
                                      orientation: CGImagePropertyOrientation) -> LocalFaceScaleCalibration {
        var samples: [LocalFaceScaleSample] = []
        let columns = max(Constants.localGridColumns, 2)
        let rows = max(Constants.localGridRows, 2)
        let focal = orientedFocalLengths(from: calibrationData,
                                         rawImageSize: rawImageSize(for: frame.pixelBuffer),
                                         orientation: orientation)
        guard focal.fx > 0, focal.fy > 0 else { return .empty }

        for row in 0..<rows {
            for column in 0..<columns {
                let xProgress = CGFloat(column) / CGFloat(columns - 1)
                let yProgress = CGFloat(row) / CGFloat(rows - 1)
                let point = NormalizedPoint(
                    x: faceBounds.x + (faceBounds.width * xProgress),
                    y: faceBounds.y + (faceBounds.height * yProgress)
                ).clamped()
                guard let depth = medianDepth(from: depthMap,
                                              at: point,
                                              orientation: orientation,
                                              radius: Constants.localDepthRadius) else {
                    continue
                }

                let horizontalReference = (Double(depth) * 1000.0 / focal.fx) * Double(imageSize.width)
                let verticalReference = (Double(depth) * 1000.0 / focal.fy) * Double(imageSize.height)
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

        let filtered = filteredLocalSamples(from: samples)
        guard filtered.count >= Constants.minimumLocalSamples else { return .empty }
        return LocalFaceScaleCalibration(samples: filtered.sorted { first, second in
            first.point.y == second.point.y ? first.point.x < second.point.x : first.point.y < second.point.y
        })
    }

    private func filteredLocalSamples(from samples: [LocalFaceScaleSample]) -> [LocalFaceScaleSample] {
        guard samples.count >= Constants.minimumLocalSamples,
              let horizontalCenter = robustMean(samples.map(\.horizontalReferenceMM)),
              let verticalCenter = robustMean(samples.map(\.verticalReferenceMM)),
              let depthCenter = robustMean(samples.map(\.depthMM)) else {
            return samples
        }

        let filtered = samples.filter { sample in
            let horizontalError = abs(sample.horizontalReferenceMM - horizontalCenter) / max(horizontalCenter, 0.001)
            let verticalError = abs(sample.verticalReferenceMM - verticalCenter) / max(verticalCenter, 0.001)
            let depthError = abs(sample.depthMM - depthCenter)
            return horizontalError <= Constants.localScaleToleranceRatio &&
                verticalError <= Constants.localScaleToleranceRatio &&
                depthError <= Constants.localDepthToleranceMM
        }

        return filtered.count >= Constants.minimumLocalSamples ? filtered : samples
    }

    /// Rejeita escalas claramente incompativeis com a faixa curta de captura traseira.
    private func isPlausibleRearDepthCaptureScale(_ calibration: PostCaptureCalibration) -> Bool {
        let minimumRearReferenceMM = 80.0
        return calibration.horizontalReferenceMM >= minimumRearReferenceMM &&
            calibration.verticalReferenceMM >= minimumRearReferenceMM
    }

    // MARK: - Pose
    private func makeHeadPose(from face: VNFaceObservation,
                              centralPoint: NormalizedPoint,
                              centralCameraPoint: SIMD3<Float>,
                              frame: RearDepthFrame,
                              depthMap: CVPixelBuffer,
                              calibrationData: AVCameraCalibrationData,
                              imageSize: CGSize,
                              orientation: CGImagePropertyOrientation,
                              timestamp: TimeInterval) -> HeadPoseSnapshot? {
        let vision = visionHeadPoseAngles(from: face)
        let depth = depthHeadPoseAngles(from: face,
                                        centralPoint: centralPoint,
                                        centralCameraPoint: centralCameraPoint,
                                        frame: frame,
                                        depthMap: depthMap,
                                        calibrationData: calibrationData,
                                        imageSize: imageSize,
                                        orientation: orientation)
        let roll = depth?.roll ?? vision?.roll
        let yaw = depth?.yaw ?? vision?.yaw
        let pitch = depth?.pitch ?? vision?.pitch
        guard let roll, let yaw, let pitch else { return nil }

        let snapshot = HeadPoseSnapshot(rollDegrees: roll,
                                        yawDegrees: yaw,
                                        pitchDegrees: pitch,
                                        timestamp: timestamp,
                                        sensor: .rearDepth)
        return snapshot.isValid ? snapshot : nil
    }

    private func visionHeadPoseAngles(from face: VNFaceObservation) -> RearDepthHeadPoseAngles? {
        let roll = face.roll.map { radiansToDegrees(Float($0.doubleValue)) }
        let yaw = face.yaw.map { radiansToDegrees(Float($0.doubleValue)) }
        let pitch = face.pitch.map { radiansToDegrees(Float($0.doubleValue)) }
        guard roll != nil || yaw != nil || pitch != nil else { return nil }
        return RearDepthHeadPoseAngles(roll: roll, yaw: yaw, pitch: pitch)
    }

    private func depthHeadPoseAngles(from face: VNFaceObservation,
                                     centralPoint: NormalizedPoint,
                                     centralCameraPoint: SIMD3<Float>,
                                     frame: RearDepthFrame,
                                     depthMap: CVPixelBuffer,
                                     calibrationData: AVCameraCalibrationData,
                                     imageSize: CGSize,
                                     orientation: CGImagePropertyOrientation) -> RearDepthHeadPoseAngles? {
        let eyePoints = resolvedEyeLandmarkPoints(face: face, imageSize: imageSize)
            .sorted { $0.x < $1.x }
        guard eyePoints.count >= 2 else { return nil }

        let imageLeftEye = eyePoints[0]
        let imageRightEye = eyePoints[1]
        let roll = clampedPoseDegrees(
            radiansToDegrees(Float(atan2(Double(imageRightEye.y - imageLeftEye.y),
                                         Double(imageRightEye.x - imageLeftEye.x))))
        )

        guard let leftDepth = medianDepth(from: depthMap,
                                          at: imageLeftEye,
                                          orientation: orientation,
                                          radius: Constants.localDepthRadius),
              let rightDepth = medianDepth(from: depthMap,
                                           at: imageRightEye,
                                           orientation: orientation,
                                           radius: Constants.localDepthRadius),
              let leftCameraPoint = cameraPoint(for: imageLeftEye,
                                                depth: leftDepth,
                                                frame: frame,
                                                calibrationData: calibrationData,
                                                orientation: orientation),
              let rightCameraPoint = cameraPoint(for: imageRightEye,
                                                 depth: rightDepth,
                                                 frame: frame,
                                                 calibrationData: calibrationData,
                                                 orientation: orientation),
              let lowerFacePoint = lowerFaceReferencePoint(from: face,
                                                           centralPoint: centralPoint,
                                                           imageSize: imageSize),
              let lowerDepth = medianDepth(from: depthMap,
                                           at: lowerFacePoint,
                                           orientation: orientation,
                                           radius: Constants.localDepthRadius),
              let lowerCameraPoint = cameraPoint(for: lowerFacePoint,
                                                 depth: lowerDepth,
                                                 frame: frame,
                                                 calibrationData: calibrationData,
                                                 orientation: orientation),
              let horizontalAxis = normalizedVector(rightCameraPoint - leftCameraPoint),
              let verticalAxis = normalizedVector(lowerCameraPoint - ((leftCameraPoint + rightCameraPoint) * 0.5)),
              var faceForward = normalizedVector(simd_cross(horizontalAxis, verticalAxis)) else {
            return RearDepthHeadPoseAngles(roll: roll, yaw: nil, pitch: nil)
        }

        let cameraDirection = normalizedVector(-centralCameraPoint) ?? SIMD3<Float>(0, 0, -1)
        if simd_dot(faceForward, cameraDirection) < 0 {
            faceForward = -faceForward
        }

        let forwardDepth = max(-faceForward.z, 0.0001)
        let normalYaw = clampedPoseDegrees(radiansToDegrees(atan2(faceForward.x, forwardDepth)))
        let yaw = depthYawDegrees(leftCameraPoint: leftCameraPoint,
                                  rightCameraPoint: rightCameraPoint) ?? normalYaw
        let pitch = clampedPoseDegrees(radiansToDegrees(atan2(faceForward.y, forwardDepth)))
        return RearDepthHeadPoseAngles(roll: roll, yaw: yaw, pitch: pitch)
    }

    private func depthYawDegrees(leftCameraPoint: SIMD3<Float>,
                                 rightCameraPoint: SIMD3<Float>) -> Float? {
        let eyeAxis = rightCameraPoint - leftCameraPoint
        let horizontalDistance = max(abs(eyeAxis.x), 0.0001)
        guard eyeAxis.z.isFinite,
              horizontalDistance.isFinite else {
            return nil
        }

        return clampedPoseDegrees(radiansToDegrees(atan2(eyeAxis.z, horizontalDistance)))
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

    private func lowerFaceReferencePoint(from face: VNFaceObservation,
                                         centralPoint: NormalizedPoint,
                                         imageSize: CGSize) -> NormalizedPoint? {
        let imageWidth = Int(imageSize.width)
        let imageHeight = Int(imageSize.height)
        guard imageWidth > 0, imageHeight > 0 else { return nil }

        let points = normalizedPoints(from: face.landmarks?.noseCrest,
                                      face: face,
                                      imageWidth: imageWidth,
                                      imageHeight: imageHeight) +
            normalizedPoints(from: face.landmarks?.medianLine,
                             face: face,
                             imageWidth: imageWidth,
                             imageHeight: imageHeight)
        if let lower = points
            .filter({ $0.y > centralPoint.y })
            .max(by: { $0.y < $1.y }) {
            return NormalizedPoint(x: lower.x, y: lower.y).clamped()
        }

        let fallbackY = min(centralPoint.y + 0.16, 0.95)
        return NormalizedPoint(x: centralPoint.x, y: fallbackY).clamped()
    }

    // MARK: - Geometria ocular
    private func makeEyeGeometrySnapshot(frame: RearDepthFrame,
                                         analysis: RearDepthFrameAnalysis,
                                         depthMap: CVPixelBuffer,
                                         calibrationData: AVCameraCalibrationData,
                                         imageSize: CGSize) -> CaptureEyeGeometrySnapshot? {
        let eyePoints = resolvedEyeGeometryPoints(face: analysis.faceObservation,
                                                  frame: frame,
                                                  depthMap: depthMap,
                                                  calibrationData: calibrationData,
                                                  imageSize: imageSize,
                                                  orientation: analysis.cgOrientation)
            .sorted { $0.normalizedPoint.x < $1.normalizedPoint.x }
        guard eyePoints.count >= 2,
              let faceForward = normalizedVector(-analysis.centralCameraPoint) else {
            return nil
        }

        let imageLeftEye = eyePoints[0]
        let imageRightEye = eyePoints[1]
        let rightGaze = normalizedVector(-imageLeftEye.cameraPoint) ?? faceForward
        let leftGaze = normalizedVector(-imageRightEye.cameraPoint) ?? faceForward

        return CaptureEyeGeometrySnapshot(
            leftEye: .init(centerCamera: CodableVector3(imageRightEye.cameraPoint),
                           gazeCamera: CodableVector3(leftGaze),
                           projection: nil),
            rightEye: .init(centerCamera: CodableVector3(imageLeftEye.cameraPoint),
                            gazeCamera: CodableVector3(rightGaze),
                            projection: nil),
            pcCameraPosition: CodableVector3(analysis.centralCameraPoint),
            faceForwardCamera: CodableVector3(faceForward),
            fixationConfidence: Constants.rearGeometryFixationConfidence,
            fixationConfidenceReason: "Geometria ocular estimada por profundidade traseira sem LiDAR.",
            strongestGazeDeviation: 0
        )
    }

    private func resolvedEyeGeometryPoints(face: VNFaceObservation,
                                           frame: RearDepthFrame,
                                           depthMap: CVPixelBuffer,
                                           calibrationData: AVCameraCalibrationData,
                                           imageSize: CGSize,
                                           orientation: CGImagePropertyOrientation) -> [RearDepthEyeGeometryPoint] {
        resolvedEyeLandmarkPoints(face: face, imageSize: imageSize)
            .compactMap { point in
                guard let depth = medianDepth(from: depthMap,
                                              at: point,
                                              orientation: orientation,
                                              radius: Constants.localDepthRadius),
                      let cameraPoint = cameraPoint(for: point,
                                                    depth: depth,
                                                    frame: frame,
                                                    calibrationData: calibrationData,
                                                    orientation: orientation) else {
                    return nil
                }
                return RearDepthEyeGeometryPoint(normalizedPoint: point,
                                                 cameraPoint: cameraPoint)
            }
    }

    // MARK: - Projecao
    private func previewCenterOffsetMeters(for point: NormalizedPoint,
                                           depth: Float,
                                           imageSize: CGSize,
                                           frame: RearDepthFrame,
                                           calibrationData: AVCameraCalibrationData,
                                           orientation: CGImagePropertyOrientation) -> SIMD2<Float>? {
        let focal = orientedFocalLengths(from: calibrationData,
                                         rawImageSize: rawImageSize(for: frame.pixelBuffer),
                                         orientation: orientation)
        guard focal.fx > 0,
              focal.fy > 0,
              imageSize.width > 0,
              imageSize.height > 0,
              depth.isFinite,
              depth > 0 else {
            return nil
        }

        let clamped = point.clamped()
        let deltaX = (Double(clamped.x) - 0.5) * Double(imageSize.width)
        let deltaY = (Double(clamped.y) - 0.5) * Double(imageSize.height)
        return SIMD2<Float>(Float(deltaX / focal.fx) * depth,
                            Float(deltaY / focal.fy) * depth)
    }

    private func cameraPoint(for point: NormalizedPoint,
                             depth: Float,
                             frame: RearDepthFrame,
                             calibrationData: AVCameraCalibrationData,
                             orientation: CGImagePropertyOrientation) -> SIMD3<Float>? {
        let rawSize = rawImageSize(for: frame.pixelBuffer)
        let rawPoint = rawDepthPoint(from: point,
                                     orientation: orientation)
        let scaledIntrinsics = scaledRawIntrinsics(from: calibrationData,
                                                   rawImageSize: rawSize)
        guard scaledIntrinsics.fx > 0,
              scaledIntrinsics.fy > 0 else {
            return nil
        }

        let pixelX = Float(rawPoint.x * rawSize.width)
        let pixelY = Float(rawPoint.y * rawSize.height)
        let x = (pixelX - Float(scaledIntrinsics.cx)) / Float(scaledIntrinsics.fx) * depth
        let y = (pixelY - Float(scaledIntrinsics.cy)) / Float(scaledIntrinsics.fy) * depth
        return orientedCameraPoint(rawX: x,
                                   rawY: y,
                                   depth: depth,
                                   orientation: orientation)
    }

    private func scaledRawIntrinsics(from calibrationData: AVCameraCalibrationData,
                                     rawImageSize: CGSize) -> (fx: Double, fy: Double, cx: Double, cy: Double) {
        let matrix = calibrationData.intrinsicMatrix
        let reference = calibrationData.intrinsicMatrixReferenceDimensions
        guard reference.width > 0, reference.height > 0 else {
            return (Double(matrix.columns.0.x),
                    Double(matrix.columns.1.y),
                    Double(matrix.columns.2.x),
                    Double(matrix.columns.2.y))
        }

        let scaleX = Double(rawImageSize.width / reference.width)
        let scaleY = Double(rawImageSize.height / reference.height)
        return (Double(matrix.columns.0.x) * scaleX,
                Double(matrix.columns.1.y) * scaleY,
                Double(matrix.columns.2.x) * scaleX,
                Double(matrix.columns.2.y) * scaleY)
    }

    private func orientedFocalLengths(from calibrationData: AVCameraCalibrationData,
                                      rawImageSize: CGSize,
                                      orientation: CGImagePropertyOrientation) -> (fx: Double, fy: Double) {
        let scaled = scaledRawIntrinsics(from: calibrationData,
                                         rawImageSize: rawImageSize)
        return orientation.rotatesDimensions ? (scaled.fy, scaled.fx) : (scaled.fx, scaled.fy)
    }

    private func rawImageSize(for pixelBuffer: CVPixelBuffer) -> CGSize {
        CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
               height: CVPixelBufferGetHeight(pixelBuffer))
    }

    private func orientedSize(for pixelBuffer: CVPixelBuffer,
                              orientation: CGImagePropertyOrientation) -> CGSize {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        return orientation.rotatesDimensions ?
            CGSize(width: height, height: width) :
            CGSize(width: width, height: height)
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

    // MARK: - Estatistica
    private func robustDepth(from values: [Float]) -> Float? {
        let sorted = values
            .filter { $0.isFinite && $0 >= Constants.minimumReadableDepthMeters && $0 <= Constants.maximumValidDepthMeters }
            .sorted()
        guard !sorted.isEmpty else { return nil }

        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) * 0.5
        }
        return sorted[middle]
    }

    private func robustMean(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let trim = Int(Double(sorted.count) * 0.10)
        let usable = Array(sorted.dropFirst(trim).dropLast(trim))
        let finalValues = usable.isEmpty ? sorted : usable
        return finalValues.reduce(0, +) / Double(finalValues.count)
    }

    private func normalizedVector(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
        let length = simd_length(vector)
        guard length.isFinite, length > .ulpOfOne else { return nil }
        return vector / length
    }

    private func radiansToDegrees(_ radians: Float) -> Float {
        radians * (180.0 / .pi)
    }

    private func clampedPoseDegrees(_ degrees: Float) -> Float {
        guard degrees.isFinite else { return 0 }
        return min(max(degrees, -Constants.maximumFallbackPoseDegrees),
                   Constants.maximumFallbackPoseDegrees)
    }

    private func cachedFrameAnalysis(timestamp: TimeInterval) -> RearDepthFrameAnalysis? {
        cacheQueue.sync {
            guard cachedTimestamp == timestamp else { return nil }
            return cachedAnalysis
        }
    }

    private func storeCachedFrameAnalysis(_ analysis: RearDepthFrameAnalysis,
                                          timestamp: TimeInterval) {
        cacheQueue.sync {
            cachedTimestamp = timestamp
            cachedAnalysis = analysis
        }
    }
}

// MARK: - Concurrency
/// O motor nao mantem estado mutavel entre frames fora do cache protegido.
extension RearDepthFallbackMeasurementEngine: @unchecked Sendable {}

/// O frame e entregue por filas seriais controladas pelo pipeline de captura.
extension RearDepthFrame: @unchecked Sendable {}

private extension CGImagePropertyOrientation {
    var rotatesDimensions: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        default:
            return false
        }
    }
}
