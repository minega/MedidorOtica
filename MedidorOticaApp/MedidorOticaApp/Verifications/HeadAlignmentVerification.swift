//
//  HeadAlignmentVerification.swift
//  MedidorOticaApp
//
//  Verificação 4: Alinhamento da cabeça
//  Usando ARKit para medições precisas com margem de erro de ±5 graus
//

import ARKit
import Vision
import simd

// Extensão para verificação de alinhamento da cabeça
extension VerificationManager {
    // MARK: - Verificação 4: Alinhamento da Cabeça
    /// Verifica se a cabeça está alinhada em todos os eixos
    
    func checkHeadAlignment(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> Bool {
        // Verificação de alinhamento com tolerância de ±5 graus
        // conforme solicitado pelo usuário

        // Define a margem de erro exatamente como ±5 graus
        let alignmentToleranceDegrees: Float = 5.0

        let rollDegrees: Float
        let yawDegrees: Float
        let pitchDegrees: Float

        if hasTrueDepth, let anchor = faceAnchor {
            // Quaternions do rosto e da câmera
            let faceQuat = simd_quatf(anchor.transform)
            let camQuat  = simd_quatf(frame.camera.transform)

            // Rotação relativa rosto -> câmera
            let relativeQuat = simd_normalize(camQuat.inverse * faceQuat)
            let relative = simd_float4x4(relativeQuat)
            let euler = extractEulerAngles(from: relative)

            rollDegrees  = radiansToDegrees(euler.roll)
            yawDegrees   = radiansToDegrees(euler.yaw)
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
        
        // Utiliza quaternions para evitar problemas de gimbal lock
        let quat = simd_quatf(transform)

        let qw = quat.real
        let qx = quat.imag.x
        let qy = quat.imag.y
        let qz = quat.imag.z

        // Fórmulas padrão de conversão quaternion -> ângulos de Euler
        let pitch = atan2(2 * (qw * qx + qy * qz), 1 - 2 * (qx * qx + qy * qy))
        let yaw   = asin(max(-1, min(1, 2 * (qw * qy - qz * qx))))
        let roll  = atan2(2 * (qw * qz + qx * qy), 1 - 2 * (qy * qy + qz * qz))

        return EulerAngles(pitch: pitch, yaw: yaw, roll: roll)
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
