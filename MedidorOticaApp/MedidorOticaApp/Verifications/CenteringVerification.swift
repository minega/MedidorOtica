//
//  CenteringVerification.swift
//  MedidorOticaApp
//
//  Verifica se o rosto está centralizado na câmera com ARKit ou Vision,
//  aceitando desvio de ±0.5cm.

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

    /// Verificação de centralização usando Vision e LiDAR (câmera traseira)
    func checkFaceCentering(using frame: ARFrame, observation: VNFaceObservation) -> Bool {
        guard #available(iOS 13.4, *),
              let depth = depthFromLiDAR(frame, at: observation.boundingBox.midPoint) else {
            return false
        }

        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        let cx = intrinsics.columns.2.x
        let cy = intrinsics.columns.2.y

        let width = Float(CVPixelBufferGetWidth(frame.capturedImage))
        let height = Float(CVPixelBufferGetHeight(frame.capturedImage))

        let px = Float(observation.boundingBox.midX) * width
        let py = Float(1 - observation.boundingBox.midY) * height

        let horizontalOffset = ((px - cx) / fx) * depth
        let verticalOffset = ((py - cy) / fy) * depth

        let isHorizontallyAligned = abs(horizontalOffset) < CenteringConstants.tolerance
        let isVerticallyAligned = abs(verticalOffset) < CenteringConstants.tolerance

        let isCentered = isHorizontallyAligned && isVerticallyAligned

        updateCenteringUI(
            horizontalOffset: horizontalOffset,
            verticalOffset: verticalOffset,
            noseOffset: horizontalOffset,
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
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.faceAligned = isCentered
            self.faceCentered = isCentered
            self.facePosition = [
                "x": horizontalCm,
                "y": verticalCm,
                "z": noseCm
            ]
            NotificationCenter.default.post(
                name: .faceCenteringUpdated,
                object: nil,
                userInfo: [
                    "isCentered": isCentered,
                    "offsets": self.facePosition ?? [:]
                ]
            )
        }
    }

    @available(iOS 13.4, *)
    private func depthFromLiDAR(_ frame: ARFrame, at point: CGPoint) -> Float? {
        guard let depthMap = frame.sceneDepth?.depthMap else { return nil }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let x = Int(point.x * CGFloat(width))
        let y = Int((1 - point.y) * CGFloat(height))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let base = CVPixelBufferGetBaseAddress(depthMap)!
        let offset = y * bytesPerRow + x * MemoryLayout<Float>.size
        let value = base.load(fromByteOffset: offset, as: Float.self)
        return value.isFinite ? value : nil
    }
}
