//
//  CaptureDiagnosticsRecorder.swift
//  MedidorOticaApp
//
//  Registra snapshots estruturados da captura para depuracao no TestFlight.
//

import Foundation

// MARK: - Gravador de diagnosticos
/// Registra mudancas relevantes do pipeline sem depender de console interativo.
final class CaptureDiagnosticsRecorder {
    private let queue = DispatchQueue(label: "com.medidorotica.capture.diagnostics")
    private var lastSnapshot: CaptureDiagnosticsSnapshot = .empty
    private var lastChangeDate = Date.distantPast
    private var lastPersistentLogDate = Date.distantPast

    /// Registra a mudanca do snapshot atual e reapresenta bloqueios persistentes.
    func record(snapshot: CaptureDiagnosticsSnapshot) {
        queue.async { [weak self] in
            self?.recordLocked(snapshot: snapshot)
        }
    }

    /// Registra uma tentativa explicita de captura com o estado atual do pipeline.
    func recordCaptureAttempt(snapshot: CaptureDiagnosticsSnapshot) {
        queue.async {
            print("Tentativa de captura -> etapa=\(snapshot.overallStep.rawValue) motivo=\(snapshot.blockingReason?.shortMessage ?? "pronto") hint=\(snapshot.blockingHint)")
        }
    }

    private func recordLocked(snapshot: CaptureDiagnosticsSnapshot) {
        let now = Date()
        if snapshot != lastSnapshot {
            lastSnapshot = snapshot
            lastChangeDate = now
            lastPersistentLogDate = now
            print(summary(for: snapshot, label: "Snapshot"))
            return
        }

        guard snapshot.blockingReason != nil else { return }
        guard now.timeIntervalSince(lastChangeDate) >= 1.2 else { return }
        guard now.timeIntervalSince(lastPersistentLogDate) >= 1.2 else { return }

        lastPersistentLogDate = now
        print(summary(for: snapshot, label: "Bloqueio persistente"))
    }

    private func summary(for snapshot: CaptureDiagnosticsSnapshot,
                         label: String) -> String {
        let failure = snapshot.failureDetail?.diagnosticLabel ?? "n/d"
        let trueDepth = String(describing: snapshot.trueDepthState)
        let calibration = snapshot.calibrationReady ? "ok" : (snapshot.calibrationHint ?? "pendente")
        return "\(label) -> etapa=\(snapshot.overallStep.rawValue) motivo=\(snapshot.blockingReason?.shortMessage ?? "pronto") falha=\(failure) TrueDepth=\(trueDepth) calibracao=\(calibration)"
    }
}

// MARK: - Concurrency
/// O acesso ao estado interno e serializado pela fila privada.
extension CaptureDiagnosticsRecorder: @unchecked Sendable {}
