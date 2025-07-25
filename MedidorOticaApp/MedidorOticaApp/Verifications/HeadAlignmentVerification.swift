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
            // Converte a matriz de transformação em ângulos de Euler
            let euler = extractEulerAngles(from: anchor.transform)
            let sign: Float = CameraManager.shared.cameraPosition == .front ? -1 : 1

            rollDegrees  = radiansToDegrees(euler.roll) * sign
            yawDegrees   = radiansToDegrees(euler.yaw) * sign
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

    // MARK: - Compensação de orientação
    /// Retorna um quaternion que ajusta o referencial conforme a orientação atual
    private func orientationCompensation() -> simd_quatf {
        switch currentCGOrientation() {
        case .left, .leftMirrored:
            return simd_quaternion(Float.pi / 2, SIMD3<Float>(0, 0, 1))
        case .right, .rightMirrored:
            return simd_quaternion(-Float.pi / 2, SIMD3<Float>(0, 0, 1))
        case .down, .downMirrored:
            return simd_quaternion(Float.pi, SIMD3<Float>(0, 0, 1))
        default:
            return simd_quaternion(0, SIMD3<Float>(0, 0, 1))
        }
    }
    
    // Converte ângulo de radianos para graus
    private func radiansToDegrees(_ radians: Float) -> Float {
        radians * (180.0 / .pi)
    }

    // Obtém ângulos de rotação da cabeça usando Vision (para LiDAR)
    private func headAnglesWithVision(from frame: ARFrame) -> (roll: Float, yaw: Float, pitch: Float)? {
        let request = makeLandmarksRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: frame.capturedImage,
            orientation: currentCGOrientation(),
            options: [:]
        )
        do {
            try handler.perform([request])
            guard let face = request.results?.first as? VNFaceObservation else { return nil }
            let roll = radiansToDegrees(Float(face.roll?.doubleValue ?? 0))
            let yaw = radiansToDegrees(Float(face.yaw?.doubleValue ?? 0))
            let pitch = radiansToDegrees(Float(face.pitch?.doubleValue ?? 0))

            // Ajusta para a orientação atual da tela
            let rollRad = roll * .pi / 180
            let yawRad = yaw * .pi / 180
            let pitchRad = pitch * .pi / 180
            let faceQuat = simd_quaternion(pitchRad, SIMD3<Float>(1,0,0)) *
                           simd_quaternion(yawRad,   SIMD3<Float>(0,1,0)) *
                           simd_quaternion(rollRad,  SIMD3<Float>(0,0,1))
            let adjusted = simd_mul(orientationCompensation(), faceQuat)
            let euler = extractEulerAngles(from: simd_float4x4(adjusted))

            return (radiansToDegrees(euler.roll),
                    radiansToDegrees(euler.yaw),
                    radiansToDegrees(euler.pitch))
        } catch {
            print("Erro ao calcular ângulos com Vision: \(error)")
            return nil
        }
    }
}
