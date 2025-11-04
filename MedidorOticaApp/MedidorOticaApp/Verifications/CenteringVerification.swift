//
//  CenteringVerification.swift
//  MedidorOticaApp
//
//  Verificação de Centralização do Rosto
//
//  Objetivo:
//  - Garantir que o rosto esteja perfeitamente centralizado na câmera
//  - Posicionar o dispositivo no meio do nariz, na altura das pupilas
//  - Fornecer feedback visual sobre o posicionamento
//
//  Critérios de Aceitação:
//  1. Centralização horizontal (eixo X) com margem de ±0,5cm
//  2. Centralização vertical (eixo Y) com margem de ±0,5cm
//  3. Alinhamento do nariz com o centro da câmera
//
//  Técnicas Utilizadas:
//  - ARKit Face Tracking para detecção precisa de pontos faciais
//  - Cálculos 3D para determinar o posicionamento relativo
//  - Tolerância ajustável para diferentes cenários de uso
//
//  Notas de Desempenho:
//  - Processamento otimizado para execução em tempo real
//  - Uso eficiente de memória com reutilização de estruturas
//  - Cálculos otimizados para evitar sobrecarga na CPU/GPU

import Foundation
import ARKit
import Vision
import simd
import CoreGraphics

// MARK: - Extensões

extension Notification.Name {
    /// Notificação enviada quando o status de centralização do rosto é atualizado
    static let faceCenteringUpdated = Notification.Name("faceCenteringUpdated")
}

// MARK: - Extensão para verificação de centralização
extension VerificationManager {
    
    // MARK: - Constantes
    
    private enum CenteringConstants {
        // Tolerância de 0,5 cm convertida para metros
        static let tolerance: Float = 0.005

        // Índice do vértice correspondente à ponta do nariz
        struct FaceIndices {
            static let noseTip = 9
        }
    }

    /// Medidas calculadas para orientar o ajuste da câmera em relação ao PC
    private struct FaceCenteringMetrics {
        let horizontal: Float
        let vertical: Float
        let noseAlignment: Float
    }
    
    // MARK: - Verificação de Centralização
    
    /// Verifica se o rosto está corretamente centralizado na câmera
    /// - Parameters:
    ///   - frame: O frame AR atual (não utilizado, mantido para compatibilidade)
    ///   - faceAnchor: O anchor do rosto detectado pelo ARKit
    /// - Returns: Booleano indicando se o rosto está perfeitamente centralizado
    /// Confere se o rosto está centralizado
    func checkFaceCentering(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> Bool {
        let sensors = preferredSensors(requireFaceAnchor: true, faceAnchorAvailable: faceAnchor != nil)

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
            print("❌ Não foi possível calcular métricas de centralização válidas")
            return false
        }

        return evaluateCentering(using: metrics)
    }

    /// Calcula métricas de centralização em metros compensando o deslocamento da lente TrueDepth na tela.
    private func makeAlignedTrueDepthMetrics(faceAnchor: ARFaceAnchor, frame: ARFrame) -> FaceCenteringMetrics? {
        let vertices = faceAnchor.geometry.vertices

        guard vertices.count > CenteringConstants.FaceIndices.noseTip else {
            return nil
        }

        // Obtém a transformação do rosto diretamente no espaço da câmera para eliminar
        // discrepâncias de tela/lente e usar a posição física real do sensor.
        let worldToCamera = simd_inverse(frame.camera.transform)
        let faceInCamera = simd_mul(worldToCamera, faceAnchor.transform)

        // Converte os principais pontos faciais para coordenadas da câmera (em metros).
        guard let nosePosition = positionFromHomogeneous(
            simd_mul(faceInCamera, simd_float4(vertices[CenteringConstants.FaceIndices.noseTip], 1))
        ) else {
            return nil
        }

        // O centro da face no espaço da câmera representa a posição ideal que deve coincidir com a origem.
        let faceCenter = translation(from: faceInCamera)

        let leftEyeTransform = simd_mul(faceInCamera, faceAnchor.leftEyeTransform)
        let rightEyeTransform = simd_mul(faceInCamera, faceAnchor.rightEyeTransform)

        let leftEyePosition = translation(from: leftEyeTransform)
        let rightEyePosition = translation(from: rightEyeTransform)

        // Altura da pupila calculada pela média das posições das duas pupilas no espaço da câmera.
        let eyeCenter = (leftEyePosition + rightEyePosition) / 2

        // Calcula o centro do nariz em relação ao centro médio das pupilas para evitar viés lateral.
        let eyesCenterX = (leftEyePosition.x + rightEyePosition.x) / 2
        let noseAlignmentOffset = nosePosition.x - eyesCenterX

        return FaceCenteringMetrics(horizontal: faceCenter.x,
                                    vertical: faceCenter.y,
                                    noseAlignment: noseAlignmentOffset)
    }

    private func checkCenteringWithLiDAR(frame: ARFrame) -> Bool {
        guard let depthMap = frame.sceneDepth?.depthMap ?? frame.smoothedSceneDepth?.depthMap else {
            print("❌ Dados de profundidade LiDAR não disponíveis")
            return false
        }

        let request = makeLandmarksRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: frame.capturedImage,
            orientation: currentCGOrientation(),
            options: [:]
        )
        do {
            try handler.perform([request])
            guard let face = request.results?.first as? VNFaceObservation,
                  let landmarks = face.landmarks else { return false }

            let orientation = currentCGOrientation()
            let (depthWidth, depthHeight) = orientedDimensions(for: depthMap, orientation: orientation)
            let resolution = frame.camera.imageResolution
            let intrinsics = frame.camera.intrinsics

            // Calcula pontos médios para nariz e pupilas nas orientações da câmera e do depth map.
            let nosePoints = resolvedLandmarkPoints(from: landmarks.nose?.normalizedPoints,
                                                    boundingBox: face.boundingBox,
                                                    imageWidth: Int(resolution.width),
                                                    imageHeight: Int(resolution.height),
                                                    orientation: orientation)
                ?? fallbackResolvedPoint(at: CGPoint(x: face.boundingBox.midX, y: face.boundingBox.midY),
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

            // Amostragem de profundidade usando a grade do depth map já orientada.
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

            let eyesCenter = (leftEyeCamera + rightEyeCamera) / 2
            let noseAlignmentOffset = noseCamera.x - (leftEyeCamera.x + rightEyeCamera.x) / 2

            let metrics = FaceCenteringMetrics(
                horizontal: eyesCenter.x,
                vertical: eyesCenter.y,
                noseAlignment: noseAlignmentOffset
            )

            return evaluateCentering(using: metrics)
        } catch {
            print("Erro ao verificar centralização com Vision: \(error)")
            return false
        }
    }

    /// Calcula pontos médios convertidos para o espaço da câmera e para o depth map.
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

    /// Converte um ponto normalizado genérico para coordenadas utilizadas pelo depth map e pela câmera.
    private func fallbackResolvedPoint(at normalizedPoint: CGPoint,
                                       imageWidth: Int,
                                       imageHeight: Int,
                                       orientation: CGImagePropertyOrientation) -> (camera: CGPoint, depth: CGPoint) {
        let pixelPoint = VNImagePointForNormalizedPoint(normalizedPoint,
                                                        imageWidth,
                                                        imageHeight)
        let rawCameraNormalized = CGPoint(x: pixelPoint.x / CGFloat(imageWidth),
                                          y: pixelPoint.y / CGFloat(imageHeight))
        let cameraNormalized = clampedNormalizedPoint(rawCameraNormalized)
        let depthNormalized = self.normalizedPoint(pixelPoint,
                                                  width: imageWidth,
                                                  height: imageHeight,
                                                  orientation: orientation)
        return (camera: cameraNormalized, depth: depthNormalized)
    }

    // MARK: - Avaliação de métricas

    /// Avalia se o rosto está centralizado com base nas métricas calculadas
    private func evaluateCentering(using metrics: FaceCenteringMetrics) -> Bool {
        // Verifica se os desvios estão dentro da tolerância permitida
        let isHorizontallyAligned = abs(metrics.horizontal) < CenteringConstants.tolerance
        let isVerticallyAligned = abs(metrics.vertical) < CenteringConstants.tolerance
        let isNoseAligned = abs(metrics.noseAlignment) < CenteringConstants.tolerance

        // Resultado global
        let isCentered = isHorizontallyAligned && isVerticallyAligned && isNoseAligned

        // Atualiza a interface com os valores reais, sem compensações fixas
        updateCenteringUI(
            horizontalOffset: metrics.horizontal,
            verticalOffset: metrics.vertical,
            noseOffset: metrics.noseAlignment,
            isCentered: isCentered
        )

        return isCentered
    }

    // MARK: - Atualização da Interface
    
    /// Atualiza a interface do usuário com os resultados da verificação de centralização
    private func updateCenteringUI(horizontalOffset: Float, verticalOffset: Float,
                                 noseOffset: Float, isCentered: Bool) {
        // Converte as medidas para centímetros para exibição
        let horizontalCm = horizontalOffset * 100
        let verticalCm = verticalOffset * 100
        let noseCm = noseOffset * 100
        
        // Log detalhado para debug
        print("""
        📏 Centralização (cm):
           - Horizontal: \(String(format: "%+.2f", horizontalCm)) cm
           - Vertical:   \(String(format: "%+.2f", verticalCm)) cm
           - Nariz:      \(String(format: "%+.2f", noseCm)) cm
           - Alinhado:   \(isCentered ? "✅" : "❌")
        """)
        
        // Atualiza a interface na thread principal
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Armazena o status atualizado para sincronizar com a notificação disparada
            self.faceAligned = isCentered

            // Armazena os desvios para feedback visual
            self.facePosition = [
                "x": horizontalCm,
                "y": verticalCm,
                "z": noseCm
            ]

            // Notifica a interface sobre a atualização
            self.notifyCenteringUpdate(isCentered: isCentered)
        }
    }

    /// Notifica a interface sobre a atualização do status de centralização
    private func notifyCenteringUpdate(isCentered: Bool) {
        NotificationCenter.default.post(
            name: .faceCenteringUpdated,
            object: nil,
            userInfo: [
                "isCentered": isCentered,
                "offsets": facePosition,
                "timestamp": Date().timeIntervalSince1970
            ]
        )
    }
}

// MARK: - Conversores auxiliares

private extension VerificationManager {
    /// Converte um vetor homogêneo em coordenadas 3D usuais.
    func positionFromHomogeneous(_ vector: simd_float4) -> SIMD3<Float>? {
        guard vector.w.isFinite, abs(vector.w) > Float.ulpOfOne else { return nil }
        return SIMD3<Float>(vector.x / vector.w,
                            vector.y / vector.w,
                            vector.z / vector.w)
    }

    /// Extrai o componente de translação de uma matriz 4x4.
    func translation(from transform: simd_float4x4) -> SIMD3<Float> {
        let translation = transform.columns.3
        return SIMD3<Float>(translation.x, translation.y, translation.z)
    }

    /// Converte um ponto normalizado (0...1) e sua profundidade em coordenadas da câmera.
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

    /// Converte um ponto normalizado em coordenadas de pixel considerando orientação da depth map.
    func depthPixel(from normalizedPoint: CGPoint, width: Int, height: Int) -> CGPoint {
        CGPoint(x: normalizedPoint.x * CGFloat(width),
                y: normalizedPoint.y * CGFloat(height))
    }
}
