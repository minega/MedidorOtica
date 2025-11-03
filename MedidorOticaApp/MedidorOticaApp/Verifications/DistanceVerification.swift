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
//  1. Distância ideal entre 25cm e 50cm do dispositivo
//  2. Feedback visual claro quando fora da faixa ideal
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

/// Limites globais de distância (centímetros)
struct DistanceLimits {
    /// Distância mínima permitida
    static let minCm: Float = 25.0
    /// Distância máxima permitida
    static let maxCm: Float = 60.0
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
    }

    
    // MARK: - Verificação de Distância
    
    /// Verifica se o rosto está a uma distância adequada da câmera
    /// - Parameters:
    ///   - frame: O frame AR atual para análise
    ///   - faceAnchor: O anchor do rosto detectado (opcional, usado apenas para TrueDepth)
    /// - Returns: Booleano indicando se a distância está dentro do intervalo aceitável
    func checkDistance(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> Bool {
        // Verifica a disponibilidade dos sensores
        guard let (distance, isValid) = getDistanceMeasurement(using: frame, faceAnchor: faceAnchor) else {
            handleDistanceVerificationError(reason: "Sensores de profundidade indisponíveis")
            return false
        }
        
        // Verifica se a distância está dentro do intervalo aceitável
        let isWithinRange = (DistanceConstants.minDistanceMeters...DistanceConstants.maxDistanceMeters).contains(distance)
        
        // Atualiza a interface do usuário com os resultados
        updateDistanceUI(distance: distance, isValid: isWithinRange)
        
        return isWithinRange && isValid
    }
    
    // MARK: - Medição de Distância
    
    /// Obtém a medição de distância usando o sensor apropriado
    private func getDistanceMeasurement(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> (distance: Float, isValid: Bool)? {
        let sensors = preferredSensors(requireFaceAnchor: true, faceAnchorAvailable: faceAnchor != nil)

        guard !sensors.isEmpty else { return nil }

        for sensor in sensors {
            switch sensor {
            case .trueDepth:
                guard let anchor = faceAnchor else { continue }
                let distance = getMeasuredDistanceWithTrueDepth(faceAnchor: anchor, frame: frame)
                return (distance, distance > 0)
            case .liDAR:
                let distance = getMeasuredDistanceWithLiDAR(frame: frame)
                return (distance, distance > 0 && distance < DistanceConstants.maxValidDepth)
            case .none:
                continue
            }
        }

        return nil
    }
    
    // MARK: - Atualização da Interface
    
    /// Atualiza a interface do usuário com os resultados da medição de distância
    private func updateDistanceUI(distance: Float, isValid: Bool) {
        let distanceInCm = distance * 100.0
        print("📏 Distância medida: \(String(format: "%.1f", distanceInCm)) cm")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.lastMeasuredDistance = Float(distanceInCm)

            // Feedback adicional baseado na distância
            if !isValid {
                let message = distance < DistanceConstants.minDistanceMeters ? "Muito perto" : "Muito longe"
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

