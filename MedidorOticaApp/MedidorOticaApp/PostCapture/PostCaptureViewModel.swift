//
//  PostCaptureViewModel.swift
//  MedidorOticaApp
//
//  Controla o estado das etapas pós-captura permitindo edição e cálculo das medidas finais.
//

import Foundation
import SwiftUI

// MARK: - Enumerações de Etapas
enum PostCaptureEye: String {
    case right = "Direito"
    case left = "Esquerdo"
}

enum PostCaptureStage: Int, CaseIterable {
    case pupil
    case horizontal
    case vertical
    case summary

    /// Retorna a descrição textual da etapa atual.
    var description: String {
        switch self {
        case .pupil: return "Localize a pupila"
        case .horizontal: return "Ajuste a largura da lente"
        case .vertical: return "Ajuste a altura da lente"
        case .summary: return "Resumo das medidas"
        }
    }
}

// MARK: - ViewModel
@MainActor
final class PostCaptureViewModel: ObservableObject {
    // MARK: - Propriedades Públicas
    @Published var configuration: PostCaptureConfiguration
    @Published var metrics: PostCaptureMetrics?
    @Published var currentEye: PostCaptureEye = .right
    @Published var currentStage: PostCaptureStage = .pupil
    @Published var isProcessing = false
    @Published var errorMessage: String?

    let capturedImage: UIImage
    private let baseMeasurement: Measurement?

    // MARK: - Estados Internos
    private var didMirrorLeftEye = false

    // MARK: - Inicialização
    init(image: UIImage, existingMeasurement: Measurement? = nil) {
        self.capturedImage = image
        self.baseMeasurement = existingMeasurement
        if let measurement = existingMeasurement,
           let storedConfiguration = measurement.postCaptureConfiguration,
           let storedMetrics = measurement.postCaptureMetrics {
            self.configuration = storedConfiguration
            self.metrics = storedMetrics
            self.currentStage = .summary
            self.isProcessing = false
            self.didMirrorLeftEye = true
        } else {
            self.configuration = PostCaptureConfiguration()
            self.metrics = nil
            self.isProcessing = true
            Task { await runAnalysis() }
        }
    }

    // MARK: - Acesso a Dados
    var currentEyeData: EyeMeasurementData {
        switch currentEye {
        case .right: return configuration.rightEye
        case .left: return configuration.leftEye
        }
    }

    var stageInstructions: String {
        switch currentStage {
        case .pupil:
            return "Arraste o ponto azul para o centro exato da pupila."
        case .horizontal:
            return "Posicione as barras verticais nos limites nasal e temporal da lente."
        case .vertical:
            return "Ajuste as barras horizontais aos limites superior e inferior da lente."
        case .summary:
            return "Revise os valores antes de salvar no histórico."
        }
    }

    var showEyeLabel: Bool {
        currentStage != .summary
    }

    var canGoBack: Bool {
        if currentStage == .summary { return true }
        if currentStage == .pupil { return currentEye == .left }
        return true
    }

    var isOnSummary: Bool {
        currentStage == .summary
    }

    // MARK: - Processamento Inicial
    private func runAnalysis() async {
        do {
            let result = try await PostCaptureProcessor.shared.analyze(image: capturedImage)
            await MainActor.run {
                self.configuration = result.configuration
                self.isProcessing = false
            }
        } catch {
            await MainActor.run {
                self.isProcessing = false
                self.errorMessage = error.localizedDescription
                self.configuration = PostCaptureConfiguration()
            }
        }
    }

    // MARK: - Navegação
    func advanceStage() {
        guard !isProcessing else { return }

        switch currentStage {
        case .pupil:
            currentStage = .horizontal
        case .horizontal:
            currentStage = .vertical
        case .vertical:
            if currentEye == .right {
                mirrorLeftEyeIfNeeded()
                currentEye = .left
                currentStage = .pupil
            } else {
                finalizeMetrics()
                currentStage = .summary
            }
        case .summary:
            break
        }
    }

    func goBack() {
        guard !isProcessing else { return }

        switch currentStage {
        case .pupil:
            if currentEye == .left {
                currentEye = .right
                currentStage = .vertical
            }
        case .horizontal:
            currentStage = .pupil
        case .vertical:
            currentStage = .horizontal
        case .summary:
            currentStage = .vertical
            currentEye = .left
        }
    }

    private func mirrorLeftEyeIfNeeded() {
        guard !didMirrorLeftEye else { return }
        let mirrored = configuration.rightEye.mirrored(around: configuration.centralPoint.x)
        configuration.leftEye = mirrored.normalizedOrder()
        didMirrorLeftEye = true
    }

    // MARK: - Atualizações de Pontos
    func updatePupil(to point: NormalizedPoint) {
        var updated = currentEyeData
        updated.pupil = point.clamped()
        apply(updatedEye: updated)
    }

    func updateVerticalBar(isNasal: Bool, value: CGFloat) {
        var updated = currentEyeData
        if isNasal {
            updated.nasalBarX = value
        } else {
            updated.temporalBarX = value
        }
        apply(updatedEye: updated)
    }

    func updateHorizontalBar(isInferior: Bool, value: CGFloat) {
        var updated = currentEyeData
        if isInferior {
            updated.inferiorBarY = value
        } else {
            updated.superiorBarY = value
        }
        apply(updatedEye: updated)
    }

    private func apply(updatedEye: EyeMeasurementData) {
        let normalized = updatedEye.normalizedOrder()
        switch currentEye {
        case .right:
            configuration = PostCaptureConfiguration(centralPoint: configuration.centralPoint,
                                                     rightEye: normalized,
                                                     leftEye: configuration.leftEye)
        case .left:
            configuration = PostCaptureConfiguration(centralPoint: configuration.centralPoint,
                                                     rightEye: configuration.rightEye,
                                                     leftEye: normalized)
            didMirrorLeftEye = true
        }
    }

    // MARK: - Cálculo de Métricas
    func finalizeMetrics() {
        let orderedRight = configuration.rightEye.normalizedOrder()
        let orderedLeft = configuration.leftEye.normalizedOrder()
        let center = configuration.centralPoint.clamped()

        let rightHorizontal = abs(orderedRight.temporalBarX - orderedRight.nasalBarX) * PostCaptureScale.horizontalReferenceMM
        let leftHorizontal = abs(orderedLeft.temporalBarX - orderedLeft.nasalBarX) * PostCaptureScale.horizontalReferenceMM

        let rightVertical = abs(orderedRight.inferiorBarY - orderedRight.superiorBarY) * PostCaptureScale.verticalReferenceMM
        let leftVertical = abs(orderedLeft.inferiorBarY - orderedLeft.superiorBarY) * PostCaptureScale.verticalReferenceMM

        let rightDNP = abs(orderedRight.pupil.x - center.x) * PostCaptureScale.horizontalReferenceMM
        let leftDNP = abs(orderedLeft.pupil.x - center.x) * PostCaptureScale.horizontalReferenceMM

        let rightAltura = abs(orderedRight.inferiorBarY - orderedRight.pupil.y) * PostCaptureScale.verticalReferenceMM
        let leftAltura = abs(orderedLeft.inferiorBarY - orderedLeft.pupil.y) * PostCaptureScale.verticalReferenceMM

        let ponte = abs(orderedLeft.nasalBarX - orderedRight.nasalBarX) * PostCaptureScale.horizontalReferenceMM

        let rightSummary = EyeMeasurementSummary(horizontalMaior: Double(rightHorizontal),
                                                 verticalMaior: Double(rightVertical),
                                                 dnp: Double(rightDNP),
                                                 alturaPupilar: Double(rightAltura))
        let leftSummary = EyeMeasurementSummary(horizontalMaior: Double(leftHorizontal),
                                                verticalMaior: Double(leftVertical),
                                                dnp: Double(leftDNP),
                                                alturaPupilar: Double(leftAltura))

        metrics = PostCaptureMetrics(rightEye: rightSummary,
                                     leftEye: leftSummary,
                                     ponte: Double(ponte))
    }

    // MARK: - Construção de Measurement
    func buildMeasurement(clientName: String) -> Measurement? {
        guard let metrics else { return nil }
        let trimmed = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let identifier = baseMeasurement?.id ?? UUID()
        let date = baseMeasurement?.date ?? Date()

        return Measurement(clientName: trimmed,
                           capturedImage: capturedImage,
                           postCaptureConfiguration: configuration,
                           postCaptureMetrics: metrics,
                           id: identifier,
                           date: date)
    }
}
