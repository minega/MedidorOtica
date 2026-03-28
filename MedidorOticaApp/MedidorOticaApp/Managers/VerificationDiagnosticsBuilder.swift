//
//  VerificationDiagnosticsBuilder.swift
//  MedidorOticaApp
//
//  Construtores dos detalhes de falha publicados para a captura.
//

import Foundation

// MARK: - Diagnosticos das verificacoes
extension VerificationManager {
    /// Detalhe padrao para a etapa de deteccao de rosto.
    func faceDetectionFailureDetail() -> VerificationFailureDetail {
        VerificationFailureDetail(overallStep: .faceDetection,
                                  blockingReason: .faceNotDetected,
                                  blockingHint: "🙂 👀 Encaixe testa, olhos e queixo dentro do oval",
                                  diagnosticLabel: "Rosto",
                                  technicalReason: "Nenhum rosto rastreado pelo sensor ativo neste frame.",
                                  directionHint: "Encaixe o rosto inteiro dentro do oval.",
                                  confidence: 1)
    }

    /// Detalhe estruturado para a etapa de distancia.
    func distanceFailureDetail() -> VerificationFailureDetail {
        let label = "Distancia"
        if projectedFaceTooSmall {
            return VerificationFailureDetail(overallStep: .distance,
                                             blockingReason: .distanceOutOfRange,
                                             blockingHint: "🙂 ↔️ Aproxime o rosto ate os olhos ocuparem melhor o oval",
                                             diagnosticLabel: label,
                                             technicalReason: "A face projetada ainda ficou pequena demais para medir com precisao.",
                                             directionHint: "Aproxime o rosto da tela mantendo o nariz no centro.",
                                             confidence: 0.95)
        }

        let distance = lastMeasuredDistance
        if distance <= 0 {
            return VerificationFailureDetail(overallStep: .distance,
                                             blockingReason: .distanceOutOfRange,
                                             blockingHint: "🙂 ↔️ Posicione o rosto entre \(Int(minDistance)) e \(Int(maxDistance)) cm da tela",
                                             diagnosticLabel: label,
                                             technicalReason: "A distancia ainda nao foi medida com estabilidade suficiente.",
                                             directionHint: "Ajuste a distancia do rosto mantendo o oval preenchido.",
                                             confidence: 0.75)
        }

        if distance < minDistance {
            let diff = max(1, Int(round(minDistance - distance)))
            return VerificationFailureDetail(overallStep: .distance,
                                             blockingReason: .distanceOutOfRange,
                                             blockingHint: "🙂 ↔️ Afaste cerca de \(diff) cm para entrar na faixa ideal",
                                             diagnosticLabel: label,
                                             technicalReason: "O rosto esta perto demais: \(String(format: "%.1f", distance)) cm.",
                                             directionHint: "Afaste o rosto sem sair do oval.",
                                             confidence: 0.95)
        }

        let diff = max(1, Int(round(distance - maxDistance)))
        return VerificationFailureDetail(overallStep: .distance,
                                         blockingReason: .distanceOutOfRange,
                                         blockingHint: "🙂 ↔️ Aproxime cerca de \(diff) cm para entrar na faixa ideal",
                                         diagnosticLabel: label,
                                         technicalReason: "O rosto esta longe demais: \(String(format: "%.1f", distance)) cm.",
                                         directionHint: "Aproxime o rosto mantendo os olhos visiveis.",
                                         confidence: 0.95)
    }

    /// Detalhe estruturado para a etapa de centralizacao.
    func centeringFailureDetail() -> VerificationFailureDetail {
        let rawX = facePosition["x"] ?? 0
        let rawY = facePosition["y"] ?? 0
        let (xPos, yPos) = adjustOffsets(horizontal: rawX, vertical: rawY)

        if abs(xPos) >= abs(yPos), abs(xPos) > 0.05 {
            if xPos > 0 {
                return VerificationFailureDetail(overallStep: .centering,
                                                 blockingReason: .faceNotCentered,
                                                 blockingHint: "📱 ⬇️ Baixe o celular ate o nariz ficar no centro",
                                                 diagnosticLabel: "Centralizacao",
                                                 technicalReason: "O nariz esta \(String(format: "%.2f", xPos)) cm acima do centro.",
                                                 directionHint: "Baixe o celular mantendo a cabeca reta.",
                                                 confidence: 0.9)
            }

            return VerificationFailureDetail(overallStep: .centering,
                                             blockingReason: .faceNotCentered,
                                             blockingHint: "📱 ⬆️ Levante o celular ate o nariz ficar no centro",
                                             diagnosticLabel: "Centralizacao",
                                             technicalReason: "O nariz esta \(String(format: "%.2f", abs(xPos))) cm abaixo do centro.",
                                             directionHint: "Levante o celular mantendo o rosto no oval.",
                                             confidence: 0.9)
        }

        if abs(yPos) > 0.05 {
            if yPos > 0 {
                return VerificationFailureDetail(overallStep: .centering,
                                                 blockingReason: .faceNotCentered,
                                                 blockingHint: "📱 ➡️ Leve o celular para a direita ate o nariz ficar no meio",
                                                 diagnosticLabel: "Centralizacao",
                                                 technicalReason: "O nariz esta \(String(format: "%.2f", yPos)) cm a esquerda do centro.",
                                                 directionHint: "Desloque o celular para a direita.",
                                                 confidence: 0.9)
            }

            return VerificationFailureDetail(overallStep: .centering,
                                             blockingReason: .faceNotCentered,
                                             blockingHint: "📱 ⬅️ Leve o celular para a esquerda ate o nariz ficar no meio",
                                             diagnosticLabel: "Centralizacao",
                                             technicalReason: "O nariz esta \(String(format: "%.2f", abs(yPos))) cm a direita do centro.",
                                             directionHint: "Desloque o celular para a esquerda.",
                                             confidence: 0.9)
        }

        return VerificationFailureDetail(overallStep: .centering,
                                         blockingReason: .faceNotCentered,
                                         blockingHint: "📱 ↔️ Faca um ajuste fino ate o nariz ficar exatamente no centro",
                                         diagnosticLabel: "Centralizacao",
                                         technicalReason: "A centralizacao esta no limite da tolerancia, mas ainda nao ficou estavel.",
                                         directionHint: "Mantenha o celular alinhado ao nariz.",
                                         confidence: 0.75)
    }

    /// Detalhe estruturado da etapa de alinhamento.
    func headAlignmentFailureDetail(from diagnostic: HeadAlignmentDiagnostic) -> VerificationFailureDetail {
        let directionHint = diagnostic.primaryFailure?.detail ?? diagnostic.technicalReason
        return VerificationFailureDetail(overallStep: .headAlignment,
                                         blockingReason: .headNotAligned,
                                         blockingHint: diagnostic.blockingHint,
                                         diagnosticLabel: diagnostic.primaryFailure?.title ?? "Alinhamento",
                                         technicalReason: diagnostic.technicalReason,
                                         directionHint: directionHint,
                                         confidence: diagnostic.confidence)
    }
}
