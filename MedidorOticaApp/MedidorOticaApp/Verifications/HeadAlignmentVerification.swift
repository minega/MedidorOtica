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
                guard let anchor = faceAnchor,
                      let euler = normalizedEulerAngles(faceAnchor: anchor, frame: frame) else { continue }
                // Ajusta o sinal para manter coerência com a câmera frontal espelhada.
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

    /// Calcula ângulos de Euler normalizados considerando a orientação da interface.
    /// - Parameters:
    ///   - faceAnchor: Anchor do rosto obtido pelo TrueDepth.
    ///   - frame: Frame atual com dados de câmera e orientação.
    /// - Returns: Ângulos alinhados ao referencial da tela em modo retrato.
    private func normalizedEulerAngles(faceAnchor: ARFaceAnchor, frame: ARFrame) -> EulerAngles? {
        // Obtém a matriz view orientada para o modo retrato.
        let orientedWorldToCamera = frame.camera.viewMatrix(for: currentUIOrientation())

        // Converte para quaternions para isolar apenas a rotação.
        let cameraQuaternion = simd_quatf(orientedWorldToCamera)
        let faceQuaternion = simd_quatf(faceAnchor.transform)

        // Combina as rotações eliminando a orientação absoluta do dispositivo.
        let relativeQuaternion = simd_mul(cameraQuaternion, faceQuaternion)

        // Normaliza para garantir precisão numérica.
        let normalized = simd_normalize(relativeQuaternion)

        return eulerAngles(from: normalized)
    }

    /// Converte um quaternion em ângulos de Euler, respeitando a ordem yaw-pitch-roll.
    /// - Parameter quaternion: Rotação relativa já normalizada.
    /// - Returns: Estrutura com ângulos em radianos.
    private func eulerAngles(from quaternion: simd_quatf) -> EulerAngles {
        let q = quaternion

        // Extrai os componentes individuais para clareza.
        let x = q.imag.x
        let y = q.imag.y
        let z = q.imag.z
        let w = q.real

        // Calcula Roll (Z) utilizando atan2 para manter o sinal correto.
        let sinRCosP = 2 * (w * x + y * z)
        let cosRCosP = 1 - 2 * (x * x + y * y)
        let roll = atan2(sinRCosP, cosRCosP)

        // Calcula Pitch (X) com clamping para evitar valores fora do intervalo.
        let sinP = 2 * (w * y - z * x)
        let pitch: Float
        if abs(sinP) >= 1 {
            pitch = copysign(.pi / 2, sinP)
        } else {
            pitch = asin(sinP)
        }

        // Calcula Yaw (Y) garantindo continuidade.
        let sinYCosP = 2 * (w * z + x * y)
        let cosYCosP = 1 - 2 * (y * y + z * z)
        let yaw = atan2(sinYCosP, cosYCosP)

        return EulerAngles(pitch: pitch, yaw: yaw, roll: roll)
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
