//
//  CenteringVerification.swift
//  MedidorOticaApp
//
//  Verificação de Centralização do Rosto
//
//  Objetivo:
//  - Garantir que o rosto esteja perfeitamente centralizado na câmera
//  - Manter o alinhamento preciso entre os olhos e o nariz
//  - Fornecer feedback visual sobre o posicionamento
//
//  Critérios de Aceitação:
//  1. Centralização horizontal (eixo X) com margem de ±0.5cm
//  2. Centralização vertical (eixo Y) com margem de ±0.5cm
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

import ARKit
import Vision
import UIKit

// MARK: - Extensões

extension Notification.Name {
    /// Notificação enviada quando o status de centralização do rosto é atualizado
    static let faceCenteringUpdated = Notification.Name("faceCenteringUpdated")
}

// MARK: - Extensão para verificação de centralização
extension VerificationManager {
    
    // MARK: - Constantes
    
    private enum CenteringConstants {
        // Tolerância de 0.5cm convertida para metros
        static let tolerance: Float = 0.005
        
        // Índices dos vértices na malha facial do ARKit
        struct FaceIndices {
            static let leftEye = 1220   // Centro aproximado do olho esquerdo
            static let rightEye = 1940  // Centro aproximado do olho direito
            static let noseTip = 9130   // Ponta do nariz
        }
    }
    
    // MARK: - Verificação de Centralização
    
    /// Verifica se o rosto está corretamente centralizado na câmera
    /// - Parameters:
    ///   - frame: O frame AR atual (não utilizado, mantido para compatibilidade)
    ///   - faceAnchor: O anchor do rosto detectado pelo ARKit
    /// - Returns: Booleano indicando se o rosto está perfeitamente centralizado
    func checkFaceCentering(using frame: ARFrame, faceAnchor: ARFaceAnchor) -> Bool {
        // Obtém a geometria 3D do rosto do ARKit
        let vertices = faceAnchor.geometry.vertices
        
        // Valida se temos vértices suficientes para análise
        guard vertices.count > CenteringConstants.FaceIndices.noseTip else {
            print("❌ Geometria facial incompleta para análise de centralização")
            return false
        }
        
        // Extrai as posições dos pontos faciais relevantes
        let leftEyePos = vertices[CenteringConstants.FaceIndices.leftEye]
        let rightEyePos = vertices[CenteringConstants.FaceIndices.rightEye]
        let nosePos = vertices[CenteringConstants.FaceIndices.noseTip]
        
        // Calcula o ponto médio entre os olhos (deve estar alinhado com o centro da câmera)
        let midEyeX = (leftEyePos.x + rightEyePos.x) / 2
        let midEyeY = (leftEyePos.y + rightEyePos.y) / 2
        
        // Calcula os desvios em relação ao centro (origem no espaço da câmera)
        let horizontalOffset = midEyeX
        let verticalOffset = midEyeY
        let noseOffset = nosePos.x
        
        // Verifica se os desvios estão dentro da tolerância permitida
        let isHorizontallyAligned = abs(horizontalOffset) < CenteringConstants.tolerance
        let isVerticallyAligned = abs(verticalOffset) < CenteringConstants.tolerance
        let isNoseAligned = abs(noseOffset) < CenteringConstants.tolerance
        
        // O rosto está centralizado se todos os critérios forem atendidos
        let isCentered = isHorizontallyAligned && isVerticallyAligned && isNoseAligned
        
        // Atualiza a interface do usuário com os resultados
        updateCenteringUI(
            horizontalOffset: horizontalOffset,
            verticalOffset: verticalOffset,
            noseOffset: noseOffset,
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
            
            // Atualiza as propriedades de estado
            self.faceAligned = isCentered
            self.faceCentered = isCentered
            
            // Armazena os desvios para feedback visual
            self.facePosition = [
                "x": horizontalCm,
                "y": verticalCm,
                "z": noseCm
            ]
            
            // Notifica a interface sobre a atualização
            self.notifyCenteringUpdate()
        }
    }
    
    /// Notifica a interface sobre a atualização do status de centralização
    private func notifyCenteringUpdate() {
        NotificationCenter.default.post(
            name: .faceCenteringUpdated,
            object: nil,
            userInfo: [
                "isCentered": faceAligned,
                "offsets": facePosition ?? [:],
                "timestamp": Date().timeIntervalSince1970
            ]
        )
    }
}
