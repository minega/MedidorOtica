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
import Vision
import AVFoundation
import UIKit

// MARK: - Extensão para verificação de distância
extension VerificationManager {
    
    // MARK: - Constantes
    
    private enum DistanceConstants {
        static let minDistanceMeters: Float = 0.4  // 40cm
        static let maxDistanceMeters: Float = 0.6  // 60cm
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
        if ARFaceTrackingConfiguration.isSupported, let faceAnchor = faceAnchor {
            // Usando TrueDepth (câmera frontal)
            let distance = getMeasuredDistanceWithTrueDepth(faceAnchor: faceAnchor)
            return (distance, distance > 0)
            
        } else if #available(iOS 13.4, *), ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            // Usando LiDAR (câmera traseira)
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
        
        // Aplica fator de correção específico do dispositivo
        let correctedDistance = distanceInMeters * getDeviceCorrectionFactor()
        
        print("📏 TrueDepth: \(String(format: "%.1f", correctedDistance * 100)) cm")
        return correctedDistance
    }
    
    /// Retorna um fator de correção específico para o dispositivo atual
    /// - Returns: Fator de correção baseado no modelo do dispositivo
    private func getDeviceCorrectionFactor() -> Float {
        let deviceName = UIDevice.current.modelName
        
        // Fatores de correção baseados em calibração empírica
        let correctionFactors: [String: Float] = [
            // iPhone 14 Series
            "iPhone14,2": 1.05, // iPhone 13 Pro
            "iPhone14,3": 1.05, // iPhone 13 Pro Max
            "iPhone15,2": 1.06, // iPhone 14 Pro
            "iPhone15,3": 1.06, // iPhone 14 Pro Max
            
            // iPhone 13 Series
            "iPhone14,4": 1.04, // iPhone 13 mini
            "iPhone14,5": 1.04, // iPhone 13
            
            // iPhone 12 Series
            "iPhone13,2": 1.03, // iPhone 12
            "iPhone13,1": 1.03, // iPhone 12 mini
            "iPhone13,3": 1.03, // iPhone 12 Pro
            "iPhone13,4": 1.03, // iPhone 12 Pro Max
            
            // iPhone 11 Series
            "iPhone12,1": 1.04, // iPhone 11
            "iPhone12,3": 1.04, // iPhone 11 Pro
            "iPhone12,5": 1.04, // iPhone 11 Pro Max
            
            // iPhone X Series
            "iPhone10,3": 1.02, // iPhone X
            "iPhone10,6": 1.02, // iPhone X
            "iPhone11,2": 1.03, // iPhone XS
            "iPhone11,4": 1.03, // iPhone XS Max
            "iPhone11,6": 1.03, // iPhone XS Max
            "iPhone11,8": 1.02  // iPhone XR
        ]
        
        // Retorna o fator de correção específico ou o padrão (1.0)
        return correctionFactors[deviceName] ?? 1.0
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
        
        // Define pontos para amostragem (centro e arredores)
        let samplePoints = createSamplePoints(for: depthData.depthMap)
        
        // Coleta valores de profundidade válidos
        let validDepths = samplePoints.compactMap { point -> Float? in
            guard let depth = getDepthValue(from: depthData.depthMap, at: point) else {
                return nil
            }
            return (depth > 0 && depth < DistanceConstants.maxValidDepth) ? depth : nil
        }
        
        // Verifica se temos amostras suficientes
        guard !validDepths.isEmpty else {
            print("⚠️ Nenhuma medição de profundidade válida encontrada")
            return 0
        }
        
        // Calcula a mediana para reduzir a influência de outliers
        let medianDepth = calculateMedian(validDepths)
        print("📏 LiDAR: \(String(format: "%.1f", medianDepth * 100)) cm (média de \(validDepths.count) pontos)")
        
        return medianDepth
    }
    
    /// Cria pontos de amostra para medição de profundidade
    private func createSamplePoints(for depthMap: CVPixelBuffer) -> [CGPoint] {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        // Define pontos em um padrão de grade para melhor cobertura
        let gridSize = 3
        let stepX = width / gridSize
        let stepY = height / gridSize
        
        var points: [CGPoint] = []
        
        for i in 0..<gridSize {
            for j in 0..<gridSize {
                let x = stepX / 2 + i * stepX
                let y = stepY / 2 + j * stepY
                points.append(CGPoint(x: x, y: y))
            }
        }
        
        return points
    }
    
    /// Calcula a mediana de um array de valores Float
    private func calculateMedian(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let count = sorted.count
        
        if count == 0 {
            return 0
        } else if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        } else {
            return sorted[count / 2]
        }
    }
    
    // MARK: - Métodos Auxiliares
    
    /// Obtém o valor de profundidade de um ponto específico no mapa de profundidade
    /// - Parameters:
    ///   - depthMap: Buffer contendo os dados de profundidade
    ///   - point: Ponto (em coordenadas de pixel) para obter a profundidade
    /// - Returns: Valor de profundidade em metros ou nil se fora dos limites
    private func getDepthValue(from depthMap: CVPixelBuffer, at point: CGPoint) -> Float? {
        // Valida as coordenadas do ponto
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        // Verifica se o ponto está dentro dos limites válidos
        guard point.x >= 0, point.x < CGFloat(width),
              point.y >= 0, point.y < CGFloat(height) else {
            return nil
        }
        
        // Bloqueia o buffer para acesso seguro
        guard CVPixelBufferLockBaseAddress(depthMap, .readOnly) == kCVReturnSuccess else {
            print("⚠️ Falha ao bloquear o buffer de profundidade")
            return nil
        }
        
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        // Obtém informações do buffer
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            print("⚠️ Falha ao obter o endereço base do buffer")
            return nil
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let bytesPerPixel = MemoryLayout<Float>.size
        
        // Calcula o offset para o ponto de interesse
        let pixelOffset = Int(point.y) * bytesPerRow + Int(point.x) * bytesPerPixel
        
        // Verifica se o offset é válido
        guard pixelOffset + bytesPerPixel <= CVPixelBufferGetDataSize(depthMap) else {
            print("⚠️ Offset de profundidade fora dos limites do buffer")
            return nil
        }
        
        // Obtém o valor de profundidade (32-bit float)
        let depthValue = baseAddress.load(fromByteOffset: pixelOffset, as: Float.self)
        
        // Valida o valor de profundidade
        guard depthValue.isFinite else {
            print("⚠️ Valor de profundidade inválido: \(depthValue)")
            return nil
        }
        
        return depthValue
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

// MARK: - Extensão para Identificar o Modelo do Dispositivo
extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        // Mapeamento dos identificadores para nomes comuns de dispositivos
        switch identifier {
        // iPhone 15
        case "iPhone16,1":                  return "iPhone 15 Pro"
        case "iPhone16,2":                  return "iPhone 15 Pro Max"
        case "iPhone15,4":                  return "iPhone 15"
        case "iPhone15,5":                  return "iPhone 15 Plus"
            
        // iPhone 14
        case "iPhone15,2":                  return "iPhone 14 Pro"
        case "iPhone15,3":                  return "iPhone 14 Pro Max"
        case "iPhone14,7":                  return "iPhone 14"
        case "iPhone14,8":                  return "iPhone 14 Plus"
            
        // iPhone 13
        case "iPhone14,2":                  return "iPhone 13 Pro"
        case "iPhone14,3":                  return "iPhone 13 Pro Max"
        case "iPhone14,4":                  return "iPhone 13 mini"
        case "iPhone14,5":                  return "iPhone 13"
            
        // iPhone 12
        case "iPhone13,1":                  return "iPhone 12 mini"
        case "iPhone13,2":                  return "iPhone 12"
        case "iPhone13,3":                  return "iPhone 12 Pro"
        case "iPhone13,4":                  return "iPhone 12 Pro Max"
            
        // iPhone 11 - IMPORTANTE para verificação de TrueDepth!
        case "iPhone12,1":                  return "iPhone 11"
        case "iPhone12,3":                  return "iPhone 11 Pro"
        case "iPhone12,5":                  return "iPhone 11 Pro Max"
            
        // iPhone XS/XR
        case "iPhone11,2":                  return "iPhone XS"
        case "iPhone11,4", "iPhone11,6":    return "iPhone XS Max"
        case "iPhone11,8":                  return "iPhone XR"
            
        // iPhone X - Primeiro com TrueDepth
        case "iPhone10,3", "iPhone10,6":    return "iPhone X"
            
        // Se não encontrar correspondência, retorna o identificador original
        default:                            return identifier
        }
    }
}
