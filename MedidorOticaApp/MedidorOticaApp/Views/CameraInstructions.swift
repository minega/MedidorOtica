//
//  CameraInstructions.swift
//  MedidorOticaApp
//
//  Instrucoes curtas para orientar a captura em tempo real.
//

import SwiftUI

struct CameraInstructions: View {
    /// Observa alteracoes do `VerificationManager` para atualizar as instrucoes.
    @ObservedObject var verificationManager: VerificationManager
    /// Observa o estado real do pipeline de captura.
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        instructionView(text: currentInstruction())
    }

    // MARK: - Texto principal
    private func currentInstruction() -> String {
        switch cameraManager.captureState {
        case .preparing:
            return "📱⏳ Preparando camera"
        case .countdown:
            return "🙂⏱️ Mantenha a posicao"
        case .capturing:
            return "📱📸 Capturando"
        case .captured:
            return "🙂✅ Foto concluida"
        case .error(let reason):
            return instruction(for: reason)
        case .checking(let reason):
            return instruction(for: reason)
        case .stableReady:
            return "🙂✅ Pronto para capturar"
        case .idle:
            return fallbackInstruction()
        }
    }

    private func fallbackInstruction() -> String {
        if !verificationManager.faceDetected {
            return "📱↔️ Centralize o rosto"
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

        return "📱⏳ \(cameraManager.captureHint)"
    }

    private func instruction(for reason: CameraCaptureBlockReason) -> String {
        switch reason {
        case .preparingSession:
            return "📱⏳ Preparando camera"
        case .sessionUnavailable:
            return "📱⏳ Reiniciando sessao"
        case .trackingUnavailable:
            return "🙂🔄 Reenquadre o rosto"
        case .faceNotDetected:
            return "📱↔️ Centralize o rosto"
        case .distanceOutOfRange:
            return distanceInstruction()
        case .faceNotCentered:
            return centeringInstruction()
        case .headNotAligned:
            return headAlignmentInstruction()
        case .calibrationUnavailable, .unstableFrame, .staleFrame:
            return "📱⏳ \(cameraManager.captureHint)"
        }
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

        if currentDistance <= 0 {
            return "🙂↔️ Fique a \(Int(minDistance))-\(Int(maxDistance)) cm"
        }

        if currentDistance < minDistance {
            let diff = max(1, Int(round(minDistance - currentDistance)))
            return "🙂⬅️ Afaste \(diff) cm"
        }

        let diff = max(1, Int(round(currentDistance - maxDistance)))
        return "🙂➡️ Aproxime \(diff) cm"
    }

    // MARK: - Centralizacao
    private func centeringInstruction() -> String {
        let rawX = verificationManager.facePosition["x"] ?? 0
        let rawY = verificationManager.facePosition["y"] ?? 0
        let (xPos, yPos) = verificationManager.adjustOffsets(horizontal: rawX, vertical: rawY)

        if abs(xPos) >= abs(yPos) {
            if xPos > 0.5 {
                return "📱⬇️ Baixe \(format(abs(xPos))) cm"
            }

            if xPos < -0.5 {
                return "📱⬆️ Levante \(format(abs(xPos))) cm"
            }
        } else {
            if yPos > 0.5 {
                return "📱➡️ Mova \(format(abs(yPos))) cm"
            }

            if yPos < -0.5 {
                return "📱⬅️ Mova \(format(abs(yPos))) cm"
            }
        }

        return "📱⏳ Mantenha o celular alinhado"
    }

    // MARK: - Cabeca
    private func headAlignmentInstruction() -> String {
        let roll = verificationManager.alignmentData["roll"] ?? 0
        let yaw = verificationManager.alignmentData["yaw"] ?? 0
        let pitch = verificationManager.alignmentData["pitch"] ?? 0
        let tolerance: Float = 3

        if abs(roll) > max(abs(yaw), abs(pitch)), abs(roll) > tolerance {
            let magnitude = format(abs(roll), digits: 0)
            return roll > 0 ? "🙂↩️ Incline \(magnitude)°" : "🙂↪️ Incline \(magnitude)°"
        }

        if abs(yaw) > abs(pitch), abs(yaw) > tolerance {
            let magnitude = format(abs(yaw), digits: 0)
            return yaw > 0 ? "🙂➡️ Vire \(magnitude)°" : "🙂⬅️ Vire \(magnitude)°"
        }

        if abs(pitch) > tolerance {
            let magnitude = format(abs(pitch), digits: 0)
            return pitch > 0 ? "🙂⬆️ Queixo \(magnitude)°" : "🙂⬇️ Queixo \(magnitude)°"
        }

        return "🙂⏳ Mantenha a cabeca reta"
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
                    Text(verification.isChecked ? "OK" : simplifyVerificationText(verification.text))
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

    private func simplifyVerificationText(_ text: String) -> String {
        switch text.lowercased() {
        case let value where value.contains("rosto detectado"):
            return "👤 Rosto"
        case let value where value.contains("distancia") || value.contains("distância"):
            return "📍 Distancia"
        case let value where value.contains("centraliz"):
            return "⬜ Centro"
        case let value where value.contains("alinha"):
            return "🕯️ Alinhado"
        case let value where value.contains("cabeca") || value.contains("cabeça"):
            return "🧠 Cabeca"
        default:
            return text.count > 10 ? String(text.prefix(10)) + "..." : text
        }
    }
}
