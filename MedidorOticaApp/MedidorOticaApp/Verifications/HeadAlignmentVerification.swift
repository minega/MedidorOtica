//
//  HeadAlignmentVerification.swift
//  MedidorOticaApp
//
//  Verificação 4: Alinhamento da cabeça
//  Usando ARKit para medições precisas com checagens extras de simetria e profundidade
//

import ARKit
import Vision
import simd

// Extensão para verificação de alinhamento da cabeça
extension VerificationManager {
    private enum HeadAlignmentConstants {
        /// Tolerância angular mais rígida para reduzir capturas tortas.
        static let toleranceDegrees: Float = 2.0
        /// Diferença máxima permitida entre a profundidade dos olhos.
        static let maxEyeDepthDeltaMM: Float = 8.0
        /// Inclinação máxima permitida da linha interpupilar.
        static let maxEyeLineTiltDegrees: Float = 1.5
        /// Faixa anatômica esperada entre a profundidade média dos olhos e o nariz.
        static let noseDepthLeadRangeMM: ClosedRange<Float> = 4.0...35.0

        struct FaceIndices {
            static let noseTip = 9
        }
    }

    /// Métricas consolidadas de alinhamento da cabeça.
    private struct HeadAlignmentMetrics: Sendable {
        let rollDegrees: Float
        let yawDegrees: Float
        let pitchDegrees: Float
        let eyeDepthDeltaMM: Float?
        let eyeLineTiltDegrees: Float?
        let noseDepthLeadMM: Float?
    }

    // MARK: - Verificação 4: Alinhamento da Cabeça
    /// Verifica se a cabeça está alinhada em todos os eixos
    
    func checkHeadAlignment(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> Bool {
        var metrics: HeadAlignmentMetrics?

        let sensors = preferredSensors(requireFaceAnchor: true, faceAnchorAvailable: faceAnchor != nil)

        guard !sensors.isEmpty else { return false }

        for sensor in sensors {
            switch sensor {
            case .trueDepth:
                guard let anchor = faceAnchor else { continue }
                metrics = makeTrueDepthHeadAlignmentMetrics(faceAnchor: anchor, frame: frame)
                break
            case .liDAR:
                guard let angles = headAnglesWithVision(from: frame) else { continue }
                metrics = HeadAlignmentMetrics(rollDegrees: angles.roll,
                                               yawDegrees: angles.yaw,
                                               pitchDegrees: angles.pitch,
                                               eyeDepthDeltaMM: nil,
                                               eyeLineTiltDegrees: nil,
                                               noseDepthLeadMM: nil)
                break
            case .none:
                continue
            }
        }

        guard let metrics else { return false }
        let isHeadAligned = headIsAligned(using: metrics)
        publishAlignmentMetrics(metrics, isHeadAligned: isHeadAligned)
        return isHeadAligned
    }

    /// Calcula métricas de alinhamento usando a geometria 3D do TrueDepth.
    private func makeTrueDepthHeadAlignmentMetrics(faceAnchor: ARFaceAnchor,
                                                   frame: ARFrame) -> HeadAlignmentMetrics? {
        let euler = extractRelativeEulerAngles(faceAnchor: faceAnchor, frame: frame)
        let sign: Float = CameraManager.shared.cameraPosition == .front ? -1 : 1
        let rollDegrees = radiansToDegrees(euler.roll) * sign
        let yawDegrees = radiansToDegrees(euler.yaw) * sign
        let pitchDegrees = radiansToDegrees(euler.pitch)

        let worldToCamera = simd_inverse(frame.camera.transform)
        let faceInCamera = simd_mul(worldToCamera, faceAnchor.transform)
        let leftEyeTransform = simd_mul(faceInCamera, faceAnchor.leftEyeTransform)
        let rightEyeTransform = simd_mul(faceInCamera, faceAnchor.rightEyeTransform)
        let leftEyePosition = translation(from: leftEyeTransform)
        let rightEyePosition = translation(from: rightEyeTransform)
        let eyeDepthDeltaMM = (abs(leftEyePosition.z) - abs(rightEyePosition.z)) * 1000

        let eyeVector = rightEyePosition - leftEyePosition
        let eyeLineTiltDegrees = radiansToDegrees(atan2(eyeVector.y,
                                                        max(abs(eyeVector.x), Float.ulpOfOne)))

        let noseDepthLeadMM = noseDepthLead(faceAnchor: faceAnchor,
                                            faceInCamera: faceInCamera,
                                            leftEyePosition: leftEyePosition,
                                            rightEyePosition: rightEyePosition)

        return HeadAlignmentMetrics(rollDegrees: rollDegrees,
                                    yawDegrees: yawDegrees,
                                    pitchDegrees: pitchDegrees,
                                    eyeDepthDeltaMM: eyeDepthDeltaMM,
                                    eyeLineTiltDegrees: eyeLineTiltDegrees,
                                    noseDepthLeadMM: noseDepthLeadMM)
    }

    /// Calcula o avanço do nariz em relação ao plano médio dos olhos.
    private func noseDepthLead(faceAnchor: ARFaceAnchor,
                               faceInCamera: simd_float4x4,
                               leftEyePosition: SIMD3<Float>,
                               rightEyePosition: SIMD3<Float>) -> Float? {
        let vertices = faceAnchor.geometry.vertices
        guard vertices.count > HeadAlignmentConstants.FaceIndices.noseTip else {
            return nil
        }

        let noseVector = simd_mul(faceInCamera,
                                  simd_float4(vertices[HeadAlignmentConstants.FaceIndices.noseTip], 1))
        guard let nosePosition = positionFromHomogeneous(noseVector) else {
            return nil
        }

        let averageEyeDepth = (abs(leftEyePosition.z) + abs(rightEyePosition.z)) * 0.5
        return (averageEyeDepth - abs(nosePosition.z)) * 1000
    }

    /// Avalia se as métricas atuais já estão boas o bastante para a captura.
    private func headIsAligned(using metrics: HeadAlignmentMetrics) -> Bool {
        let isRollAligned = abs(metrics.rollDegrees) <= HeadAlignmentConstants.toleranceDegrees
        let isYawAligned = abs(metrics.yawDegrees) <= HeadAlignmentConstants.toleranceDegrees
        let isPitchAligned = abs(metrics.pitchDegrees) <= HeadAlignmentConstants.toleranceDegrees
        let isEyeDepthBalanced = metrics.eyeDepthDeltaMM.map {
            abs($0) <= HeadAlignmentConstants.maxEyeDepthDeltaMM
        } ?? true
        let isEyeLineLevel = metrics.eyeLineTiltDegrees.map {
            abs($0) <= HeadAlignmentConstants.maxEyeLineTiltDegrees
        } ?? true
        let hasExpectedNoseDepth = metrics.noseDepthLeadMM.map {
            HeadAlignmentConstants.noseDepthLeadRangeMM.contains($0)
        } ?? true

        return isRollAligned &&
               isYawAligned &&
               isPitchAligned &&
               isEyeDepthBalanced &&
               isEyeLineLevel &&
               hasExpectedNoseDepth
    }

    /// Publica as métricas usadas pela UI e pelo overlay de depuração.
    private func publishAlignmentMetrics(_ metrics: HeadAlignmentMetrics,
                                         isHeadAligned: Bool) {
        DispatchQueue.main.async {
            var debugData: [String: Float] = [
                "roll": metrics.rollDegrees,
                "yaw": metrics.yawDegrees,
                "pitch": metrics.pitchDegrees
            ]
            if let eyeDepthDeltaMM = metrics.eyeDepthDeltaMM {
                debugData["eyeDepthDeltaMM"] = eyeDepthDeltaMM
            }
            if let eyeLineTiltDegrees = metrics.eyeLineTiltDegrees {
                debugData["eyeLineTiltDegrees"] = eyeLineTiltDegrees
            }
            if let noseDepthLeadMM = metrics.noseDepthLeadMM {
                debugData["noseDepthLeadMM"] = noseDepthLeadMM
            }
            self.alignmentData = debugData

            print("Alinhamento da cabeça: Roll=\(metrics.rollDegrees)°, Yaw=\(metrics.yawDegrees)°, Pitch=\(metrics.pitchDegrees)°, DeltaOlhos=\(String(format: "%.1f", metrics.eyeDepthDeltaMM ?? 0))mm, LinhaOlhos=\(String(format: "%.1f", metrics.eyeLineTiltDegrees ?? 0))°, Nariz=\(String(format: "%.1f", metrics.noseDepthLeadMM ?? 0))mm, Alinhado=\(isHeadAligned)")
        }
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

    /// Extrai os ângulos de Euler relativos à câmera para compensar inclinações do dispositivo
    /// - Parameters:
    ///   - faceAnchor: Anchor do rosto com dados de rotação absoluta
    ///   - frame: Frame atual contendo a orientação da câmera
    /// - Returns: Ângulos de Euler alinhados ao referencial da câmera
    private func extractRelativeEulerAngles(faceAnchor: ARFaceAnchor, frame: ARFrame) -> EulerAngles {
        let worldToCamera = simd_inverse(frame.camera.transform)
        let relativeTransform = simd_mul(worldToCamera, faceAnchor.transform)
        let orientationMatrix = simd_float4x4(orientationCompensation())
        let compensatedTransform = simd_mul(orientationMatrix, relativeTransform)
        return extractEulerAngles(from: compensatedTransform)
    }

    // MARK: - Compensação de orientação
    /// Retorna um quaternion que ajusta o referencial conforme a orientação atual
    private func orientationCompensation() -> simd_quatf {
        switch currentCGOrientation() {
        case .left, .leftMirrored:
            // Compensa imagens que chegam giradas 90° para a esquerda rotacionando no sentido horário
            return simd_quaternion(-Float.pi / 2, SIMD3<Float>(0, 0, 1))
        case .right, .rightMirrored:
            // Compensa imagens que chegam giradas 90° para a direita rotacionando no sentido anti-horário
            return simd_quaternion(Float.pi / 2, SIMD3<Float>(0, 0, 1))
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

// MARK: - Helpers geométricos
private extension VerificationManager {
    /// Extrai o ponto 3D a partir de um vetor homogêneo.
    func positionFromHomogeneous(_ vector: simd_float4) -> SIMD3<Float>? {
        guard vector.w.isFinite, abs(vector.w) > Float.ulpOfOne else { return nil }
        return SIMD3<Float>(vector.x / vector.w,
                            vector.y / vector.w,
                            vector.z / vector.w)
    }

    /// Extrai apenas a translação de uma matriz 4x4.
    func translation(from transform: simd_float4x4) -> SIMD3<Float> {
        let translation = transform.columns.3
        return SIMD3<Float>(translation.x, translation.y, translation.z)
    }
}
