//
//  FaceDetectionVerification.swift
//  MedidorOticaApp
//
//  Verificação 1: Detecção de rosto usando ARKit nativo
//  Suporta TrueDepth (câmera frontal) e LiDAR (câmera traseira)
//

import ARKit
import Vision

// Extensão para verificação de detecção de rosto
extension VerificationManager {
    
    // MARK: - Verificação 1: Detecção de Rosto
    /// Verifica a presença de rosto usando o sensor disponível e atualiza o estado
    func checkFaceDetection(using frame: ARFrame) -> Bool {
        let detected: Bool
        if hasTrueDepth {
            detected = checkFaceDetectionWithTrueDepth(frame: frame)
        } else if hasLiDAR {
            detected = checkFaceDetectionWithLiDAR(frame: frame)
        } else {
            print("ERRO: Sensores de detecção de rosto indisponíveis")
            NotificationCenter.default.post(
                name: NSNotification.Name("DeviceNotCompatible"),
                object: nil,
                userInfo: ["reason": "Sensores TrueDepth ou LiDAR não encontrados"]
            )
            return false
        }

        return detected
    }
    
    // MARK: - Detecção com TrueDepth (Câmera Frontal)
    private func checkFaceDetectionWithTrueDepth(frame: ARFrame) -> Bool {
        // Busca a primeira âncora de rosto e verifica se está sendo rastreada
        if let faceAnchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first {
            let tracked = faceAnchor.isTracked
            print(tracked ? "Rosto detectado usando TrueDepth" : "Rosto não rastreado com TrueDepth")
            return tracked
        }

        print("Nenhum rosto detectado com TrueDepth")
        return false
    }
    
    // MARK: - Detecção com LiDAR (Câmera Traseira)
    @available(iOS 13.4, *)
    private func checkFaceDetectionWithLiDAR(frame: ARFrame) -> Bool {
        // Acessa dados de profundidade do LiDAR
        guard let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth else {
            print("ERRO: Dados de profundidade do LiDAR não disponíveis")
            return false
        }
        
        // Obtém o depth map para análise
        let depthMap = depthData.depthMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        // Configura a detecção de rosto usando Vision
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: frame.capturedImage,
            orientation: currentCGOrientation(),
            options: [:])
        
        do {
            try handler.perform([request])

            // Verifica se detectou rostos
            if let results = request.results, !results.isEmpty {
                for faceObservation in results {
                    // Converte as coordenadas normalizadas para coordenadas de pixel
                    let boundingBox = faceObservation.boundingBox
                    let centerX = boundingBox.midX * CGFloat(width)
                    let centerY = (1 - boundingBox.midY) * CGFloat(height) // Inverte Y para coordenadas da imagem
                    
                    // Obtém valores de profundidade para vários pontos do rosto
                    var depthValues: [Float] = []
                    
                    // Amostra 5 pontos no rosto para maior precisão
                    let samplePoints = [
                        CGPoint(x: centerX, y: centerY), // Centro
                        CGPoint(x: centerX - boundingBox.width * 0.25, y: centerY), // Esquerda
                        CGPoint(x: centerX + boundingBox.width * 0.25, y: centerY), // Direita
                        CGPoint(x: centerX, y: centerY - boundingBox.height * 0.25), // Cima
                        CGPoint(x: centerX, y: centerY + boundingBox.height * 0.25)  // Baixo
                    ]
                    
                    // Coleta profundidades para os pontos de amostra
                    for point in samplePoints {
                        if let depth = depthValue(from: depthMap, at: point) {
                            depthValues.append(depth)
                        }
                    }
                    
                    // Se temos pelo menos 3 valores válidos de profundidade
                    if depthValues.count >= 3 {
                        // Calcula a média das profundidades
                        let avgDepth = depthValues.reduce(0, +) / Float(depthValues.count)
                        
                        // Verifica se a profundidade está em um intervalo válido para um rosto
                        // Típicamente, rostos estão entre 0.3m e 1.5m da câmera
                        if avgDepth > 0.3 && avgDepth < 1.5 {
                            print("Rosto detectado usando LiDAR a \(String(format: "%.2f", avgDepth))m")
                            return true
                        }
                    }
                }
            }
            
            print("Nenhum rosto detectado com LiDAR")
            return false
            
        } catch {
            print("ERRO na detecção de rosto com LiDAR: \(error)")
            return false
        }
    }
    
}
