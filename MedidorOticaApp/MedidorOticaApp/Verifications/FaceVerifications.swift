//
//  FaceVerifications.swift
//  MedidorOticaApp
//
//  Arquivo de constantes para verificações faciais usando ARKit
//

import Foundation
import ARKit
import Vision
import UIKit
import AVFoundation
import Combine

// MARK: - Constantes e Configurações
public struct VerificationConstants {
    // Distância ideal entre usuário e câmera (em metros)
    static let idealDistance: Float = 0.5
    static let minDistance: Float = 0.4
    static let maxDistance: Float = 0.6
    
    // Centralização do rosto
    static let centeringTolerance: Float = 0.005 // Equivalente a 0.5cm
    
    // Alinhamento da cabeça (em graus)
    static let alignmentTolerance: Float = 2.0 // Exatamente 2 graus
    
    // Verificação de olhar
    static let gazeTolerance: Float = 0.001 // Quase sem margem de erro
}

// MARK: - Módulos de Verificação
// Este aplicativo usa uma abordagem modular para as verificações:
//
// 1. FaceDetectionVerification.swift - Verificação 1: Detecção de rosto
// 2. DistanceVerification.swift - Verificação 2: Distância
// 3. CenteringVerification.swift - Verificação 3: Centralização
// 4. HeadAlignmentVerification.swift - Verificação 4: Alinhamento da cabeça
// 7. GazeVerification.swift - Verificação 7: Direção do olhar

// Extensão do VerificationManager para as verificações de rosto
extension VerificationManager {
    
    // MARK: - Verificação de Sensores Disponíveis
    // Esta função foi movida para a classe VerificationManager
    
    // MARK: - Verificação de Compatibilidade da Câmera
    func isDeviceCompatible(with cameraType: CameraType) -> Bool {
        let capabilities = checkDeviceCapabilities()
        
        switch cameraType {
        case .front: return capabilities.hasTrueDepth
        case .back: return capabilities.hasLiDAR
        }
    }
    
    // MARK: - Gerenciamento da Sessão AR
    private func setupARSessionInternal(for cameraType: CameraType) -> ARSession {
        let session = ARSession()
        
        // Verifica se o dispositivo suporta a configuração solicitada
        guard isDeviceCompatible(with: cameraType) else {
            let sensorName = cameraType == .front ? "TrueDepth" : "LiDAR"
            print("ERRO: Dispositivo não suporta o sensor \(sensorName)")
            
            // Notifica que o dispositivo não é compatível
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("DeviceNotCompatible"),
                    object: nil,
                    userInfo: ["sensor": sensorName]
                )
            }
            return session
        }
        
        // Configura a sessão
        let configuration: ARConfiguration
        if cameraType == .front {
            configuration = ARFaceTrackingConfiguration()
        } else {
            configuration = ARWorldTrackingConfiguration()
        }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        print("AR Session iniciada com sucesso para câmera \(cameraType)")
        
        return session
    }
    
    // Interface pública para setupARSession
    func setupARSession(for cameraType: CameraType) -> ARSession {
        return setupARSessionInternal(for: cameraType)
    }
    
    // MARK: - Processamento do Frame AR
    func processARFrame(_ frame: ARFrame, cameraType: CameraType = .front) {
        // Processamento original com ARFrame
        processFrameInternal(frame: frame, cameraType: cameraType)
    }
    
    // Sobrecarga do método para aceitar CVPixelBuffer
    func processARFrame(_ pixelBuffer: CVPixelBuffer, cameraType: CameraType = .front) {
        // Fallback para quando temos apenas CVPixelBuffer
        processFrameWithPixelBuffer(pixelBuffer, cameraType: cameraType)
    }
    
    // Método para processar frames quando apenas temos CVPixelBuffer disponível
    private func processFrameWithPixelBuffer(_ pixelBuffer: CVPixelBuffer, cameraType: CameraType) {
        // Executa as verificações em sequência
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Verificação 1: Detecção de rosto
            let faceDetected = self.checkFaceDetection(in: pixelBuffer)
            
            // Só continua com as demais verificações se um rosto for detectado
            if faceDetected {
                // Verificação 2: Distância
                let distanceOk = self.checkDistance(in: pixelBuffer)
                
                // Verificação 3: Centralização
                if distanceOk {
                    let centeredOk = self.checkCentering(in: pixelBuffer)
                    
                    // Verificação 4: Alinhamento da cabeça
                    if centeredOk {
                        let headAlignedOk = self.checkHeadAlignment(in: pixelBuffer)
                        
                        // Verificação 7: Direcionamento do olhar
                        if headAlignedOk {
                            let gazeOk = self.checkGaze(in: pixelBuffer)
                            print("Olhar direcionado para a câmera: \(gazeOk)")
                        }
                    }
                }
            }
            
            // Atualiza as verificações em tempo real
            DispatchQueue.main.async {
                self.updateAllVerifications()
            }
        }
    }
    
    // Método interno compartilhado para processamento
    private func processFrameInternal(frame: ARFrame, cameraType: CameraType) {
        // Executa as verificações em sequência
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Registra o tempo de início para monitorar a performance
            let startTime = CACurrentMediaTime()
            
            switch cameraType {
            case .front:
                // Processamento com câmera frontal (TrueDepth)
                self.processFrontCameraFrame(frame)
                
            case .back:
                // Processamento com câmera traseira (LiDAR)
                self.processBackCameraFrame(frame)
            }
            
            // Calcula tempo de processamento
            let elapsedTime = CACurrentMediaTime() - startTime
            print("Verificações completas em \(String(format: "%.2f", elapsedTime * 1000))ms")
        }
    }
    
    // MARK: - Processamento para Câmera Frontal (TrueDepth)
    private func processFrontCameraFrame(_ frame: ARFrame) {
        // VERIFICAÇÃO 1: Detecção de rosto
        let faceDetected = self.checkFaceDetection(using: frame)
        guard faceDetected else {
            resetVerificationStates(upTo: .faceDetection)
            return
        }
        
        // Procura por FaceAnchor no frame
        guard let faceAnchor = frame.anchors.first(where: { $0 is ARFaceAnchor }) as? ARFaceAnchor else {
            resetVerificationStates(upTo: .faceDetection)
            return
        }
        
        // VERIFICAÇÃO 2: Distância
        let distanceCorrect = self.checkDistance(using: frame, faceAnchor: faceAnchor)
        guard distanceCorrect else {
            resetVerificationStates(upTo: .distance)
            return
        }
        
        // VERIFICAÇÃO 3: Centralização
        let centeringCorrect = self.checkFaceCentering(using: frame, faceAnchor: faceAnchor)
        guard centeringCorrect else {
            resetVerificationStates(upTo: .centering)
            return
        }
        
        // VERIFICAÇÃO 4: Alinhamento da cabeça
        let headAligned = self.checkHeadAlignment(using: faceAnchor)
        guard headAligned else {
            resetVerificationStates(upTo: .headAlignment)
            return
        }
        
        // VERIFICAÇÃO 7: Direção do olhar
        let gazeCorrect = self.checkGaze(using: faceAnchor)
        
        // Atualiza o estado com o resultado final
        DispatchQueue.main.async {
            self.faceDetected = true
            self.distanceCorrect = true
            self.faceCentered = true
            self.headAligned = true
            self.gazeCorrect = gazeCorrect
            // allVerificationsChecked é uma propriedade calculada
            self.updateAllVerifications()
        }
    }
    
    // MARK: - Processamento para Câmera Traseira (LiDAR)
    private func processBackCameraFrame(_ frame: ARFrame) {
        // Implementação para câmera traseira com LiDAR
        // Nota: Esta implementação depende de funcionalidades específicas do LiDAR
        // e pode ser expandida conforme necessário
        
        // Por enquanto, notifica que a câmera traseira ainda não é totalmente suportada
        DispatchQueue.main.async {
            // Configura o estado como não verificado
            self.resetAllVerificationStates()
            
            // Notifica que está em desenvolvimento
            NotificationCenter.default.post(
                name: NSNotification.Name("BackCameraNotImplemented"),
                object: nil
            )
        }
    }
    
    // MARK: - Auxiliares para Gerenciamento de Estado
    
    // Define os estágios de verificação para controle de estado
    private enum VerificationStage: Int {
        case none = 0
        case faceDetection = 1
        case distance = 2
        case centering = 3
        case headAlignment = 4
        case gaze = 5
        case all = 6
    }
    
    // Reseta os estados até um determinado estágio
    private func resetVerificationStates(upTo stage: VerificationStage) {
        DispatchQueue.main.async {
            // Configura os estados com base no estágio atual
            self.faceDetected = stage.rawValue >= VerificationStage.faceDetection.rawValue
            self.distanceCorrect = stage.rawValue >= VerificationStage.distance.rawValue
            self.faceCentered = stage.rawValue >= VerificationStage.centering.rawValue
            self.headAligned = stage.rawValue >= VerificationStage.headAlignment.rawValue
            self.gazeCorrect = stage.rawValue >= VerificationStage.gaze.rawValue
            // allVerificationsChecked é uma propriedade calculada, não precisa ser atribuída
            
            // Notifica a mudança de estado
            self.updateAllVerifications()
        }
    }
    
    // Reseta todos os estados de verificação
    private func resetAllVerificationStates() {
        DispatchQueue.main.async {
            self.faceDetected = false
            self.distanceCorrect = false
            self.faceCentered = false
            self.headAligned = false
            self.gazeCorrect = false
            // allVerificationsChecked é uma propriedade calculada, não deve ser atribuída
            self.updateAllVerifications()
        }
    }
    
    // MARK: - Verificação 1: Detecção de Rosto
    func checkFaceDetection(in image: CVPixelBuffer) -> Bool {
        // Cria uma solicitação de detecção de rosto usando Vision
        let faceDetectionRequest = VNDetectFaceRectanglesRequest()
        
        // Configura o manipulador de solicitação
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
        
        // Resultado da detecção
        var faceDetected = false
        
        do {
            // Executa a solicitação de detecção de rosto
            try requestHandler.perform([faceDetectionRequest])
            
            // Verifica se algum rosto foi detectado
            if let results = faceDetectionRequest.results, !results.isEmpty {
                faceDetected = true
                
                // Atualiza o estado no VerificationManager
                DispatchQueue.main.async {
                    self.faceDetected = true
                    self.updateAllVerifications()
                }
            } else {
                // Nenhum rosto detectado
                DispatchQueue.main.async {
                    self.faceDetected = false
                    self.updateAllVerifications()
                }
            }
        } catch {
            print("Erro na detecção de rosto: \(error)")
            DispatchQueue.main.async {
                self.faceDetected = false
                self.updateAllVerifications()
            }
        }
        
        return faceDetected
    }
    
    
    // Função auxiliar para calcular o ponto médio a partir de uma lista de pontos
    private func averagePoint(from points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }
}
