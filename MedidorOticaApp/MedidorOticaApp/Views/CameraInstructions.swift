//
//  CameraInstructions.swift
//  MedidorOticaApp
//
//  Textos curtos e estabilizados para orientar a captura em tempo real.
//

import SwiftUI
import Combine

// MARK: - Construtor da instrucao da cabeca
enum HeadPoseInstructionBuilder {
    static let rollToleranceDegrees: Float = 0.8
    static let yawToleranceDegrees: Float = 0.8
    static let pitchToleranceDegrees: Float = 1.0

    /// Escolhe um unico eixo por vez, seguindo a ordem pitch, yaw e roll.
    static func adjustment(from snapshot: HeadPoseSnapshot) -> HeadAxisAdjustment? {
        if abs(snapshot.pitchDegrees) > pitchToleranceDegrees {
            let correction = displayedDegrees(from: snapshot.pitchDegrees,
                                              tolerance: pitchToleranceDegrees)
            return snapshot.pitchDegrees > 0 ? .pitchUp(correction) : .pitchDown(correction)
        }

        if abs(snapshot.yawDegrees) > yawToleranceDegrees {
            let correction = displayedDegrees(from: snapshot.yawDegrees,
                                              tolerance: yawToleranceDegrees)
            return snapshot.yawDegrees > 0 ? .yawRight(correction) : .yawLeft(correction)
        }

        if abs(snapshot.rollDegrees) > rollToleranceDegrees {
            let correction = displayedDegrees(from: snapshot.rollDegrees,
                                              tolerance: rollToleranceDegrees)
            return snapshot.rollDegrees > 0 ? .rollLeft(correction) : .rollRight(correction)
        }

        return nil
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

    var axis: CameraGuidanceAxis {
        switch self {
        case .pitchUp, .pitchDown:
            return .pitch
        case .yawLeft, .yawRight:
            return .yaw
        case .rollLeft, .rollRight:
            return .roll
        }
    }

    var direction: CameraGuidanceDirection {
        switch self {
        case .pitchUp:
            return .up
        case .pitchDown:
            return .down
        case .yawLeft, .rollLeft:
            return .left
        case .yawRight, .rollRight:
            return .right
        }
    }

    var magnitude: Float {
        switch self {
        case .rollLeft(let value),
             .rollRight(let value),
             .yawLeft(let value),
             .yawRight(let value),
             .pitchUp(let value),
             .pitchDown(let value):
            return value
        }
    }

    private static func degreesText(_ value: Float) -> String {
        String(format: "%.0f", value)
    }
}

// MARK: - Guidance
private enum CameraGuidanceFamily: Equatable {
    case immediate
    case centering
    case head
    case headUnavailable
}

private enum CameraGuidanceAxis: String, Equatable {
    case none
    case horizontal
    case vertical
    case pitch
    case yaw
    case roll
}

private enum CameraGuidanceDirection: String, Equatable {
    case none
    case left
    case right
    case up
    case down
}

private struct CameraGuidance: Equatable {
    let text: String
    let family: CameraGuidanceFamily
    let axis: CameraGuidanceAxis
    let direction: CameraGuidanceDirection
    let magnitude: Float

    var isStabilizable: Bool {
        family == .centering || family == .head || family == .headUnavailable
    }

    var stabilityKey: String {
        "\(family)-\(axis.rawValue)-\(direction.rawValue)"
    }

    static func immediate(_ text: String) -> CameraGuidance {
        CameraGuidance(text: text,
                       family: .immediate,
                       axis: .none,
                       direction: .none,
                       magnitude: 0)
    }

    static func centering(text: String,
                          axis: CameraGuidanceAxis,
                          direction: CameraGuidanceDirection,
                          magnitude: Float) -> CameraGuidance {
        CameraGuidance(text: text,
                       family: .centering,
                       axis: axis,
                       direction: direction,
                       magnitude: magnitude)
    }

    static func head(_ adjustment: HeadAxisAdjustment) -> CameraGuidance {
        CameraGuidance(text: adjustment.instruction,
                       family: .head,
                       axis: adjustment.axis,
                       direction: adjustment.direction,
                       magnitude: adjustment.magnitude)
    }

    static func headUnavailable(_ text: String) -> CameraGuidance {
        CameraGuidance(text: text,
                       family: .headUnavailable,
                       axis: .none,
                       direction: .none,
                       magnitude: 0)
    }
}

// MARK: - Histerese da UI
/// Estabiliza apenas a orientacao exibida, sem relaxar o gate real da captura.
private final class CameraGuidanceStabilizer: ObservableObject {
    private enum Constants {
        static let switchPersistenceFrames = 3
        static let unavailableHoldFrames = 4
        static let centeringImmediateDelta: Float = 1.0
        static let headImmediateDelta: Float = 2.0
    }

    @Published private(set) var displayedGuidance: CameraGuidance?

    private var pendingGuidance: CameraGuidance?
    private var pendingCount = 0
    private var unavailableCount = 0

    func update(with guidance: CameraGuidance) {
        guard let current = displayedGuidance else {
            displayedGuidance = guidance
            resetPending()
            unavailableCount = 0
            return
        }

        guard guidance != current else {
            unavailableCount = 0
            return
        }

        guard current.isStabilizable, guidance.isStabilizable else {
            displayedGuidance = guidance
            resetPending()
            unavailableCount = 0
            return
        }

        if guidance.family == .headUnavailable, current.family == .head {
            unavailableCount += 1
            if unavailableCount < Constants.unavailableHoldFrames {
                return
            }

            displayedGuidance = guidance
            resetPending()
            unavailableCount = 0
            return
        }

        unavailableCount = 0

        if guidance.family != current.family {
            displayedGuidance = guidance
            resetPending()
            return
        }

        if guidance.axis == current.axis && guidance.direction == current.direction {
            displayedGuidance = guidance
            resetPending()
            return
        }

        if shouldSwitchImmediately(from: current, to: guidance) {
            displayedGuidance = guidance
            resetPending()
            return
        }

        if pendingGuidance?.stabilityKey == guidance.stabilityKey {
            pendingCount += 1
        } else {
            pendingGuidance = guidance
            pendingCount = 1
        }

        if pendingCount >= Constants.switchPersistenceFrames {
            displayedGuidance = guidance
            resetPending()
        }
    }

    private func shouldSwitchImmediately(from current: CameraGuidance,
                                         to guidance: CameraGuidance) -> Bool {
        let threshold: Float

        switch guidance.family {
        case .centering:
            threshold = Constants.centeringImmediateDelta
        case .head:
            threshold = Constants.headImmediateDelta
        case .immediate, .headUnavailable:
            return false
        }

        return guidance.magnitude >= current.magnitude + threshold
    }

    private func resetPending() {
        pendingGuidance = nil
        pendingCount = 0
    }
}

// MARK: - Instrucoes da camera
struct CameraInstructions: View {
    /// Observa as verificacoes do enquadramento.
    @ObservedObject var verificationManager: VerificationManager
    /// Observa o estado real do pipeline de captura.
    @ObservedObject var cameraManager: CameraManager
    /// Evita que a UI fique alternando seta para lados opostos por ruido de frame.
    @StateObject private var guidanceStabilizer = CameraGuidanceStabilizer()

    var body: some View {
        let guidance = currentGuidance()

        return instructionView(text: guidanceStabilizer.displayedGuidance?.text ?? guidance.text)
            .onAppear {
                guidanceStabilizer.update(with: guidance)
            }
            .onChange(of: guidance) { newValue in
                guidanceStabilizer.update(with: newValue)
            }
    }

    // MARK: - Texto principal
    private func currentGuidance() -> CameraGuidance {
        if shouldShowTrueDepthBootstrap {
            return trueDepthGuidance()
        }

        switch cameraManager.captureState {
        case .preparing:
            return .immediate("📱 ⏳ Aguarde a camera abrir e estabilizar")
        case .countdown:
            return .immediate("🙂 ✅ Mantenha a posicao. Captura automatica iniciando")
        case .capturing:
            return .immediate("📱 📸 Capturando a foto")
        case .captured:
            return .immediate("🙂 ✅ Foto concluida")
        case .error(let reason):
            return guidance(for: reason)
        case .checking(let reason):
            return guidance(for: reason)
        case .stableReady:
            return .immediate("🙂 ✅ Mantenha a posicao. Captura automatica imediata")
        case .idle:
            return fallbackGuidance()
        }
    }

    private var shouldShowTrueDepthBootstrap: Bool {
        cameraManager.isUsingARSession &&
        cameraManager.cameraPosition == .front &&
        !cameraManager.isTrueDepthSensorAlive
    }

    private func trueDepthGuidance() -> CameraGuidance {
        switch cameraManager.trueDepthState {
        case .startingSession:
            return .immediate("📱 ⏳ Aguarde a camera abrir e o TrueDepth iniciar")
        case .waitingForFaceAnchor:
            return .immediate("🙂 👀 Encaixe testa, olhos e queixo dentro do oval")
        case .waitingForEyeProjection:
            return .immediate("🙂 👀 Deixe os dois olhos totalmente visiveis no oval")
        case .waitingForDepthConsistency:
            return guidance(for: cameraManager.trueDepthFailureReason ?? .noRecentSamples)
        case .sensorAlive:
            return .immediate("🙂 ✅ Sensor pronto. Ajuste as verificacoes olhando para a tela")
        case .recovering:
            return .immediate("📱 🔄 Reiniciando o TrueDepth. Mantenha o rosto no oval")
        case .failed(let reason):
            return guidance(for: reason)
        }
    }

    private func fallbackGuidance() -> CameraGuidance {
        if !verificationManager.faceDetected {
            return .immediate("🙂 👀 Encaixe o rosto inteiro no oval olhando para a tela")
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

        return .immediate("🙂 ✅ Mantenha a posicao para a captura automatica")
    }

    private func guidance(for reason: CameraCaptureBlockReason) -> CameraGuidance {
        switch reason {
        case .preparingSession:
            return .immediate("📱 ⏳ Aguarde a camera abrir e estabilizar")
        case .sessionUnavailable:
            return .immediate("📱 🔄 A camera reiniciou. Segure o celular parado")
        case .trackingUnavailable:
            return .immediate("🙂 👀 Reenquadre o rosto inteiro dentro do oval")
        case .faceNotDetected:
            return .immediate("🙂 👀 Encaixe o rosto inteiro no oval olhando para a tela")
        case .distanceOutOfRange:
            return distanceGuidance()
        case .faceNotCentered:
            return centeringGuidance()
        case .headPoseUnavailable, .headNotAligned:
            return headAlignmentGuidance()
        case .calibrationUnavailable:
            return calibrationGuidance()
        case .unstableFrame:
            return .immediate("📱 ⏳ Segure o celular totalmente parado ate validar o frame")
        case .staleFrame:
            return .immediate("📱 ⏳ Aguarde a imagem atualizar antes da captura")
        }
    }

    private func guidance(for reason: TrueDepthBlockReason) -> CameraGuidance {
        switch reason {
        case .noFaceAnchor, .faceNotTracked:
            return .immediate("🙂 👀 Encaixe testa, olhos e queixo dentro do oval")
        case .invalidIntrinsics:
            return .immediate("📱 🔄 O sensor esta reiniciando. Mantenha o rosto no oval")
        case .invalidEyeDepth:
            return .immediate("🙂 👀 Deixe os dois olhos, sobrancelhas e cantos visiveis")
        case .ipdOutOfRange, .pixelBaselineTooSmall:
            return .immediate("🙂 ↔️ Aproxime o rosto ate os olhos ocuparem mais o oval")
        case .noRecentSamples:
            return .immediate("🙂 ↔️ Aproxime o rosto ate aparecer a malha facial")
        case .scaleOutOfRange, .baselineNoiseTooHigh:
            return .immediate("📱 ↔️ Aproxime o rosto ate o sensor confirmar a malha")
        }
    }

    private func calibrationGuidance() -> CameraGuidance {
        if let failure = cameraManager.trueDepthFailureReason {
            return guidance(for: failure)
        }

        return .immediate("📱 ↔️ Aproxime o rosto ate o sensor confirmar a malha")
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
    private func distanceGuidance() -> CameraGuidance {
        let minDistance = verificationManager.minDistance
        let maxDistance = verificationManager.maxDistance
        let currentDistance = verificationManager.lastMeasuredDistance

        if verificationManager.projectedFaceTooSmall {
            return .immediate("🙂 ↔️ Aproxime o rosto ate os olhos ocuparem melhor o oval")
        }

        if currentDistance <= 0 {
            return .immediate("🙂 ↔️ Posicione o rosto entre \(Int(minDistance)) e \(Int(maxDistance)) cm")
        }

        if currentDistance < minDistance {
            let diff = max(1, Int(round(minDistance - currentDistance)))
            return .immediate("🙂 ↔️ Afaste cerca de \(diff) cm para entrar na faixa ideal")
        }

        let diff = max(1, Int(round(currentDistance - maxDistance)))
        return .immediate("🙂 ↔️ Aproxime cerca de \(diff) cm para entrar na faixa ideal")
    }

    // MARK: - Centralizacao
    private func centeringGuidance() -> CameraGuidance {
        let rawX = verificationManager.facePosition["x"] ?? 0
        let rawY = verificationManager.facePosition["y"] ?? 0
        let (xPos, yPos) = verificationManager.adjustOffsets(horizontal: rawX, vertical: rawY)
        let dominantOffset = max(abs(xPos), abs(yPos))

        if abs(xPos) >= abs(yPos) {
            if xPos > 0 {
                let amount = quantizedCentimeters(max(abs(xPos), 0.1))
                return .centering(text: "📱 ➡️ Leve o celular \(format(amount)) cm para a direita ate a camera ficar no PC",
                                  axis: .horizontal,
                                  direction: .right,
                                  magnitude: amount)
            }

            if xPos < 0 {
                let amount = quantizedCentimeters(max(abs(xPos), 0.1))
                return .centering(text: "📱 ⬅️ Leve o celular \(format(amount)) cm para a esquerda ate a camera ficar no PC",
                                  axis: .horizontal,
                                  direction: .left,
                                  magnitude: amount)
            }
        } else {
            if yPos > 0 {
                let amount = quantizedCentimeters(max(abs(yPos), 0.1))
                return .centering(text: "📱 ⬆️ Levante o celular \(format(amount)) cm ate a camera ficar na altura do PC",
                                  axis: .vertical,
                                  direction: .up,
                                  magnitude: amount)
            }

            if yPos < 0 {
                let amount = quantizedCentimeters(max(abs(yPos), 0.1))
                return .centering(text: "📱 ⬇️ Baixe o celular \(format(amount)) cm ate a camera ficar na altura do PC",
                                  axis: .vertical,
                                  direction: .down,
                                  magnitude: amount)
            }
        }

        if dominantOffset > 0.05 {
            return .immediate("📱 ↔️ Faca um ajuste fino ate a camera ficar no PC")
        }

        return .immediate("📱 ⏳ Segure o celular reto sem girar")
    }

    // MARK: - Cabeca
    /// Toda instrucao da etapa 4 precisa apontar um eixo real.
    private func headAlignmentGuidance() -> CameraGuidance {
        guard let snapshot = verificationManager.headPoseSnapshot else {
            return .headUnavailable("🙂 👀 Mostre testa, olhos e queixo para medir os eixos")
        }

        guard let adjustment = HeadPoseInstructionBuilder.adjustment(from: snapshot) else {
            return .immediate("🙂 ✅ Cabeca alinhada nos 3 eixos")
        }

        return .head(adjustment)
    }

    private func format(_ value: Float, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value)
    }

    /// Arredonda a orientacao em centimetros para evitar flip-flop por ruido minimo.
    private func quantizedCentimeters(_ value: Float) -> Float {
        let clamped = max(value, 0.1)
        let step: Float = clamped >= 1.0 ? 0.5 : 0.2
        return max(step, (clamped / step).rounded() * step)
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
}
