//
//  HeadAlignmentVerification.swift
//  MedidorOticaApp
//
//  Verificacao 4: mede a pose atual da cabeca nos 3 eixos.
//

import ARKit
import Vision
import simd

// MARK: - Verificacao 4
extension VerificationManager {
    private enum HeadAlignmentConstants {
        /// Tolerancia escolhida para manter a etapa estavel sem perder precisao.
        static let toleranceDegrees: Float = 3.0
    }

    /// Mede a pose atual da cabeca e informa se a etapa 4 esta liberada.
    func evaluateHeadAlignment(using frame: ARFrame,
                               faceAnchor: ARFaceAnchor?) -> (headPoseAvailable: Bool, isAligned: Bool) {
        let sensors = preferredSensors(requireFaceAnchor: true,
                                       faceAnchorAvailable: faceAnchor != nil)

        guard !sensors.isEmpty else {
            reportUnavailableHeadPose(reason: "Nenhum sensor conseguiu medir a pose da cabeca.")
            return (false, false)
        }

        for sensor in sensors {
            let snapshot: HeadPoseSnapshot?

            switch sensor {
            case .trueDepth:
                guard let faceAnchor else { continue }
                snapshot = makeTrueDepthHeadPoseSnapshot(faceAnchor: faceAnchor,
                                                         frame: frame)
            case .liDAR:
                snapshot = makeLiDARHeadPoseSnapshot(from: frame)
            case .none:
                snapshot = nil
            }

            guard let snapshot else { continue }
            let isAligned = snapshot.isAligned(tolerance: HeadAlignmentConstants.toleranceDegrees)
            publishHeadPose(snapshot, isHeadAligned: isAligned)
            return (true, isAligned)
        }

        reportUnavailableHeadPose(reason: "A pose da cabeca nao ficou disponivel neste frame.")
        return (false, false)
    }

    /// Calcula a pose diretamente do ARFaceAnchor relativo a camera.
    private func makeTrueDepthHeadPoseSnapshot(faceAnchor: ARFaceAnchor,
                                               frame: ARFrame) -> HeadPoseSnapshot? {
        let euler = extractRelativeEulerAngles(faceAnchor: faceAnchor, frame: frame)
        let sign: Float = CameraManager.shared.cameraPosition == .front ? -1 : 1
        let snapshot = HeadPoseSnapshot(rollDegrees: radiansToDegrees(euler.roll) * sign,
                                        yawDegrees: radiansToDegrees(euler.yaw) * sign,
                                        pitchDegrees: radiansToDegrees(euler.pitch),
                                        timestamp: frame.timestamp,
                                        sensor: .trueDepth)

        return snapshot.isValid ? snapshot : nil
    }

    /// Calcula a pose com Vision para o caminho do LiDAR.
    private func makeLiDARHeadPoseSnapshot(from frame: ARFrame) -> HeadPoseSnapshot? {
        guard let angles = headAnglesWithVision(from: frame) else { return nil }
        let snapshot = HeadPoseSnapshot(rollDegrees: angles.roll,
                                        yawDegrees: angles.yaw,
                                        pitchDegrees: angles.pitch,
                                        timestamp: frame.timestamp,
                                        sensor: .liDAR)

        return snapshot.isValid ? snapshot : nil
    }

    /// Publica a pose atual para a UI e para o gate de captura.
    private func publishHeadPose(_ snapshot: HeadPoseSnapshot,
                                 isHeadAligned: Bool) {
        DispatchQueue.main.async {
            self.headPoseSnapshot = snapshot
            self.alignmentData = [
                "roll": snapshot.rollDegrees,
                "yaw": snapshot.yawDegrees,
                "pitch": snapshot.pitchDegrees
            ]

            print("Alinhamento da cabeca: Roll=\(snapshot.rollDegrees)°, Yaw=\(snapshot.yawDegrees)°, Pitch=\(snapshot.pitchDegrees)°, Alinhado=\(isHeadAligned)")
        }
    }

    /// Apenas registra a indisponibilidade do frame atual.
    /// A limpeza efetiva fica centralizada no `VerificationManager.apply(evaluation:)`
    /// para evitar apagar a ultima pose valida antes da UI decidir se pode reutiliza-la.
    private func reportUnavailableHeadPose(reason: String) {
        print("Pose da cabeca indisponivel: \(reason)")
    }

    // MARK: - Angulos de Euler
    private struct EulerAngles {
        let pitch: Float
        let yaw: Float
        let roll: Float
    }

    /// Extrai angulos de Euler a partir da matriz 4x4.
    private func extractEulerAngles(from transform: simd_float4x4) -> EulerAngles {
        let quaternion = simd_quatf(transform)
        let qw = quaternion.real
        let qx = quaternion.imag.x
        let qy = quaternion.imag.y
        let qz = quaternion.imag.z

        let pitch = atan2(2 * (qw * qx + qy * qz),
                          1 - 2 * (qx * qx + qy * qy))
        let yaw = asin(max(-1, min(1, 2 * (qw * qy - qz * qx))))
        let roll = atan2(2 * (qw * qz + qx * qy),
                         1 - 2 * (qy * qy + qz * qz))

        return EulerAngles(pitch: pitch, yaw: yaw, roll: roll)
    }

    /// Mede a pose do rosto no referencial da camera atual.
    private func extractRelativeEulerAngles(faceAnchor: ARFaceAnchor,
                                            frame: ARFrame) -> EulerAngles {
        let worldToCamera = simd_inverse(frame.camera.transform)
        let relativeTransform = simd_mul(worldToCamera, faceAnchor.transform)
        return extractEulerAngles(from: relativeTransform)
    }

    /// Converte um angulo de radianos para graus.
    private func radiansToDegrees(_ radians: Float) -> Float {
        radians * (180.0 / .pi)
    }

    // MARK: - Vision
    /// Le a pose da cabeca com Vision para a camera LiDAR.
    private func headAnglesWithVision(from frame: ARFrame) -> (roll: Float, yaw: Float, pitch: Float)? {
        let request = makeLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage,
                                            orientation: currentCGOrientation(),
                                            options: [:])

        do {
            try handler.perform([request])
            guard let face = request.results?.first as? VNFaceObservation else { return nil }

            let roll = radiansToDegrees(Float(face.roll?.doubleValue ?? 0))
            let yaw = radiansToDegrees(Float(face.yaw?.doubleValue ?? 0))
            let pitch = radiansToDegrees(Float(face.pitch?.doubleValue ?? 0))

            let rollRad = roll * .pi / 180
            let yawRad = yaw * .pi / 180
            let pitchRad = pitch * .pi / 180
            let faceQuaternion = simd_quaternion(pitchRad, SIMD3<Float>(1, 0, 0)) *
                simd_quaternion(yawRad, SIMD3<Float>(0, 1, 0)) *
                simd_quaternion(rollRad, SIMD3<Float>(0, 0, 1))
            let adjusted = simd_mul(orientationCompensation(), faceQuaternion)
            let euler = extractEulerAngles(from: simd_float4x4(adjusted))

            return (radiansToDegrees(euler.roll),
                    radiansToDegrees(euler.yaw),
                    radiansToDegrees(euler.pitch))
        } catch {
            print("Erro ao calcular angulos com Vision: \(error)")
            return nil
        }
    }

    /// Compensa a orientacao da tela no caminho do Vision.
    private func orientationCompensation() -> simd_quatf {
        switch currentCGOrientation() {
        case .left, .leftMirrored:
            return simd_quaternion(-Float.pi / 2, SIMD3<Float>(0, 0, 1))
        case .right, .rightMirrored:
            return simd_quaternion(Float.pi / 2, SIMD3<Float>(0, 0, 1))
        case .down, .downMirrored:
            return simd_quaternion(Float.pi, SIMD3<Float>(0, 0, 1))
        default:
            return simd_quaternion(0, SIMD3<Float>(0, 0, 1))
        }
    }
}

// MARK: - Helpers da pose
private extension HeadPoseSnapshot {
    /// Indica se a pose esta alinhada dentro da tolerancia configurada.
    func isAligned(tolerance: Float) -> Bool {
        abs(rollDegrees) <= tolerance &&
        abs(yawDegrees) <= tolerance &&
        abs(pitchDegrees) <= tolerance
    }
}
