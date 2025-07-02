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
import simd

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
        
        // Índice do vértice correspondente à ponta do nariz
        struct FaceIndices {
            static let noseTip = 9
        }
    }
    
    // MARK: - Verificação de Centralização
    
    /// Verifica se o rosto está corretamente centralizado na câmera
    /// - Parameters:
    ///   - frame: O frame AR atual (não utilizado, mantido para compatibilidade)
    ///   - faceAnchor: O anchor do rosto detectado pelo ARKit
    /// - Returns: Booleano indicando se o rosto está perfeitamente centralizado
    /// Confere se o rosto está centralizado
    func checkFaceCentering(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> Bool {
        if hasTrueDepth, let anchor = faceAnchor {
            return checkCenteringWithTrueDepth(faceAnchor: anchor)
        }
        if hasLiDAR {
            return checkCenteringWithLiDAR(frame: frame)
        }
        return false
    }

    private func checkCenteringWithTrueDepth(faceAnchor: ARFaceAnchor) -> Bool {
        // Obtém a geometria 3D do rosto
        let vertices = faceAnchor.geometry.vertices

        // Valida se temos vértices suficientes para análise
        guard vertices.count > CenteringConstants.FaceIndices.noseTip else {
            print("❌ Geometria facial incompleta para análise de centralização")
            return false
        }

        // Posições dos olhos fornecidas pelo ARKit
        let leftEyePos = simd_make_float3(faceAnchor.leftEyeTransform.columns.3)
        let rightEyePos = simd_make_float3(faceAnchor.rightEyeTransform.columns.3)

        // Posição da ponta do nariz obtida da malha facial
        let nosePos = vertices[CenteringConstants.FaceIndices.noseTip]

        // Calcula o ponto médio entre os olhos
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

    @available(iOS 13.0, *)
    private func checkCenteringWithLiDAR(frame: ARFrame) -> Bool {
        guard let depthMap = frame.sceneDepth?.depthMap ?? frame.smoothedSceneDepth?.depthMap else {
            print("❌ Dados de profundidade LiDAR não disponíveis")
            return false
        }

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right, options: [:])
        do {
            try handler.perform([request])
            guard let face = request.results?.first as? VNFaceObservation else { return false }

            let width = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            let nosePointNorm = face.landmarks?.nose?.normalizedPoints.first ?? CGPoint(x: face.boundingBox.midX, y: face.boundingBox.midY)
            let px = nosePointNorm.x * CGFloat(width)
            let py = (1 - nosePointNorm.y) * CGFloat(height)

            guard let depth = depthValue(from: depthMap, at: CGPoint(x: px, y: py)) else { return false }
            let horizontalOffset = Float(nosePointNorm.x - 0.5) * Float(depth)
            let verticalOffset = Float(0.5 - nosePointNorm.y) * Float(depth)

            let isHorizontallyAligned = abs(horizontalOffset) < CenteringConstants.tolerance
            let isVerticallyAligned = abs(verticalOffset) < CenteringConstants.tolerance
            let isCentered = isHorizontallyAligned && isVerticallyAligned

            updateCenteringUI(horizontalOffset: horizontalOffset,
                              verticalOffset: verticalOffset,
                              noseOffset: horizontalOffset,
                              isCentered: isCentered)

            return isCentered
        } catch {
            print("Erro ao verificar centralização com Vision: \(error)")
            return false
        }
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
