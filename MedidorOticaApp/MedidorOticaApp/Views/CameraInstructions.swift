//
//  CameraInstructions.swift
//  MedidorOticaApp
//
//  Componente de instruções para a câmera
//

import SwiftUI

struct CameraInstructions: View {
    let verificationManager: VerificationManager
    
    var body: some View {
        VStack(spacing: 8) {
            // Verifica quais instruções exibir com base nas verificações pendentes
            // Mostra instruções específicas para a primeira verificação que falhar
            if !verificationManager.faceDetected {
                instructionView(text: "✍️ Posicione seu rosto no oval para detectar suas feições")
            } else if !verificationManager.distanceCorrect {
                distanceInstructionView()
            } else if !verificationManager.faceAligned {
                centeringInstructionView()
            } else if !verificationManager.headAligned {
                headAlignmentInstructionView()
            } else if !verificationManager.gazeCorrect {
                // Quando chegar na verificação de olhar, exibe instruções especiais
                gazeInstructionView()
            } else {
                instructionView(text: "✅ Perfeito! Pronto para capturar a imagem")
            }
        }
    }
    
    // View padrão para instruções simples
    private func instructionView(text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(10)
    }
    
    // View específica para instruções de distância
    private func distanceInstructionView() -> some View {
        let diff: Int
        let instruction: String
        
        if verificationManager.lastMeasuredDistance < verificationManager.minDistance {
            // Muito perto, precisa se afastar
            diff = Int(verificationManager.minDistance - verificationManager.lastMeasuredDistance)
            instruction = "⬅️ Afaste-se aproximadamente \(diff) cm do celular para obter a distância ideal"
        } else {
            // Muito longe, precisa se aproximar
            diff = Int(verificationManager.lastMeasuredDistance - verificationManager.maxDistance)
            instruction = "➡️ Aproxime-se aproximadamente \(diff) cm do celular para obter a distância ideal"
        }
        
        return instructionView(text: instruction)
    }
    
    // View específica para instruções de centralização
    private func centeringInstructionView() -> some View {
        // Usa os dados de posição do rosto para dar instruções específicas
        let xPos = verificationManager.facePosition["x"] ?? 0
        let yPos = verificationManager.facePosition["y"] ?? 0
        
        var instruction = "Centralize seu rosto no oval"
        
        // Determina a direção com base na posição atual
        if abs(xPos) > abs(yPos) {
            // Movimento horizontal mais importante
            if xPos > 0.01 {
                instruction = "⬅️ Mova seu celular para direita aproximadamente \(Int(abs(xPos)*100)) cm"
            } else if xPos < -0.01 {
                instruction = "➡️ Mova seu celular para esquerda aproximadamente \(Int(abs(xPos)*100)) cm"
            }
        } else {
            // Movimento vertical mais importante
            if yPos > 0.01 {
                instruction = "⬆️ Mova seu celular para baixo aproximadamente \(Int(abs(yPos)*100)) cm"
            } else if yPos < -0.01 {
                instruction = "⬇️ Mova seu celular para cima aproximadamente \(Int(abs(yPos)*100)) cm"
            }
        }
        
        return instructionView(text: instruction)
    }
    
    // View específica para instruções de alinhamento da cabeça
    private func headAlignmentInstructionView() -> some View {
        // Usa os dados de alinhamento para dar instruções específicas
        let roll = verificationManager.alignmentData["roll"] ?? 0
        let yaw = verificationManager.alignmentData["yaw"] ?? 0
        let pitch = verificationManager.alignmentData["pitch"] ?? 0
        
        var instruction = "Mantenha sua cabeça reta, sem inclinação"
        
        // Determina qual rotação precisa de maior correção
        if abs(roll) > max(abs(yaw), abs(pitch)) && abs(roll) > 2 {
            let direction = roll > 0 ? "anti-horário" : "horário"
            instruction = "↺️ Gire sua cabeça no sentido \(direction) aproximadamente \(Int(abs(roll))) graus"
        } else if abs(yaw) > abs(pitch) && abs(yaw) > 2 {
            let direction = yaw > 0 ? "esquerda" : "direita"
            instruction = "⤵️ Vire sua cabeça para \(direction) aproximadamente \(Int(abs(yaw))) graus"
        } else if abs(pitch) > 2 {
            let direction = pitch > 0 ? "cima" : "baixo"
            instruction = "⤴️ Incline sua cabeça para \(direction) aproximadamente \(Int(abs(pitch))) graus"
        }
        
        return instructionView(text: instruction)
    }
    
    // View específica para instruções de olhar
    private func gazeInstructionView() -> some View {
        VStack(spacing: 12) {
            instructionView(text: "👁️ Olhe diretamente para a lente da câmera, sem desviar o olhar")
            
            // Destaque visual para a câmera
            CameraHighlight()
        }
    }
}

// View para o menu de verificações laterais
struct VerificationMenu: View {
    let verificationManager: VerificationManager
    
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
        case let t where t.contains("olhar") || t.contains("gaze"):
            return "👁️ Olhar"
        case let t where t.contains("frame") || t.contains("borda"):
            return "🖼️ Borda"
        default:
            // Se não encontrar um padrão conhecido, retorna os primeiros 10 caracteres
            return text.count > 10 ? String(text.prefix(10)) + "..." : text
        }
    }
}
