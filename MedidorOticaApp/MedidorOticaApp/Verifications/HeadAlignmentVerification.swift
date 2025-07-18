//
//  HeadAlignmentVerification.swift
//  MedidorOticaApp
//
//  Verificação 4: Alinhamento da cabeça
//  Usando ARKit para medições precisas com margem de erro de ±2 graus
//

import ARKit
import Vision

// Extensão para verificação de alinhamento da cabeça
extension VerificationManager {
    // MARK: - Verificação 4: Alinhamento da Cabeça
    /// Verifica se a cabeça está alinhada em todos os eixos
    
    func checkHeadAlignment(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> Bool {
        // A verificação de alinhamento da cabeça com tolerância de exatamente ±2 graus
        // conforme solicitado pelo usuário

        // Define a margem de erro exatamente como ±2 graus
        let alignmentToleranceDegrees: Float = 2.0

        let rollDegrees: Float
        let yawDegrees: Float
        let pitchDegrees: Float

        if hasTrueDepth, let anchor = faceAnchor {
            // Converte a rotação do rosto para o sistema de coordenadas da câmera
            let worldToCamera = simd_inverse(frame.camera.transform)
            let headInCamera = simd_mul(worldToCamera, anchor.transform)
            let euler = extractEulerAngles(from: headInCamera)
            rollDegrees = radiansToDegrees(euler.roll)
            yawDegrees = radiansToDegrees(euler.yaw)
            pitchDegrees = radiansToDegrees(euler.pitch)
        } else if hasLiDAR, let angles = headAnglesWithVision(from: frame) {
            rollDegrees = angles.roll
            yawDegrees = angles.yaw
            pitchDegrees = angles.pitch
        } else {
            return false
        }
        
        // Verifica se todos os ângulos estão dentro da margem de tolerância
        let isRollAligned = abs(rollDegrees) <= alignmentToleranceDegrees
        let isYawAligned = abs(yawDegrees) <= alignmentToleranceDegrees
        let isPitchAligned = abs(pitchDegrees) <= alignmentToleranceDegrees

        // A cabeça está alinhada se todos os ângulos estiverem dentro da tolerância
        let isHeadAligned = isRollAligned && isYawAligned && isPitchAligned
        
        DispatchQueue.main.async {
            // Armazena dados sobre o desalinhamento para feedback mais preciso
            self.alignmentData = [
                "roll": rollDegrees,
                "yaw": yawDegrees,
                "pitch": pitchDegrees
            ]

            print("Alinhamento da cabeça: Roll=\(rollDegrees)°, Yaw=\(yawDegrees)°, Pitch=\(pitchDegrees)°, Alinhado=\(isHeadAligned)")
        }
        
        return isHeadAligned
    }
    
    // Estrutura para armazenar os ângulos de Euler
    private struct EulerAngles {
        var pitch: Float // Rotação em X (cabeça para cima/baixo)
        var yaw: Float   // Rotação em Y (cabeça para esquerda/direita)
        var roll: Float  // Rotação em Z (inclinação lateral da cabeça)
    }
    
    // Extrai os ângulos de Euler a partir da matriz de transformação 4x4
    private func extractEulerAngles(from transform: simd_float4x4) -> EulerAngles {
        // A matriz de transformação do ARFaceAnchor contém informações de rotação
        // Os elementos da matriz 3x3 superior podem ser convertidos para ângulos de Euler
        
        // Extrai a matriz de rotação 3x3 da transformação 4x4
        let rotationMatrix = simd_float3x3(
            simd_float3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            simd_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        )
        
        // Converte a matriz de rotação para ângulos de Euler
        var angles = EulerAngles(pitch: 0, yaw: 0, roll: 0)
        
        // Calcula pitch (rotação em X)
        angles.pitch = asin(-rotationMatrix[2, 0])
        
        // Calcula yaw (rotação em Y)
        if cos(angles.pitch) > 0.0001 {
            angles.yaw = atan2(rotationMatrix[2, 1], rotationMatrix[2, 2])
            angles.roll = atan2(rotationMatrix[1, 0], rotationMatrix[0, 0])
        } else {
            // Gimbal lock (quando pitch = ±90°)
            angles.yaw = 0
            angles.roll = atan2(-rotationMatrix[0, 1], rotationMatrix[1, 1])
        }
        
        return angles
    }
    
    // Converte ângulo de radianos para graus
    private func radiansToDegrees(_ radians: Float) -> Float {
        radians * (180.0 / .pi)
    }

    // Obtém ângulos de rotação da cabeça usando Vision (para LiDAR)
    @available(iOS 13.0, *)
    private func headAnglesWithVision(from frame: ARFrame) -> (roll: Float, yaw: Float, pitch: Float)? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage,
                                            orientation: currentCGOrientation(),
                                            options: [:])
        do {
            try handler.perform([request])
            guard let face = request.results?.first as? VNFaceObservation else { return nil }
            let roll = radiansToDegrees(Float(face.roll?.doubleValue ?? 0))
            let yaw = radiansToDegrees(Float(face.yaw?.doubleValue ?? 0))
            let pitch = radiansToDegrees(Float(face.pitch?.doubleValue ?? 0))
            return (roll, yaw, pitch)
        } catch {
            print("Erro ao calcular ângulos com Vision: \(error)")
            return nil
        }
    }
}
