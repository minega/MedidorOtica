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
//  1. Distância ideal entre 40cm e 60cm do dispositivo
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

// MARK: - Extensão para verificação de distância
extension VerificationManager {
    
    // MARK: - Constantes
    
    private enum DistanceConstants {
        static let minDistanceMeters: Float = 0.4  // 40cm
        static let maxDistanceMeters: Float = 1.2  // 120cm
        static let maxValidDepth: Float = 10.0     // 10 metros (filtro para valores inválidos)
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
        if hasTrueDepth, let faceAnchor = faceAnchor {
            let distance = getMeasuredDistanceWithTrueDepth(faceAnchor: faceAnchor)
            return (distance, distance > 0)
        }

        if hasLiDAR {
            let distance = getMeasuredDistanceWithLiDAR(frame: frame)
            return (distance, distance > 0 && distance < DistanceConstants.maxValidDepth)
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
            self.distanceCorrect = isValid
            self.updateAllVerifications()
            
            // Feedback adicional baseado na distância
            if !isValid {
                let message = distance < DistanceConstants.minDistanceMeters ? "Muito perto" : "Muito longe"
                print("⚠️ \(message): \(String(format: "%.1f", distanceInCm)) cm")
            }
        }
    }
    
    // MARK: - Medição com TrueDepth (Câmera Frontal)
    
    /// Mede a distância usando o sensor TrueDepth e a geometria 3D do rosto
    /// - Parameter faceAnchor: O anchor do rosto detectado
    /// - Returns: Distância em metros ou 0 se inválida
    private func getMeasuredDistanceWithTrueDepth(faceAnchor: ARFaceAnchor) -> Float {
        // A componente Z da posição é a distância perpendicular do rosto à câmera
        let distanceInMeters = abs(faceAnchor.transform.columns.3.z)
        
        // Valida a distância medida
        guard distanceInMeters > 0, distanceInMeters < DistanceConstants.maxValidDepth else {
            print("⚠️ Distância TrueDepth fora do intervalo válido: \(distanceInMeters)m")
            return 0
        }
        
        print("📏 TrueDepth: \(String(format: "%.1f", distanceInMeters * 100)) cm")
        return distanceInMeters
    }
    
    // MARK: - Medição com LiDAR (Câmera Traseira)
    
    /// Mede a distância usando o sensor LiDAR
    /// - Parameter frame: O frame AR atual para análise
    /// - Returns: Distância em metros ou 0 se inválida
    @available(iOS 13.4, *)
    private func getMeasuredDistanceWithLiDAR(frame: ARFrame) -> Float {
        // Obtém os dados de profundidade do frame AR
        guard let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth else {
            print("❌ Dados de profundidade LiDAR não disponíveis")
            return 0
        }
        
        let width = CVPixelBufferGetWidth(depthData.depthMap)
        let height = CVPixelBufferGetHeight(depthData.depthMap)
        let stepX = width / 3
        let stepY = height / 3
        var depths: [Float] = []

        for i in 0..<3 {
            for j in 0..<3 {
                let point = CGPoint(x: stepX / 2 + i * stepX, y: stepY / 2 + j * stepY)
                if let d = depthValue(from: depthData.depthMap, at: point), d > 0, d < DistanceConstants.maxValidDepth {
                    depths.append(d)
                }
            }
        }

        guard !depths.isEmpty else {
            print("⚠️ Nenhuma medição de profundidade válida encontrada")
            return 0
        }

        let avgDepth = depths.reduce(0, +) / Float(depths.count)
        print("📏 LiDAR: \(String(format: "%.1f", avgDepth * 100)) cm")
        return avgDepth
    }
    
    // MARK: - Tratamento de Erros
    
    /// Manipula erros durante a verificação de distância
    private func handleDistanceVerificationError(reason: String) {
        print("❌ Erro na verificação de distância: \(reason)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.distanceCorrect = false
            self.updateAllVerifications()
            
            // Notifica sobre o erro
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

