//
//  CameraInstructions.swift
//  MedidorOticaApp
//
//  Componente de instruções para a câmera
//

import SwiftUI

struct CameraInstructions: View {
    /// Observa alterações do `VerificationManager` para atualizar as instruções em tempo real
    @ObservedObject var verificationManager: VerificationManager

    /// Emojis possíveis para indicar o ator responsável pela ação na instrução.
    private enum InstructionActor: String {
        case device = "📱"
        case user = "🙂"
    }

    /// Emojis possíveis para indicar a direção da ação sugerida ao usuário.
    private enum InstructionDirection: String {
        case steady = "↔️"
        case moveLeft = "⬅️"
        case moveRight = "➡️"
        case moveUp = "⬆️"
        case moveDown = "⬇️"
        case rotateRight = "↻"
        case rotateLeft = "↺"
    }

    var body: some View {
        VStack(spacing: 8) {
            // Verifica quais instruções exibir com base nas verificações pendentes
            // Mostra instruções específicas para a primeira verificação que falhar
            if !verificationManager.faceDetected {
                instructionView(actor: .device,
                                 direction: .steady,
                                 message: "Centralize o rosto no oval")
            } else if !verificationManager.distanceCorrect {
                distanceInstructionView()
            } else if !verificationManager.faceAligned {
                centeringInstructionView()
            } else if !verificationManager.headAligned {
                headAlignmentInstructionView()
            } else {
                instructionView(actor: .user,
                                 direction: .steady,
                                 message: "Pronto para capturar")
            }
        }
    }

    // View padrão para instruções simples
    private func instructionView(actor: InstructionActor,
                                 direction: InstructionDirection,
                                 message: String) -> some View {
        Text(formattedInstruction(actor: actor,
                                  direction: direction,
                                  message: message))
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(10)
    }

    /// Monta a string com o par de emojis obrigatório antes da mensagem.
    private func formattedInstruction(actor: InstructionActor,
                                      direction: InstructionDirection,
                                      message: String) -> String {
        "\(actor.rawValue)\(direction.rawValue) \(message)"
    }

    // View específica para instruções de distância
    private func distanceInstructionView() -> some View {
        let minDistance = verificationManager.minDistance
        let maxDistance = verificationManager.maxDistance
        let currentDistance = verificationManager.lastMeasuredDistance

        let direction: InstructionDirection
        let message: String

        if currentDistance <= 0 {
            direction = .steady
            message = "Ajuste para \(Int(minDistance))-\(Int(maxDistance)) cm"
        } else if currentDistance < minDistance {
            let diff = max(1, Int(round(minDistance - currentDistance)))
            direction = .moveLeft
            message = "Afaste \(diff) cm (meta \(Int(minDistance))-\(Int(maxDistance)))"
        } else {
            let diff = max(1, Int(round(currentDistance - maxDistance)))
            direction = .moveRight
            message = "Aproxime \(diff) cm (meta \(Int(minDistance))-\(Int(maxDistance)))"
        }

        return instructionView(actor: .user,
                                direction: direction,
                                message: message)
    }

    // View específica para instruções de centralização
    private func centeringInstructionView() -> some View {
        // Usa os dados de posição do rosto e ajusta conforme a orientação do dispositivo
        let rawX = verificationManager.facePosition["x"] ?? 0
        let rawY = verificationManager.facePosition["y"] ?? 0
        let (xPos, yPos) = verificationManager.adjustOffsets(horizontal: rawX, vertical: rawY)

        var direction: InstructionDirection = .steady
        var message = "Celular alinhado, mantenha"

        // Determina a direção com base na posição atual
        if abs(xPos) >= abs(yPos) {
            // xPos representa o deslocamento vertical
            if xPos > 0.5 {
                let magnitude = String(format: "%.1f", abs(xPos))
                direction = .moveDown
                message = "Baixe \(magnitude) cm"
            } else if xPos < -0.5 {
                let magnitude = String(format: "%.1f", abs(xPos))
                direction = .moveUp
                message = "Levante \(magnitude) cm"
            }
        } else {
            // yPos representa o deslocamento horizontal
            if yPos > 0.5 {
                let magnitude = String(format: "%.1f", abs(yPos))
                direction = .moveRight
                message = "Mova \(magnitude) cm para a direita"
            } else if yPos < -0.5 {
                let magnitude = String(format: "%.1f", abs(yPos))
                direction = .moveLeft
                message = "Mova \(magnitude) cm para a esquerda"
            }
        }

        return instructionView(actor: .device,
                                direction: direction,
                                message: message)
    }

    // View específica para instruções de alinhamento da cabeça
    private func headAlignmentInstructionView() -> some View {
        // Usa os dados de alinhamento para dar instruções específicas
        let roll = verificationManager.alignmentData["roll"] ?? 0
        let yaw = verificationManager.alignmentData["yaw"] ?? 0
        let pitch = verificationManager.alignmentData["pitch"] ?? 0

        let tolerance: Float = 3
        var direction: InstructionDirection = .steady
        var message = "Cabeça alinhada, mantenha"

        // Determina qual rotação precisa de maior correção
        if abs(roll) > max(abs(yaw), abs(pitch)) && abs(roll) > tolerance {
            let magnitude = String(format: "%.0f", abs(roll))
            direction = roll > 0 ? .rotateRight : .rotateLeft
            let directionText = roll > 0 ? "para a direita" : "para a esquerda"
            message = "Incline \(directionText) \(magnitude)°"
        } else if abs(yaw) > abs(pitch) && abs(yaw) > tolerance {
            let magnitude = String(format: "%.0f", abs(yaw))
            direction = yaw > 0 ? .moveRight : .moveLeft
            let directionText = yaw > 0 ? "para a direita" : "para a esquerda"
            message = "Vire \(directionText) \(magnitude)°"
        } else if abs(pitch) > tolerance {
            let magnitude = String(format: "%.0f", abs(pitch))
            direction = pitch > 0 ? .moveUp : .moveDown
            let directionText = pitch > 0 ? "para cima" : "para baixo"
            message = "Queixo \(directionText) \(magnitude)°"
        }

        return instructionView(actor: .user,
                                direction: direction,
                                message: message)
    }

}

// View para o menu de verificações laterais
struct VerificationMenu: View {
    /// Gerenciador observado para refletir mudanças no menu em tempo real
    @ObservedObject var verificationManager: VerificationManager
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Contador de verificações
            HStack {
                let completedCount = verificationManager.verifications.filter { $0.isChecked && !$0.type.isOptional }.count
                let requiredCount = verificationManager.verifications.filter { !$0.type.isOptional }.count
                
                Text("\(completedCount)/\(requiredCount)")
                    .font(.caption)
                    .foregroundColor(.white)
                
                // Indicador de progresso
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: 50, height: 8)
                        .foregroundColor(.gray.opacity(0.5))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: requiredCount > 0 ? 50 * CGFloat(completedCount) / CGFloat(requiredCount) : 0, height: 8)
                        .foregroundColor(verificationManager.allVerificationsChecked ? .green : .orange)
                }
            }
            
            // Todas as verificações (obrigatórias e opcionais)
            ForEach(verificationManager.verifications) { verification in
                HStack(spacing: 6) {
                    let simplifiedText = simplifyVerificationText(verification.text)

                    Text(verification.isChecked ? "OK" : simplifiedText)
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
    
    // Função para simplificar os textos das verificações no menu lateral
    private func simplifyVerificationText(_ text: String) -> String {
        // Mapeando textos longos para versões mais curtas com emoji
        switch text.lowercased() {
        case let t where t.contains("rosto detectado"):
            return "👤 Rosto"
        case let t where t.contains("distância"):
            return "📍 Distância"
        case let t where t.contains("centraliz"):
            return "⬜️ Centrado"
        case let t where t.contains("alinha"):
            return "🕯️ Alinhado"
        case let t where t.contains("cabeça"):
            return "🧠 Cabeça"
        case let t where t.contains("frame") || t.contains("borda"):
            return "🖼️ Borda"
        default:
            // Se não encontrar um padrão conhecido, retorna os primeiros 10 caracteres
            return text.count > 10 ? String(text.prefix(10)) + "..." : text
        }
    }
}
