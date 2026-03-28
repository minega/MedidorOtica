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
import CoreGraphics

// Extensão para verificação de alinhamento da cabeça
extension VerificationManager {
    private enum HeadAlignmentConstants {
        /// Tolerância angular mais rígida para reduzir capturas tortas.
        static let toleranceDegrees: Float = 2.0
        /// Limite usado para ignorar leituras de pose claramente inconsistentes.
        static let maxPlausiblePoseDegrees: Float = 35.0
        /// Diferença máxima permitida entre a profundidade dos olhos.
        static let maxEyeDepthDeltaMM: Float = 8.0
        /// Inclinação máxima permitida da linha interpupilar.
        static let maxEyeLineTiltDegrees: Float = 2.5
        /// Distância mínima projetada entre os olhos para considerar a leitura válida.
        static let minProjectedEyeDeltaPoints: Float = 12.0
        /// Limite usado para descartar leituras absurdas causadas por projeção inconsistente.
        static let maxPlausibleEyeLineTiltDegrees: Float = 20.0
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

    /// Resultado estruturado do alinhamento da cabeca.
    struct HeadAlignmentOutcome: Sendable {
        let isAligned: Bool
        let diagnostic: HeadAlignmentDiagnostic
    }

    // MARK: - Verificação 4: Alinhamento da Cabeça
    /// Verifica se a cabeça está alinhada em todos os eixos
    
    func checkHeadAlignment(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> Bool {
        headAlignmentOutcome(using: frame, faceAnchor: faceAnchor).isAligned
    }

    /// Avalia o alinhamento da cabeca retornando diagnostico estruturado.
    func headAlignmentOutcome(using frame: ARFrame, faceAnchor: ARFaceAnchor?) -> HeadAlignmentOutcome {
        var diagnostic = unavailableAlignmentDiagnostic(reason: "Nenhuma metrica de alinhamento foi gerada para o sensor atual.")

        let sensors = preferredSensors(requireFaceAnchor: true, faceAnchorAvailable: faceAnchor != nil)

        guard !sensors.isEmpty else {
            publishAlignmentDiagnostic(diagnostic)
            return HeadAlignmentOutcome(isAligned: false, diagnostic: diagnostic)
        }

        for sensor in sensors {
            switch sensor {
            case .trueDepth:
                guard let anchor = faceAnchor else {
                    diagnostic = unavailableAlignmentDiagnostic(reason: "O ARFaceAnchor nao ficou disponivel neste frame.")
                    continue
                }
                diagnostic = makeTrueDepthHeadAlignmentDiagnostic(faceAnchor: anchor, frame: frame)
                publishAlignmentDiagnostic(diagnostic)
                return HeadAlignmentOutcome(isAligned: diagnostic.primaryFailure == nil,
                                            diagnostic: diagnostic)
            case .liDAR:
                guard let angles = headAnglesWithVision(from: frame) else {
                    diagnostic = unavailableAlignmentDiagnostic(reason: "O Vision nao conseguiu medir a pose do rosto neste frame.")
                    continue
                }
                diagnostic = makeHeadAlignmentDiagnostic(from: HeadAlignmentMetrics(rollDegrees: angles.roll,
                                                                                    yawDegrees: angles.yaw,
                                                                                    pitchDegrees: angles.pitch,
                                                                                    eyeDepthDeltaMM: nil,
                                                                                    eyeLineTiltDegrees: nil,
                                                                                    noseDepthLeadMM: nil))
                publishAlignmentDiagnostic(diagnostic)
                return HeadAlignmentOutcome(isAligned: diagnostic.primaryFailure == nil,
                                            diagnostic: diagnostic)
            case .none:
                continue
            }
        }

        publishAlignmentDiagnostic(diagnostic)
        return HeadAlignmentOutcome(isAligned: false, diagnostic: diagnostic)
    }

    /// Calcula métricas de alinhamento usando a geometria 3D do TrueDepth.
    private func makeTrueDepthHeadAlignmentMetrics(faceAnchor: ARFaceAnchor,
                                                   frame: ARFrame) -> HeadAlignmentMetrics? {
        let euler = extractRelativeEulerAngles(faceAnchor: faceAnchor, frame: frame)
        let sign: Float = CameraManager.shared.cameraPosition == .front ? -1 : 1
        let rollDegrees = radiansToDegrees(euler.roll) * sign
        let yawDegrees = radiansToDegrees(euler.yaw) * sign
        let pitchDegrees = radiansToDegrees(euler.pitch)

        guard poseAnglesArePlausible(rollDegrees: rollDegrees,
                                     yawDegrees: yawDegrees,
                                     pitchDegrees: pitchDegrees) else {
            return nil
        }

        let worldToCamera = simd_inverse(frame.camera.transform)
        let faceInCamera = simd_mul(worldToCamera, faceAnchor.transform)
        let leftEyeTransform = simd_mul(faceInCamera, faceAnchor.leftEyeTransform)
        let rightEyeTransform = simd_mul(faceInCamera, faceAnchor.rightEyeTransform)
        let leftEyePosition = translation(from: leftEyeTransform)
        let rightEyePosition = translation(from: rightEyeTransform)
        let eyeDepthDeltaMM = (abs(leftEyePosition.z) - abs(rightEyePosition.z)) * 1000

        let eyeLineTiltDegrees = projectedEyeLineTiltDegrees(faceAnchor: faceAnchor, frame: frame)

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

    /// Monta um diagnostico completo do alinhamento usando as subchecagens explicitas.
    private func makeTrueDepthHeadAlignmentDiagnostic(faceAnchor: ARFaceAnchor,
                                                      frame: ARFrame) -> HeadAlignmentDiagnostic {
        guard let metrics = makeTrueDepthHeadAlignmentMetrics(faceAnchor: faceAnchor, frame: frame) else {
            return invalidPoseDiagnostic()
        }

        return makeHeadAlignmentDiagnostic(from: metrics)
    }

    /// Mede o desnivel dos olhos no espaço do preview para validar se estão na mesma altura.
    private func projectedEyeLineTiltDegrees(faceAnchor: ARFaceAnchor,
                                             frame: ARFrame) -> Float? {
        let viewport = orientedHeadAlignmentViewportSize(for: frame.camera.imageResolution,
                                                         orientation: currentCGOrientation())
        let uiOrientation = currentUIOrientation()

        let leftEyeWorldTransform = simd_mul(faceAnchor.transform, faceAnchor.leftEyeTransform)
        let rightEyeWorldTransform = simd_mul(faceAnchor.transform, faceAnchor.rightEyeTransform)
        let leftEyeWorldPosition = translation(from: leftEyeWorldTransform)
        let rightEyeWorldPosition = translation(from: rightEyeWorldTransform)

        let projectedLeft = frame.camera.projectPoint(leftEyeWorldPosition,
                                                      orientation: uiOrientation,
                                                      viewportSize: viewport)
        let projectedRight = frame.camera.projectPoint(rightEyeWorldPosition,
                                                       orientation: uiOrientation,
                                                       viewportSize: viewport)

        guard projectedLeft.x.isFinite,
              projectedLeft.y.isFinite,
              projectedRight.x.isFinite,
              projectedRight.y.isFinite else {
            return nil
        }

        let deltaX = Float(projectedRight.x - projectedLeft.x)
        let deltaY = Float(projectedRight.y - projectedLeft.y)
        guard abs(deltaX) >= HeadAlignmentConstants.minProjectedEyeDeltaPoints else {
            return nil
        }

        let tiltDegrees = radiansToDegrees(atan2(deltaY,
                                                 max(abs(deltaX), Float.ulpOfOne)))
        guard abs(tiltDegrees) <= HeadAlignmentConstants.maxPlausibleEyeLineTiltDegrees else {
            return nil
        }

        return tiltDegrees
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

    /// Publica as métricas usadas pela UI e pelo overlay de depuração.
    private func publishAlignmentDiagnostic(_ diagnostic: HeadAlignmentDiagnostic) {
        DispatchQueue.main.async {
            var debugData: [String: Float] = [
                "roll": diagnostic.metricValue(for: "roll"),
                "yaw": diagnostic.metricValue(for: "yaw"),
                "pitch": diagnostic.metricValue(for: "pitch")
            ]
            if let eyeDepthDeltaMM = diagnostic.metricValueOptional(for: "eyeDepthSymmetry") {
                debugData["eyeDepthDeltaMM"] = eyeDepthDeltaMM
            }
            if let eyeLineTiltDegrees = diagnostic.metricValueOptional(for: "eyeLineLevel") {
                debugData["eyeLineTiltDegrees"] = eyeLineTiltDegrees
            }
            if let noseDepthLeadMM = diagnostic.metricValueOptional(for: "noseDepthLead") {
                debugData["noseDepthLeadMM"] = noseDepthLeadMM
            }
            self.alignmentData = debugData

            print("Alinhamento da cabeca -> bloqueio=\(diagnostic.primaryFailure?.title ?? "nenhum") detalhe=\(diagnostic.technicalReason)")
        }
    }

    /// Monta o diagnostico final respeitando a ordem estrita de prioridade.
    private func makeHeadAlignmentDiagnostic(from metrics: HeadAlignmentMetrics) -> HeadAlignmentDiagnostic {
        let diagnostics = [
            poseDiagnostic(id: "roll",
                           title: "Roll",
                           value: metrics.rollDegrees,
                           tolerance: HeadAlignmentConstants.toleranceDegrees,
                           positiveDirection: .counterclockwise,
                           negativeDirection: .clockwise),
            poseDiagnostic(id: "yaw",
                           title: "Yaw",
                           value: metrics.yawDegrees,
                           tolerance: HeadAlignmentConstants.toleranceDegrees,
                           positiveDirection: .right,
                           negativeDirection: .left),
            poseDiagnostic(id: "pitch",
                           title: "Pitch",
                           value: metrics.pitchDegrees,
                           tolerance: HeadAlignmentConstants.toleranceDegrees,
                           positiveDirection: .up,
                           negativeDirection: .down),
            eyeLineDiagnostic(from: metrics.eyeLineTiltDegrees),
            eyeDepthDiagnostic(from: metrics.eyeDepthDeltaMM),
            noseDepthDiagnostic(from: metrics.noseDepthLeadMM)
        ]

        let primaryFailure = diagnostics.first(where: { !$0.isPassing })
        return HeadAlignmentDiagnostic(metrics: diagnostics,
                                       primaryFailureKind: primaryFailure.flatMap(headAlignmentKind(from:)),
                                       primaryFailure: primaryFailure,
                                       blockingHint: blockingHint(for: primaryFailure),
                                       technicalReason: primaryFailure?.detail ?? "Alinhamento validado.",
                                       confidence: primaryFailure?.confidence ?? 1)
    }

    /// Cria um diagnostico quando a pose retornada pelo TrueDepth ficou incoerente.
    private func invalidPoseDiagnostic() -> HeadAlignmentDiagnostic {
        let metric = VerificationMetricDiagnostic(id: "invalidPose",
                                                  title: "Pose invalida",
                                                  currentValue: nil,
                                                  targetRange: nil,
                                                  unit: "",
                                                  direction: .center,
                                                  confidence: 0.2,
                                                  isPassing: false,
                                                  detail: "O TrueDepth gerou uma pose incoerente para este frame.")
        return HeadAlignmentDiagnostic(metrics: [metric],
                                       primaryFailureKind: .invalidPose,
                                       primaryFailure: metric,
                                       blockingHint: "🙂 ↔️ Reajustando alinhamento do rosto",
                                       technicalReason: metric.detail,
                                       confidence: metric.confidence)
    }

    /// Cria um diagnostico indisponivel quando o frame nao gerou dados suficientes.
    private func unavailableAlignmentDiagnostic(reason: String) -> HeadAlignmentDiagnostic {
        let metric = VerificationMetricDiagnostic(id: "invalidPose",
                                                  title: "Leitura indisponivel",
                                                  currentValue: nil,
                                                  targetRange: nil,
                                                  unit: "",
                                                  direction: .hold,
                                                  confidence: 0.1,
                                                  isPassing: false,
                                                  detail: reason)
        return HeadAlignmentDiagnostic(metrics: [metric],
                                       primaryFailureKind: .invalidPose,
                                       primaryFailure: metric,
                                       blockingHint: "🙂 ⏳ Reajustando alinhamento do rosto",
                                       technicalReason: reason,
                                       confidence: metric.confidence)
    }

    private func poseDiagnostic(id: String,
                                title: String,
                                value: Float,
                                tolerance: Float,
                                positiveDirection: VerificationDiagnosticDirection,
                                negativeDirection: VerificationDiagnosticDirection) -> VerificationMetricDiagnostic {
        let direction = value >= 0 ? positiveDirection : negativeDirection
        let isPassing = abs(value) <= tolerance
        let detail = "\(title) medido em \(String(format: "%.1f", value))°; alvo entre -\(String(format: "%.1f", tolerance))° e +\(String(format: "%.1f", tolerance))°."
        return VerificationMetricDiagnostic(id: id,
                                            title: title,
                                            currentValue: value,
                                            targetRange: (-tolerance)...tolerance,
                                            unit: "°",
                                            direction: direction,
                                            confidence: 0.98,
                                            isPassing: isPassing,
                                            detail: detail)
    }

    private func eyeLineDiagnostic(from value: Float?) -> VerificationMetricDiagnostic {
        guard let value else {
            return missingDiagnostic(id: "eyeLineLevel",
                                     title: "Olhos na horizontal",
                                     detail: "Nao foi possivel medir se os olhos ficaram na mesma altura no preview.")
        }

        let tolerance = HeadAlignmentConstants.maxEyeLineTiltDegrees
        return VerificationMetricDiagnostic(id: "eyeLineLevel",
                                            title: "Olhos na horizontal",
                                            currentValue: value,
                                            targetRange: (-tolerance)...tolerance,
                                            unit: "°",
                                            direction: value >= 0 ? .counterclockwise : .clockwise,
                                            confidence: 0.9,
                                            isPassing: abs(value) <= tolerance,
                                            detail: "Linha dos olhos em \(String(format: "%.1f", value))°; alvo entre -\(String(format: "%.1f", tolerance))° e +\(String(format: "%.1f", tolerance))°.")
    }

    private func eyeDepthDiagnostic(from value: Float?) -> VerificationMetricDiagnostic {
        guard let value else {
            return missingDiagnostic(id: "eyeDepthSymmetry",
                                     title: "Profundidade dos olhos",
                                     detail: "Nao foi possivel comparar a profundidade dos dois olhos neste frame.")
        }

        let tolerance = HeadAlignmentConstants.maxEyeDepthDeltaMM
        return VerificationMetricDiagnostic(id: "eyeDepthSymmetry",
                                            title: "Profundidade dos olhos",
                                            currentValue: value,
                                            targetRange: (-tolerance)...tolerance,
                                            unit: "mm",
                                            direction: .center,
                                            confidence: 0.88,
                                            isPassing: abs(value) <= tolerance,
                                            detail: "Diferenca de profundidade entre olhos em \(String(format: "%.1f", value)) mm; alvo entre -\(String(format: "%.1f", tolerance)) e +\(String(format: "%.1f", tolerance)) mm.")
    }

    private func noseDepthDiagnostic(from value: Float?) -> VerificationMetricDiagnostic {
        guard let value else {
            return missingDiagnostic(id: "noseDepthLead",
                                     title: "Profundidade do nariz",
                                     detail: "Nao foi possivel medir o avanco do nariz em relacao aos olhos.")
        }

        let range = HeadAlignmentConstants.noseDepthLeadRangeMM
        return VerificationMetricDiagnostic(id: "noseDepthLead",
                                            title: "Profundidade do nariz",
                                            currentValue: value,
                                            targetRange: range,
                                            unit: "mm",
                                            direction: .hold,
                                            confidence: 0.85,
                                            isPassing: range.contains(value),
                                            detail: "Avanco do nariz em \(String(format: "%.1f", value)) mm; alvo entre \(String(format: "%.1f", range.lowerBound)) e \(String(format: "%.1f", range.upperBound)) mm.")
    }

    private func missingDiagnostic(id: String,
                                   title: String,
                                   detail: String) -> VerificationMetricDiagnostic {
        VerificationMetricDiagnostic(id: id,
                                     title: title,
                                     currentValue: nil,
                                     targetRange: nil,
                                     unit: "",
                                     direction: .hold,
                                     confidence: 0.3,
                                     isPassing: false,
                                     detail: detail)
    }

    private func headAlignmentKind(from metric: VerificationMetricDiagnostic) -> HeadAlignmentCheckKind? {
        switch metric.id {
        case "roll":
            return .roll
        case "yaw":
            return .yaw
        case "pitch":
            return .pitch
        case "eyeLineLevel":
            return .eyeLineLevel
        case "eyeDepthSymmetry":
            return .eyeDepthSymmetry
        case "noseDepthLead":
            return .noseDepthLead
        case "invalidPose":
            return .invalidPose
        default:
            return nil
        }
    }

    private func blockingHint(for metric: VerificationMetricDiagnostic?) -> String {
        guard let metric else {
            return "🙂 ✅ Cabeca alinhada"
        }

        switch metric.id {
        case "roll":
            return metric.direction == .counterclockwise ?
                "🙂 ↩️ Incline levemente a cabeca para nivelar os olhos" :
                "🙂 ↪️ Incline levemente a cabeca para nivelar os olhos"
        case "yaw":
            return metric.direction == .right ?
                "🙂 ➡️ Vire levemente o rosto para a direita sem sair do oval" :
                "🙂 ⬅️ Vire levemente o rosto para a esquerda sem sair do oval"
        case "pitch":
            return metric.direction == .up ?
                "🙂 ⬆️ Levante levemente o queixo mantendo o nariz no centro" :
                "🙂 ⬇️ Abaixe levemente o queixo mantendo o nariz no centro"
        case "eyeLineLevel":
            return metric.direction == .counterclockwise ?
                "📱 ↩️ Gire levemente o celular para nivelar os dois olhos na horizontal" :
                "📱 ↪️ Gire levemente o celular para nivelar os dois olhos na horizontal"
        case "eyeDepthSymmetry":
            return "🙂 ↔️ Desvire o rosto ate os dois olhos ficarem na mesma distancia"
        case "noseDepthLead":
            return "📱 ↕️ Ajuste a altura do celular ate o nariz ficar entre os olhos"
        default:
            return "🙂 ⏳ Reajustando alinhamento do rosto"
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
        return extractEulerAngles(from: relativeTransform)
    }

    /// Valida a pose do TrueDepth antes de publicar instruções absurdas para o usuário.
    private func poseAnglesArePlausible(rollDegrees: Float,
                                        yawDegrees: Float,
                                        pitchDegrees: Float) -> Bool {
        abs(rollDegrees) <= HeadAlignmentConstants.maxPlausiblePoseDegrees &&
        abs(yawDegrees) <= HeadAlignmentConstants.maxPlausiblePoseDegrees &&
        abs(pitchDegrees) <= HeadAlignmentConstants.maxPlausiblePoseDegrees
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
    /// Ajusta o viewport conforme a orientação usada no preview.
    func orientedHeadAlignmentViewportSize(for resolution: CGSize,
                                           orientation: CGImagePropertyOrientation) -> CGSize {
        orientation.isPortrait ?
            CGSize(width: resolution.height, height: resolution.width) :
            resolution
    }

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

// MARK: - Helpers do diagnostico
private extension HeadAlignmentDiagnostic {
    /// Retorna o valor atual da metrica ou zero quando ausente.
    func metricValue(for id: String) -> Float {
        metricValueOptional(for: id) ?? 0
    }

    /// Retorna o valor atual da metrica quando disponivel.
    func metricValueOptional(for id: String) -> Float? {
        metrics.first(where: { $0.id == id })?.currentValue
    }
}
