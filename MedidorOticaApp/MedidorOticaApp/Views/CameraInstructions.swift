//
//  CameraInstructions.swift
//  MedidorOticaApp
//
//  Textos curtos e objetivos para orientar a captura em tempo real.
//

import SwiftUI

// MARK: - Construtor da instrucao da cabeca
enum HeadPoseInstructionBuilder {
    static let rollToleranceDegrees = CapturePrecisionPolicy.rollToleranceDegrees
    static let yawToleranceDegrees = CapturePrecisionPolicy.yawToleranceDegrees
    static let pitchToleranceDegrees = CapturePrecisionPolicy.pitchToleranceDegrees

    /// Escolhe um unico eixo por vez, seguindo a ordem pitch, yaw e roll.
    static func adjustment(from snapshot: HeadPoseSnapshot) -> HeadAxisAdjustment? {
        let tolerances = tolerances(for: snapshot.sensor)

        if abs(snapshot.pitchDegrees) > tolerances.pitch {
            let correction = displayedDegrees(from: snapshot.pitchDegrees,
                                              tolerance: tolerances.pitch)
            return snapshot.pitchDegrees > 0 ? .pitchUp(correction) : .pitchDown(correction)
        }

        if abs(snapshot.yawDegrees) > tolerances.yaw {
            let correction = displayedDegrees(from: snapshot.yawDegrees,
                                              tolerance: tolerances.yaw)
            return snapshot.yawDegrees > 0 ? .yawRight(correction) : .yawLeft(correction)
        }

        if abs(snapshot.rollDegrees) > tolerances.roll {
            let correction = displayedDegrees(from: snapshot.rollDegrees,
                                              tolerance: tolerances.roll)
            return snapshot.rollDegrees > 0 ? .rollLeft(correction) : .rollRight(correction)
        }

        return nil
    }

    /// Retorna tolerancias coerentes com o sensor que gerou a pose.
    private static func tolerances(for sensor: VerificationManager.SensorType) -> (roll: Float, yaw: Float, pitch: Float) {
        switch sensor {
        case .liDAR:
            return (RearLiDARCapturePrecisionPolicy.rollToleranceDegrees,
                    RearLiDARCapturePrecisionPolicy.yawToleranceDegrees,
                    RearLiDARCapturePrecisionPolicy.pitchToleranceDegrees)
        default:
            return (rollToleranceDegrees,
                    yawToleranceDegrees,
                    pitchToleranceDegrees)
        }
    }

    /// Mostra apenas o quanto falta corrigir apos a tolerancia.
    private static func displayedDegrees(from angle: Float,
                                         tolerance: Float) -> Float {
        max(round(abs(angle) - tolerance), 1)
    }
}

// MARK: - Ajuste de eixo
enum HeadAxisAdjustment: Equatable, Sendable {
    case rollLeft(Float)
    case rollRight(Float)
    case yawLeft(Float)
    case yawRight(Float)
    case pitchUp(Float)
    case pitchDown(Float)

    /// Texto curto e objetivo para corrigir um eixo por vez.
    var instruction: String {
        switch self {
        case .rollLeft(let degrees):
            return "🙂 ↩️ Incline a cabeca \(Self.degreesText(degrees))° para a esquerda"
        case .rollRight(let degrees):
            return "🙂 ↪️ Incline a cabeca \(Self.degreesText(degrees))° para a direita"
        case .yawLeft(let degrees):
            return "🙂 ⬅️ Gire a cabeca \(Self.degreesText(degrees))° para a esquerda"
        case .yawRight(let degrees):
            return "🙂 ➡️ Gire a cabeca \(Self.degreesText(degrees))° para a direita"
        case .pitchUp(let degrees):
            return "🙂 ⬆️ Gire a cabeca \(Self.degreesText(degrees))° para cima"
        case .pitchDown(let degrees):
            return "🙂 ⬇️ Gire a cabeca \(Self.degreesText(degrees))° para baixo"
        }
    }

    private static func degreesText(_ value: Float) -> String {
        String(format: "%.0f", value)
    }
}

// MARK: - Instrucoes da camera
struct CameraInstructions: View {
    /// Observa as verificacoes do enquadramento.
    @ObservedObject var verificationManager: VerificationManager
    /// Observa o estado real do pipeline de captura.
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        instructionView(text: currentInstruction())
    }

    // MARK: - Texto principal
    private func currentInstruction() -> String {
        if shouldShowTrueDepthBootstrap {
            return trueDepthGuidance()
        }

        switch cameraManager.captureState {
        case .preparing:
            return "📱 ⏳ Aguarde a camera abrir e estabilizar"
        case .countdown:
            return "🙂 ✅ Mantenha a posicao. Captura automatica iniciando"
        case .capturing:
            return "📱 📸 Capturando a foto"
        case .captured:
            return "🙂 ✅ Foto concluida"
        case .error(let reason):
            return guidance(for: reason)
        case .checking(let reason):
            return guidance(for: reason)
        case .stableReady:
            if cameraManager.cameraPosition == .back {
                return "🙂 👀 Olhe para um ponto distante. Captura imediata"
            }
            return "🙂 ✅ Mantenha a posicao. Captura automatica imediata"
        case .idle:
            return fallbackGuidance()
        }
    }

    private var shouldShowTrueDepthBootstrap: Bool {
        cameraManager.isUsingARSession &&
        cameraManager.cameraPosition == .front &&
        !cameraManager.isTrueDepthSensorAlive
    }

    private func trueDepthGuidance() -> String {
        switch cameraManager.trueDepthState {
        case .startingSession:
            return "📱 ⏳ Aguarde a camera abrir e o TrueDepth iniciar"
        case .waitingForFaceAnchor:
            return "🙂 👀 Encaixe testa, olhos e queixo dentro do oval"
        case .waitingForEyeProjection:
            return "🙂 👀 Deixe os dois olhos totalmente visiveis no oval"
        case .waitingForDepthConsistency:
            return guidance(for: cameraManager.trueDepthFailureReason ?? .noRecentSamples)
        case .sensorAlive:
            return "🙂 ✅ Sensor pronto. Ajuste as verificacoes olhando para a tela"
        case .recovering:
            return "📱 🔄 Reiniciando o TrueDepth. Mantenha o rosto no oval"
        case .failed(let reason):
            return guidance(for: reason)
        }
    }

    private func fallbackGuidance() -> String {
        if !verificationManager.faceDetected {
            return "🙂 👀 Encaixe o rosto inteiro no oval olhando para a tela"
        }

        if !verificationManager.distanceCorrect {
            return distanceGuidance()
        }

        if !verificationManager.faceAligned {
            return centeringGuidance()
        }

        if !verificationManager.headAligned {
            return headAlignmentGuidance()
        }

        if cameraManager.cameraPosition == .back {
            return "🙂 👀 Olhe para um ponto distante. Segure parado"
        }

        return "🙂 ✅ Mantenha a posicao para a captura automatica"
    }

    private func guidance(for reason: CameraCaptureBlockReason) -> String {
        switch reason {
        case .preparingSession:
            return "📱 ⏳ Aguarde a camera abrir e estabilizar"
        case .sessionUnavailable:
            return "📱 🔄 A camera reiniciou. Segure o celular parado"
        case .trackingUnavailable:
            return "🙂 👀 Reenquadre o rosto inteiro dentro do oval"
        case .faceNotDetected:
            return "🙂 👀 Encaixe o rosto inteiro no oval olhando para a tela"
        case .distanceOutOfRange:
            return distanceGuidance()
        case .faceNotCentered:
            return centeringGuidance()
        case .headPoseUnavailable, .headNotAligned:
            return headAlignmentGuidance()
        case .calibrationUnavailable:
            return calibrationGuidance()
        case .unstableFrame:
            return "📱 ⏳ Segure o celular totalmente parado ate validar o frame"
        case .staleFrame:
            return "📱 ⏳ Aguarde a imagem atualizar antes da captura"
        }
    }

    private func guidance(for reason: TrueDepthBlockReason) -> String {
        switch reason {
        case .noFaceAnchor, .faceNotTracked:
            return "🙂 👀 Encaixe testa, olhos e queixo dentro do oval"
        case .invalidIntrinsics:
            return "📱 🔄 O sensor esta reiniciando. Mantenha o rosto no oval"
        case .invalidEyeDepth:
            return "🙂 👀 Deixe os dois olhos, sobrancelhas e cantos visiveis"
        case .ipdOutOfRange, .pixelBaselineTooSmall:
            return "🙂 ↔️ Aproxime o rosto ate os olhos ocuparem mais o oval"
        case .noRecentSamples:
            return "🙂 ↔️ Aproxime o rosto ate aparecer a malha facial"
        case .scaleOutOfRange, .baselineNoiseTooHigh:
            return "📱 ↔️ Aproxime o rosto ate o sensor confirmar a malha"
        }
    }

    private func calibrationGuidance() -> String {
        if cameraManager.cameraPosition == .back {
            return "📱 ↔️ Mantenha o rosto entre \(Int(RearLiDARDistanceLimits.minCm)) e \(Int(RearLiDARDistanceLimits.maxCm)) cm"
        }

        if let failure = cameraManager.trueDepthFailureReason {
            return guidance(for: failure)
        }

        return "📱 ↔️ Aproxime o rosto ate o sensor confirmar a malha"
    }

    // MARK: - Bloco visual
    private func instructionView(text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .environment(\.colorScheme, .light)
            .appGlassSurface(cornerRadius: 12,
                             borderOpacity: 0.14,
                             tintOpacity: 0.24,
                             tintColor: .black,
                             variant: .regular,
                             interactive: false,
                             fallbackMaterial: .thinMaterial)
            .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 4)
    }

    // MARK: - Distancia
    private func distanceGuidance() -> String {
        let minDistance = verificationManager.minDistance
        let maxDistance = verificationManager.maxDistance
        let currentDistance = verificationManager.lastMeasuredDistance

        if verificationManager.projectedFaceTooSmall {
            return "🙂 ↔️ Aproxime o rosto ate os olhos ocuparem melhor o oval"
        }

        if currentDistance <= 0 {
            return "🙂 ↔️ Posicione o rosto entre \(Int(minDistance)) e \(Int(maxDistance)) cm"
        }

        if currentDistance < minDistance {
            let diff = max(1, Int(round(minDistance - currentDistance)))
            return "🙂 ↔️ Afaste cerca de \(diff) cm para entrar na faixa ideal"
        }

        let diff = max(1, Int(round(currentDistance - maxDistance)))
        return "🙂 ↔️ Aproxime cerca de \(diff) cm para entrar na faixa ideal"
    }

    // MARK: - Centralizacao
    private func centeringGuidance() -> String {
        if verificationManager.activeSensor == .liDAR {
            return rearLiDARCenteringGuidance()
        }

        let rawX = verificationManager.facePosition["x"] ?? 0
        let rawY = verificationManager.facePosition["y"] ?? 0
        let (xPos, yPos) = verificationManager.adjustOffsets(horizontal: rawX, vertical: rawY)
        let horizontalOffset = abs(xPos)
        let verticalOffset = abs(yPos)
        let dominantOffset = max(abs(xPos), abs(yPos))

        if horizontalOffset <= CapturePrecisionPolicy.horizontalCenteringTolerance * 100 &&
            verticalOffset <= CapturePrecisionPolicy.verticalCenteringTolerance * 100 {
            return "📱 ⏳ Segure parado no PC para validar a captura"
        }

        if horizontalOffset >= verticalOffset {
            if xPos > 0 {
                return "📱 ➡️ Leve o celular \(format(max(horizontalOffset, 0.1))) cm para a direita ate a camera ficar no PC"
            }

            if xPos < 0 {
                return "📱 ⬅️ Leve o celular \(format(max(horizontalOffset, 0.1))) cm para a esquerda ate a camera ficar no PC"
            }
        } else {
            if yPos > 0 {
                return "📱 ⬆️ Levante o celular \(format(max(verticalOffset, 0.1))) cm ate a camera ficar na altura do PC"
            }

            if yPos < 0 {
                return "📱 ⬇️ Baixe o celular \(format(max(verticalOffset, 0.1))) cm ate a camera ficar na altura do PC"
            }
        }

        if dominantOffset > 0.05 {
            return "📱 ↔️ Faca um ajuste fino ate a camera ficar no PC"
        }

        return "📱 ⏳ Segure o celular reto sem girar"
    }

    /// Instrucao traseira baseada no deslocamento visual do PC no preview LiDAR.
    private func rearLiDARCenteringGuidance() -> String {
        let xPos = verificationManager.facePosition["x"] ?? 0
        let yPos = verificationManager.facePosition["y"] ?? 0
        let horizontalOffset = abs(xPos)
        let verticalOffset = abs(yPos)
        let horizontalTolerance = RearLiDARCapturePrecisionPolicy.horizontalCenteringTolerance * 100
        let verticalTolerance = RearLiDARCapturePrecisionPolicy.verticalCenteringTolerance * 100

        if horizontalOffset <= horizontalTolerance && verticalOffset <= verticalTolerance {
            return "📱 ⏳ Segure parado no centro do PC"
        }

        if horizontalOffset >= verticalOffset {
            if xPos > 0 {
                return "📱 ➡️ Leve o celular \(format(max(horizontalOffset, 0.1))) cm para a direita"
            }

            if xPos < 0 {
                return "📱 ⬅️ Leve o celular \(format(max(horizontalOffset, 0.1))) cm para a esquerda"
            }
        } else {
            if yPos > 0 {
                return "📱 ⬇️ Baixe o celular \(format(max(verticalOffset, 0.1))) cm"
            }

            if yPos < 0 {
                return "📱 ⬆️ Levante o celular \(format(max(verticalOffset, 0.1))) cm"
            }
        }

        return "📱 ↔️ Ajuste fino ate o PC ficar no centro"
    }

    // MARK: - Cabeca
    /// Toda instrucao da etapa 4 precisa apontar um eixo real.
    private func headAlignmentGuidance() -> String {
        guard let snapshot = verificationManager.headPoseSnapshot else {
            return "🙂 👀 Mostre testa, olhos e queixo para medir os eixos"
        }

        guard let adjustment = HeadPoseInstructionBuilder.adjustment(from: snapshot) else {
            return "🙂 ✅ Cabeca alinhada nos 3 eixos"
        }

        return adjustment.instruction
    }

    private func format(_ value: Float, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value)
    }
}

// MARK: - Menu de verificacoes
struct VerificationMenu: View {
    /// Gerenciador observado para refletir mudancas no menu em tempo real.
    @ObservedObject var verificationManager: VerificationManager

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            progressHeader()
            ForEach(verificationManager.verifications) { verification in
                HStack(spacing: 6) {
                    Text(verification.isChecked ? "OK" : menuTitle(for: verification.type))
                        .font(.caption)
                        .foregroundColor(.white)

                    Circle()
                        .foregroundColor(verification.isChecked ? .green : .red)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .environment(\.colorScheme, .light)
        .appGlassSurface(cornerRadius: 18,
                         borderOpacity: 0.16,
                         tintOpacity: 0.12,
                         tintColor: .white,
                         variant: .regular,
                         interactive: false,
                         fallbackMaterial: .thinMaterial)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 20)
        .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 10)
    }

    private func progressHeader() -> some View {
        let completedCount = verificationManager.verifications
            .filter { $0.isChecked && !$0.type.isOptional }
            .count
        let requiredCount = verificationManager.verifications
            .filter { !$0.type.isOptional }
            .count
        let progressWidth = requiredCount > 0 ? 50 * CGFloat(completedCount) / CGFloat(requiredCount) : 0

        return HStack {
            Text("\(completedCount)/\(requiredCount)")
                .font(.caption)
                .foregroundColor(.white)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .frame(width: 50, height: 8)
                    .foregroundColor(.gray.opacity(0.5))

                RoundedRectangle(cornerRadius: 4)
                    .frame(width: progressWidth, height: 8)
                    .foregroundColor(verificationManager.allVerificationsChecked ? .green : .orange)
            }
        }
    }

    private func menuTitle(for type: VerificationType) -> String {
        if type == .distance,
           verificationManager.activeSensor == .liDAR {
            return "\(Int(RearLiDARDistanceLimits.minCm))-\(Int(RearLiDARDistanceLimits.maxCm)) cm"
        }

        return type.menuTitle
    }
}
