//
//  DistanceVerification.swift
//  MedidorOticaApp
//
//  Verificação de Distância
//
//  Objetivo:
//  - Garantir que o usuário esteja a uma distância adequada da câmera
//  - Fornecer feedback em tempo real sobre a distância atual
//  - Suportar diferentes sensores (TrueDepth e LiDAR) para máxima precisão
//
//  Critérios de Aceitação:
//  1. Distância ideal entre 28cm e 45cm do dispositivo
//  2. Face projetada com tamanho suficiente para garantir precisão
//  3. Feedback visual claro quando fora da faixa ideal
//  
//  Sensores Suportados:
//  - TrueDepth (câmera frontal): Usa ARFaceAnchor para medição precisa
//  - LiDAR (câmera traseira): Usa depth map para medição de profundidade
//
//  Notas de Desempenho:
//  - Processamento assíncrono para não bloquear a UI
//  - Cache de valores para evitar cálculos repetitivos
//  - Fatores de correção específicos por dispositivo

import ARKit
import Vision
import simd

/// Limites globais de distância (centímetros)
struct DistanceLimits {
    /// Distância mínima permitida
    static let minCm: Float = 28.0
    /// Distância máxima permitida
    static let maxCm: Float = 45.0
}

// MARK: - Extensão para verificação de distância
extension VerificationManager {
    
    // MARK: - Constantes
    
    private enum DistanceConstants {
        // Distância mínima em metros (conversão de centímetros)
        static let minDistanceMeters: Float = DistanceLimits.minCm / 100
        // Distância máxima em metros
        static let maxDistanceMeters: Float = DistanceLimits.maxCm / 100
        // Limite superior para descartar leituras inválidas
        static let maxValidDepth: Float = 10.0
        // Tamanho mínimo projetado da face para impedir capturas distantes demais.
        static let minProjectedFaceWidthRatio: Float = 0.22
        static let minProjectedFaceHeightRatio: Float = 0.30
    }

    /// Resultado completo da verificação de distância.
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

    
    // MARK: - Verificação de Distância
    
    /// Verifica se o rosto está a uma distância adequada da câmera
    /// - Parameters:
    ///   - frame: O frame AR atual para análise
    ///   - faceAnchor: O anchor do rosto detectado (opcional, usado apenas para TrueDepth)
    /// - Returns: Booleano indicando se a distância está dentro do intervalo aceitável
    func checkDistance(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> Bool {
        // Verifica a disponibilidade dos sensores
        guard let measurement = getDistanceMeasurement(using: frame, faceAnchor: faceAnchor) else {
            handleDistanceVerificationError(reason: "Sensores de profundidade indisponíveis")
            return false
        }

        // Verifica se a distância está dentro do intervalo aceitável
        let isWithinRange = (DistanceConstants.minDistanceMeters...DistanceConstants.maxDistanceMeters).contains(measurement.distance)
        let isWithinProjectedRange = !measurement.projectedFaceTooSmall
        let isValid = measurement.hasValidDepth && isWithinProjectedRange

        // Atualiza a interface do usuário com os resultados
        updateDistanceUI(distance: measurement.distance,
                         isValid: isWithinRange && isValid,
                         projectedFaceWidthRatio: measurement.projectedFaceWidthRatio,
                         projectedFaceHeightRatio: measurement.projectedFaceHeightRatio,
                         projectedFaceTooSmall: measurement.projectedFaceTooSmall)

        return isWithinRange && isValid
    }
    
    // MARK: - Medição de Distância
    
    /// Obtém a medição de distância usando o sensor apropriado
    private func getDistanceMeasurement(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> DistanceMeasurement? {
        let sensors = preferredSensors(requireFaceAnchor: true, faceAnchorAvailable: faceAnchor != nil)

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

    /// Consolida a distância e o tamanho projetado do rosto para a câmera frontal.
    private func makeTrueDepthMeasurement(faceAnchor: ARFaceAnchor,
                                          frame: ARFrame) -> DistanceMeasurement {
        let distance = getMeasuredDistanceWithTrueDepth(faceAnchor: faceAnchor, frame: frame)
        let projectedSize = projectedFaceSizeWithTrueDepth(faceAnchor: faceAnchor, frame: frame)

        return DistanceMeasurement(distance: distance,
                                   projectedFaceWidthRatio: projectedSize?.widthRatio ?? 0,
                                   projectedFaceHeightRatio: projectedSize?.heightRatio ?? 0)
    }
    
    // MARK: - Atualização da Interface
    
    /// Atualiza a interface do usuário com os resultados da medição de distância
    private func updateDistanceUI(distance: Float,
                                  isValid: Bool,
                                  projectedFaceWidthRatio: Float,
                                  projectedFaceHeightRatio: Float,
                                  projectedFaceTooSmall: Bool) {
        let distanceInCm = distance * 100.0
        print("📏 Distância medida: \(String(format: "%.1f", distanceInCm)) cm")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.lastMeasuredDistance = Float(distanceInCm)
            self.projectedFaceTooSmall = projectedFaceTooSmall
            self.projectedFaceWidthRatio = projectedFaceWidthRatio
            self.projectedFaceHeightRatio = projectedFaceHeightRatio

            // Feedback adicional baseado na distância
            if !isValid {
                let message: String
                if projectedFaceTooSmall {
                    message = "Face ainda pequena no enquadramento"
                } else {
                    message = distance < DistanceConstants.minDistanceMeters ? "Muito perto" : "Muito longe"
                }
                print("⚠️ \(message): \(String(format: "%.1f", distanceInCm)) cm")
            }
        }
    }
    
    // MARK: - Medição com TrueDepth (Câmera Frontal)
    
    /// Mede a distância usando o sensor TrueDepth e a geometria 3D do rosto
    /// - Parameters:
    ///   - faceAnchor: Anchor do rosto detectado
    ///   - frame: Frame atual para referência de câmera
    /// - Returns: Distância em metros ou 0 se inválida
    private func getMeasuredDistanceWithTrueDepth(faceAnchor: ARFaceAnchor, frame: ARFrame) -> Float {
        // Calcula a posição dos olhos no sistema de coordenadas da câmera
        let worldToCamera = simd_inverse(frame.camera.transform)
        let leftEyeWorld = simd_mul(faceAnchor.transform, faceAnchor.leftEyeTransform)
        let rightEyeWorld = simd_mul(faceAnchor.transform, faceAnchor.rightEyeTransform)

        let leftEye = simd_mul(worldToCamera, leftEyeWorld)
        let rightEye = simd_mul(worldToCamera, rightEyeWorld)

        let leftDistance = abs(leftEye.columns.3.z)
        let rightDistance = abs(rightEye.columns.3.z)
        let average = (leftDistance + rightDistance) / 2

        guard average > 0, average < DistanceConstants.maxValidDepth else {
            print("⚠️ Distância TrueDepth fora do intervalo válido: \(average)m")
            return 0
        }

        print("📏 TrueDepth olhos: \(String(format: "%.1f", average * 100)) cm")
        return average
    }
    
    // MARK: - Medição com LiDAR (Câmera Traseira)
    
    /// Mede a distância usando o sensor LiDAR
    /// - Parameter frame: O frame AR atual para análise
    /// - Returns: Distância em metros ou 0 se inválida
    private func getMeasuredDistanceWithLiDAR(frame: ARFrame) -> Float {
        // Obtém os dados de profundidade do frame AR
        guard let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth else {
            print("❌ Dados de profundidade LiDAR não disponíveis")
            return 0
        }
        
        // Requisição usando a revisão mais recente do Vision
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
                print("⚠️ Olhos não detectados com LiDAR")
                return 0
            }

            let width = CVPixelBufferGetWidth(depthData.depthMap)
            let height = CVPixelBufferGetHeight(depthData.depthMap)

            let leftCenter = averagePoint(from: leftEye.normalizedPoints)
            let rightCenter = averagePoint(from: rightEye.normalizedPoints)

            func convert(_ p: CGPoint) -> CGPoint {
                CGPoint(x: p.x * CGFloat(width), y: (1 - p.y) * CGFloat(height))
            }

            var depths: [Float] = []
            if let d = depthValue(from: depthData.depthMap, at: convert(leftCenter)) { depths.append(d) }
            if let d = depthValue(from: depthData.depthMap, at: convert(rightCenter)) { depths.append(d) }

            guard !depths.isEmpty else {
                print("⚠️ Não foi possível medir a profundidade dos olhos")
                return 0
            }

            let avgDepth = depths.reduce(0, +) / Float(depths.count)
            guard avgDepth > 0, avgDepth < DistanceConstants.maxValidDepth else { return 0 }

            print("📏 LiDAR olhos: \(String(format: "%.1f", avgDepth * 100)) cm")
            return avgDepth
        } catch {
            print("ERRO na medição de distância com LiDAR: \(error)")
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
    
    // MARK: - Tratamento de Erros
    
    /// Manipula erros durante a verificação de distância
    private func handleDistanceVerificationError(reason: String) {
        print("❌ Erro na verificação de distância: \(reason)")
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("DistanceVerificationError"),
                object: nil,
                userInfo: [
                    "reason": reason,
                    "timestamp": Date().timeIntervalSince1970
                ]
            )
        }
    }
}

// MARK: - Helpers geométricos
private extension VerificationManager {
    /// Converte a resolução da câmera para o viewport efetivo considerando a orientação atual.
    func orientedViewportSize(for resolution: CGSize,
                              orientation: CGImagePropertyOrientation) -> CGSize {
        orientation.isPortrait ?
            CGSize(width: resolution.height, height: resolution.width) :
            resolution
    }

    /// Converte um vértice da malha em ponto 3D no mundo.
    func worldPosition(of vertex: simd_float3,
                       transform: simd_float4x4) -> simd_float3 {
        let position = simd_mul(transform, SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1))
        return simd_float3(position.x, position.y, position.z)
    }
}

