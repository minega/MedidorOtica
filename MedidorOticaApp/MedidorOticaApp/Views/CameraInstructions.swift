//
//  CameraInstructions.swift
//  MedidorOticaApp
//
//  Textos de orientacao detalhada durante a captura.
//

import SwiftUI

// MARK: - Instrucoes da camera
struct CameraInstructions: View {
    private enum InstructionLimits {
        /// Evita instruções absurdas quando a pose chega corrompida.
        static let maxPlausiblePoseDegrees: Float = 35
    }

    private enum HeadAxisAdjustment {
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
                return "🙂 ↩️ Incline a cabeca cerca de \(Self.degreesText(degrees))° para a sua esquerda"
            case .rollRight(let degrees):
                return "🙂 ↪️ Incline a cabeca cerca de \(Self.degreesText(degrees))° para a sua direita"
            case .yawLeft(let degrees):
                return "🙂 ⬅️ Vire o rosto cerca de \(Self.degreesText(degrees))° para a sua esquerda"
            case .yawRight(let degrees):
                return "🙂 ➡️ Vire o rosto cerca de \(Self.degreesText(degrees))° para a sua direita"
            case .pitchUp(let degrees):
                return "🙂 ⬆️ Levante o queixo cerca de \(Self.degreesText(degrees))°"
            case .pitchDown(let degrees):
                return "🙂 ⬇️ Abaixe o queixo cerca de \(Self.degreesText(degrees))°"
            }
        }

        private static func degreesText(_ value: Float) -> String {
            String(format: "%.1f", value)
        }
    }

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
            return trueDepthInstruction()
        }

        switch cameraManager.captureState {
        case .preparing:
            return "📱 ⏳ Aguarde a camera abrir e estabilizar"
        case .countdown:
            return "🙂 👀 Agora olhe para a camera sem mover o celular"
        case .capturing:
            return "📱 📸 Capturando a foto"
        case .captured:
            return "🙂 ✅ Foto concluida"
        case .error(let reason):
            return instruction(for: reason)
        case .checking(let reason):
            return instruction(for: reason)
        case .stableReady:
            return "🙂 ✅ Continue olhando para a tela. Na contagem, olhe para a camera"
        case .idle:
            return fallbackInstruction()
        }
    }

    private var shouldShowTrueDepthBootstrap: Bool {
        cameraManager.isUsingARSession &&
        cameraManager.cameraPosition == .front &&
        !cameraManager.isTrueDepthSensorAlive
    }

    private func trueDepthInstruction() -> String {
        switch cameraManager.trueDepthState {
        case .startingSession:
            return "📱 ⏳ Aguarde a camera abrir e o TrueDepth iniciar"
        case .waitingForFaceAnchor:
            return "🙂 👀 Encaixe testa, olhos e queixo dentro do oval"
        case .waitingForEyeProjection:
            return "🙂 👀 Deixe os dois olhos totalmente visiveis no oval"
        case .waitingForDepthConsistency:
            return instruction(for: cameraManager.trueDepthFailureReason ?? .noRecentSamples)
        case .sensorAlive:
            return "🙂 ✅ Sensor pronto. Ajuste as verificacoes olhando para a tela"
        case .recovering:
            return "📱 🔄 Reiniciando o TrueDepth. Mantenha o rosto no oval"
        case .failed(let reason):
            return instruction(for: reason)
        }
    }

    private func fallbackInstruction() -> String {
        if !verificationManager.faceDetected {
            return "🙂 👀 Encaixe o rosto inteiro no oval olhando para a tela"
        }

        if !verificationManager.distanceCorrect {
            return distanceInstruction()
        }

        if !verificationManager.faceAligned {
            return centeringInstruction()
        }

        if !verificationManager.headAligned {
            return headAlignmentInstruction()
        }

        return "🙂 ✅ Continue olhando para a tela. Na contagem, olhe para a camera"
    }

    private func instruction(for reason: CameraCaptureBlockReason) -> String {
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
            return distanceInstruction()
        case .faceNotCentered:
            return centeringInstruction()
        case .headNotAligned:
            return headAlignmentInstruction()
        case .calibrationUnavailable:
            return calibrationInstruction()
        case .unstableFrame:
            return "📱 ⏳ Segure o celular sem girar nem aproximar por 1 segundo"
        case .staleFrame:
            return "📱 ⏳ Aguarde a imagem atualizar antes da captura"
        }
    }

    private func instruction(for reason: TrueDepthBlockReason) -> String {
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
            return "📱 ⏳ Segure o celular reto e parado ate a malha estabilizar"
        }
    }

    private func calibrationInstruction() -> String {
        if let failure = cameraManager.trueDepthFailureReason {
            return instruction(for: failure)
        }

        return "📱 ⏳ Segure o celular reto e parado ate o sensor confirmar a malha"
    }

    // MARK: - Bloco visual
    private func instructionView(text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(10)
    }

    // MARK: - Distancia
    private func distanceInstruction() -> String {
        let minDistance = verificationManager.minDistance
        let maxDistance = verificationManager.maxDistance
        let currentDistance = verificationManager.lastMeasuredDistance

        if verificationManager.projectedFaceTooSmall {
            return "🙂 ↔️ Aproxime o rosto ate os olhos ocuparem melhor o oval"
        }

        if currentDistance <= 0 {
            return "🙂 ↔️ Posicione o rosto entre \(Int(minDistance)) e \(Int(maxDistance)) cm da tela"
        }

        if currentDistance < minDistance {
            let diff = max(1, Int(round(minDistance - currentDistance)))
            return "🙂 ↔️ Afaste cerca de \(diff) cm para entrar na faixa ideal"
        }

        let diff = max(1, Int(round(currentDistance - maxDistance)))
        return "🙂 ↔️ Aproxime cerca de \(diff) cm para entrar na faixa ideal"
    }

    // MARK: - Centralizacao
    private func centeringInstruction() -> String {
        let rawX = verificationManager.facePosition["x"] ?? 0
        let rawY = verificationManager.facePosition["y"] ?? 0
        let (xPos, yPos) = verificationManager.adjustOffsets(horizontal: rawX, vertical: rawY)
        let dominantOffset = max(abs(xPos), abs(yPos))

        if abs(xPos) >= abs(yPos) {
            if xPos > 0 {
                return "📱 ⬇️ Baixe \(format(max(abs(xPos), 0.1))) cm ate a camera ficar no meio do nariz e na altura das pupilas"
            }

            if xPos < 0 {
                return "📱 ⬆️ Levante \(format(max(abs(xPos), 0.1))) cm ate a camera ficar no meio do nariz e na altura das pupilas"
            }
        } else {
            if yPos > 0 {
                return "📱 ➡️ Leve o celular \(format(max(abs(yPos), 0.1))) cm para a direita ate a camera ficar no meio do nariz"
            }

            if yPos < 0 {
                return "📱 ⬅️ Leve o celular \(format(max(abs(yPos), 0.1))) cm para a esquerda ate a camera ficar no meio do nariz"
            }
        }

        if dominantOffset > 0.05 {
            return "📱 ↔️ Faca um ajuste fino ate a camera ficar no meio do nariz e na altura das pupilas"
        }

        return "📱 ⏳ Segure o celular reto sem girar"
    }

    // MARK: - Cabeca
    /// Regra do fluxo: toda instrucao de alinhamento precisa dizer o que mover.
    private func headAlignmentInstruction() -> String {
        if let adjustment = dominantHeadAxisAdjustment() {
            return adjustment.instruction
        }

        return "🙂 ↔️ Traga o rosto para frente, sem inclinar, sem virar e com o queixo neutro"
    }

    /// Escolhe sempre o eixo dominante para a UI orientar um ajuste por vez.
    private func dominantHeadAxisAdjustment() -> HeadAxisAdjustment? {
        guard let roll = verificationManager.alignmentData["roll"],
              let yaw = verificationManager.alignmentData["yaw"],
              let pitch = verificationManager.alignmentData["pitch"] else {
            return nil
        }

        let angleTolerance: Float = 2
        let candidates: [(axis: String, value: Float)] = [
            ("roll", roll),
            ("yaw", yaw),
            ("pitch", pitch)
        ]

        guard let dominant = candidates
            .filter({ abs($0.value) > angleTolerance && isPlausiblePoseAngle($0.value) })
            .max(by: { abs($0.value) < abs($1.value) }) else {
            return nil
        }

        let correction = correctedDegrees(from: dominant.value, tolerance: angleTolerance)
        switch dominant.axis {
        case "roll":
            return dominant.value > 0 ? .rollLeft(correction) : .rollRight(correction)
        case "yaw":
            return dominant.value > 0 ? .yawRight(correction) : .yawLeft(correction)
        case "pitch":
            return dominant.value > 0 ? .pitchUp(correction) : .pitchDown(correction)
        default:
            return nil
        }
    }

    private func correctedDegrees(from angle: Float,
                                  tolerance: Float) -> Float {
        max(abs(angle) - tolerance, 0.5)
    }

    private func format(_ value: Float, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value)
    }

    private func isPlausiblePoseAngle(_ angle: Float) -> Bool {
        abs(angle) <= InstructionLimits.maxPlausiblePoseDegrees
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
                    Text(verification.isChecked ? "OK" : verification.type.menuTitle)
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
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 20)
    }

    private func progressHeader() -> some View {
        let completedCount = verificationManager.verifications.filter { $0.isChecked && !$0.type.isOptional }.count
        let requiredCount = verificationManager.verifications.filter { !$0.type.isOptional }.count
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
}
