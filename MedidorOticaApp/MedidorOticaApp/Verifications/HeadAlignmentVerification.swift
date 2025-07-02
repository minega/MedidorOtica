//
//  HeadAlignmentVerification.swift
//  MedidorOticaApp
//
//  Verifica se a cabeça está alinhada em até ±2° usando ARKit ou Vision.
//

import ARKit
import Vision
import UIKit

// Extensão para verificação de alinhamento da cabeça
extension VerificationManager {
    
    // MARK: - Verificação 4: Alinhamento da Cabeça
    func checkHeadAlignment(using faceAnchor: ARFaceAnchor) -> Bool {
        let alignmentToleranceDegrees: Float = 2.0
        // Extrai a orientação da cabeça e converte para ângulos de Euler
        let transform = faceAnchor.transform
        let eulerAngles = extractEulerAngles(from: transform)
        
        let rollDegrees = radiansToDegrees(eulerAngles.roll)
        let yawDegrees = radiansToDegrees(eulerAngles.yaw)
        let pitchDegrees = radiansToDegrees(eulerAngles.pitch)
        
        let isRollAligned = abs(rollDegrees) <= alignmentToleranceDegrees
        let isYawAligned = abs(yawDegrees) <= alignmentToleranceDegrees
        let isPitchAligned = abs(pitchDegrees) <= alignmentToleranceDegrees
        // A cabeça está alinhada se todos os ângulos estiverem dentro da tolerância
        let isHeadAligned = isRollAligned && isYawAligned && isPitchAligned
        
        DispatchQueue.main.async {
            self.headAligned = isHeadAligned
            
            // Armazena dados sobre o desalinhamento para feedback mais preciso
            self.alignmentData = [
                "roll": rollDegrees,
                "yaw": yawDegrees,
                "pitch": pitchDegrees
            ]
            
            self.updateAllVerifications()
        }
        
        return isHeadAligned
    }

    /// Verificação de alinhamento usando Vision quando o sensor TrueDepth não está disponível
    func checkHeadAlignment(using frame: ARFrame, observation: VNFaceObservation) -> Bool {
        let tolerance: Float = 2.0

        let rollDegrees = radiansToDegrees(observation.roll?.floatValue ?? 0)
        let yawDegrees = radiansToDegrees(observation.yaw?.floatValue ?? 0)
        let pitchDegrees: Float
        if #available(iOS 14.0, *), let pitch = observation.pitch?.floatValue {
            pitchDegrees = radiansToDegrees(pitch)
        } else {
            pitchDegrees = 0
        }

        let isRollAligned = abs(rollDegrees) <= tolerance
        let isYawAligned = abs(yawDegrees) <= tolerance
        let isPitchAligned = abs(pitchDegrees) <= tolerance

        let aligned = isRollAligned && isYawAligned && isPitchAligned

        DispatchQueue.main.async {
            self.headAligned = aligned
            self.alignmentData = [
                "roll": rollDegrees,
                "yaw": yawDegrees,
                "pitch": pitchDegrees
            ]
            self.updateAllVerifications()
        }

        return aligned
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
}
