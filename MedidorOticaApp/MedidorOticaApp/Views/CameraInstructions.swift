//
//  CameraInstructions.swift
//  MedidorOticaApp
//
//  Textos curtos e objetivos para orientar a captura em tempo real.
//

import SwiftUI

// MARK: - Construtor da instrucao da cabeca
enum HeadPoseInstructionBuilder {
    static let toleranceDegrees: Float = 2.0

    /// Escolhe um unico eixo por vez, seguindo a ordem pitch, yaw e roll.
    static func adjustment(from snapshot: HeadPoseSnapshot) -> HeadAxisAdjustment? {
        if abs(snapshot.pitchDegrees) > toleranceDegrees {
            let correction = displayedDegrees(from: snapshot.pitchDegrees)
            return snapshot.pitchDegrees > 0 ? .pitchUp(correction) : .pitchDown(correction)
        }

        if abs(snapshot.yawDegrees) > toleranceDegrees {
            let correction = displayedDegrees(from: snapshot.yawDegrees)
            return snapshot.yawDegrees > 0 ? .yawRight(correction) : .yawLeft(correction)
        }

        if abs(snapshot.rollDegrees) > toleranceDegrees {
            let correction = displayedDegrees(from: snapshot.rollDegrees)
            return snapshot.rollDegrees > 0 ? .rollLeft(correction) : .rollRight(correction)
        }

        return nil
    }

    /// Mostra apenas o quanto falta corrigir apos a tolerancia.
    private static func displayedDegrees(from angle: Float) -> Float {
        max(round(abs(angle) - toleranceDegrees), 1)
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
        case .headPoseUnavailable, .headNotAligned:
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
            return "📱 ↔️ Aproxime o rosto ate o sensor confirmar a malha"
        }
    }

    private func calibrationInstruction() -> String {
        if let failure = cameraManager.trueDepthFailureReason {
            return instruction(for: failure)
        }

        return "📱 ↔️ Aproxime o rosto ate o sensor confirmar a malha"
    }

    // MARK: - Bloco visual
    private func instructionView(text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .appGlassSurface(cornerRadius: 22,
                             borderOpacity: 0.62,
                             tintOpacity: 0.16,
                             interactive: false)
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
    private func centeringInstruction() -> String {
        let rawX = verificationManager.facePosition["x"] ?? 0
        let rawY = verificationManager.facePosition["y"] ?? 0
        let (xPos, yPos) = verificationManager.adjustOffsets(horizontal: rawX, vertical: rawY)
        let dominantOffset = max(abs(xPos), abs(yPos))

        if abs(xPos) >= abs(yPos) {
            if xPos > 0 {
                return "📱 ➡️ Leve o celular \(format(max(abs(xPos), 0.1))) cm para a direita ate a camera ficar no PC"
            }

            if xPos < 0 {
                return "📱 ⬅️ Leve o celular \(format(max(abs(xPos), 0.1))) cm para a esquerda ate a camera ficar no PC"
            }
        } else {
            if yPos > 0 {
                return "📱 ⬆️ Levante o celular \(format(max(abs(yPos), 0.1))) cm ate a camera ficar na altura do PC"
            }

            if yPos < 0 {
                return "📱 ⬇️ Baixe o celular \(format(max(abs(yPos), 0.1))) cm ate a camera ficar na altura do PC"
            }
        }

        if dominantOffset > 0.05 {
            return "📱 ↔️ Faca um ajuste fino ate a camera ficar no PC"
        }

        return "📱 ⏳ Segure o celular reto sem girar"
    }

    // MARK: - Cabeca
    /// Toda instrucao da etapa 4 precisa apontar um eixo real.
    private func headAlignmentInstruction() -> String {
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
        VStack(alignment: .trailing, spacing: 8) {
            progressHeader()
            ForEach(verificationManager.verifications) { verification in
                HStack(spacing: 8) {
                    Text(verification.isChecked ? "OK" : verification.type.menuTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)

                    Circle()
                        .foregroundColor(verification.isChecked ? .green : .red)
                        .frame(width: 9, height: 9)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .appGlassSurface(cornerRadius: 22,
                         borderOpacity: 0.62,
                         tintOpacity: 0.14,
                         interactive: false)
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
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .frame(width: 50, height: 8)
                    .foregroundStyle(.white.opacity(0.24))

                RoundedRectangle(cornerRadius: 4)
                    .frame(width: progressWidth, height: 8)
                    .foregroundColor(verificationManager.allVerificationsChecked ? .green : .orange)
            }
        }
    }
}
