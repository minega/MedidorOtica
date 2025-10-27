//
//  HeadAlignmentVerification.swift
//  MedidorOticaApp
//
//  Verificação 4: Alinhamento da cabeça
//  Usando ARKit para medições precisas com margem de erro de ±3 graus
//

import ARKit
import Vision
import simd

// Extensão para verificação de alinhamento da cabeça
extension VerificationManager {
    // MARK: - Verificação 4: Alinhamento da Cabeça
    /// Verifica se a cabeça está alinhada em todos os eixos
    
    func checkHeadAlignment(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> Bool {
        // Verificação de alinhamento com tolerância de ±3 graus
        // conforme especificação do projeto

        // Define a margem de erro exatamente como ±3 graus
        let alignmentToleranceDegrees: Float = 3.0

        var rollDegrees: Float?
        var yawDegrees: Float?
        var pitchDegrees: Float?

        let sensors = preferredSensors(requireFaceAnchor: true, faceAnchorAvailable: faceAnchor != nil)

        guard !sensors.isEmpty else { return false }

        for sensor in sensors {
            switch sensor {
            case .trueDepth:
                guard let anchor = faceAnchor else { continue }
                // Calcula os ângulos relativos à câmera sem aplicar compensações extras.
                let euler = extractRelativeEulerAngles(faceAnchor: anchor, frame: frame)
                let sign: Float = CameraManager.shared.cameraPosition == .front ? -1 : 1
                rollDegrees  = radiansToDegrees(euler.roll) * sign
                yawDegrees   = radiansToDegrees(euler.yaw) * sign
                pitchDegrees = radiansToDegrees(euler.pitch)
                break
            case .liDAR:
                guard let angles = headAnglesWithVision(from: frame) else { continue }
                rollDegrees = angles.roll
                yawDegrees = angles.yaw
                pitchDegrees = angles.pitch
                break
            case .none:
                continue
            }
        }

        guard
            let rollDegrees,
            let yawDegrees,
            let pitchDegrees
        else {
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
        let m11 = transform.columns.0.x
        let m12 = transform.columns.1.x
        let m13 = transform.columns.2.x
        let m21 = transform.columns.0.y
        let m22 = transform.columns.1.y
        let m23 = transform.columns.2.y
        let m31 = transform.columns.0.z
        let m32 = transform.columns.1.z
        let m33 = transform.columns.2.z

        let sy = sqrt(m11 * m11 + m21 * m21)
        let singular = sy < 1e-6

        let pitch: Float
        let yaw: Float
        let roll: Float

        if !singular {
            pitch = atan2(m32, m33)
            yaw = atan2(-m31, sy)
            roll = atan2(m21, m11)
        } else {
            pitch = atan2(-m23, m22)
            yaw = atan2(-m31, sy)
            roll = 0
        }

        return EulerAngles(pitch: pitch, yaw: yaw, roll: roll)
    }

    /// Extrai os ângulos de Euler relativos à câmera para compensar inclinações do dispositivo
    /// - Parameters:
    ///   - faceAnchor: Anchor do rosto com dados de rotação absoluta
    ///   - frame: Frame atual contendo a orientação da câmera
    /// - Returns: Ângulos de Euler alinhados ao referencial da câmera
    private func extractRelativeEulerAngles(faceAnchor: ARFaceAnchor, frame: ARFrame) -> EulerAngles {
        let worldToCamera = simd_inverse(frame.camera.transform)
        let relativeTransform = simd_mul(worldToCamera, faceAnchor.transform)
        // O transform relativo já está no referencial da câmera, evitando offsets de 90°.
        return extractEulerAngles(from: relativeTransform)
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

            // Mantém a convenção de sinais igual à do TrueDepth para feedback coerente.
            let sign: Float = CameraManager.shared.cameraPosition == .front ? -1 : 1
            return (roll * sign, yaw * sign, pitch)
        } catch {
            print("Erro ao calcular ângulos com Vision: \(error)")
            return nil
        }
    }
}
