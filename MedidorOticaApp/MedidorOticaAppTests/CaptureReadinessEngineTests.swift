//
//  CaptureReadinessEngineTests.swift
//  MedidorOticaAppTests
//
//  Valida a estabilidade exigida antes da captura final.
//

import Foundation
import Testing
@testable import MedidorOticaApp

struct CaptureReadinessEngineTests {
    @Test func distanceVerificationDescriptionReflectsTighterRange() async throws {
        #expect(DistanceLimits.minCm == 28.0)
        #expect(DistanceLimits.maxCm == 45.0)
        #expect(VerificationType.distance.description.contains("28cm"))
        #expect(VerificationType.distance.description.contains("45cm"))
    }

    @Test func trueDepthNoRecentSamplesMessageIsActionable() async throws {
        #expect(TrueDepthBlockReason.noRecentSamples.shortMessage == "Aproxime o rosto ate aparecer a malha facial.")
    }

    @Test func verificationMenuTitlesReflectDetailedFlow() async throws {
        #expect(VerificationType.faceDetection.menuTitle == "Rosto")
        #expect(VerificationType.distance.menuTitle == "28-45 cm")
        #expect(VerificationType.centering.menuTitle == "Nariz")
        #expect(VerificationType.headAlignment.menuTitle == "Cabeca")
    }

    @Test func verificationDescriptionsMatchDetailedCaptureChecks() async throws {
        #expect(VerificationType.faceDetection.description == "Rosto inteiro dentro do oval")
        #expect(VerificationType.centering.description == "Nariz alinhado ao centro do oval")
        #expect(VerificationType.headAlignment.description == "Rosto reto em roll, yaw e pitch")
    }

    @Test func requiresConsecutiveStableFramesBeforeReady() async throws {
        let engine = CaptureReadinessEngine(requiredStableSampleCount: 3,
                                            maximumFrameGap: 0.20,
                                            maximumCaptureAge: 0.15)

        let status1 = engine.evaluate(input: readyInput(timestamp: 1.00))
        let status2 = engine.evaluate(input: readyInput(timestamp: 1.05))
        let status3 = engine.evaluate(input: readyInput(timestamp: 1.10))

        #expect(!status1.isStableReady)
        #expect(!status2.isStableReady)
        #expect(status3.isStableReady)
        #expect(status3.progress == 1.0)
    }

    @Test func resetsWhenCalibrationIsLost() async throws {
        let engine = CaptureReadinessEngine(requiredStableSampleCount: 2,
                                            maximumFrameGap: 0.20,
                                            maximumCaptureAge: 0.15)

        _ = engine.evaluate(input: readyInput(timestamp: 2.00))
        let blocked = engine.evaluate(input: CaptureReadinessInput(evaluation: readyEvaluation(timestamp: 2.05),
                                                                   sessionReady: true,
                                                                   calibrationReady: false))
        let recovered = engine.evaluate(input: readyInput(timestamp: 2.10))

        #expect(blocked.blockReason == .calibrationUnavailable)
        #expect(!recovered.isStableReady)
        #expect(recovered.progress == 0.5)
    }

    @Test func rejectsFramesThatBecomeStaleForCapture() async throws {
        let engine = CaptureReadinessEngine(requiredStableSampleCount: 2,
                                            maximumFrameGap: 0.20,
                                            maximumCaptureAge: 0.10)

        _ = engine.evaluate(input: readyInput(timestamp: 3.00))
        _ = engine.evaluate(input: readyInput(timestamp: 3.05))

        #expect(engine.isFrameFresh(3.10))
        #expect(!engine.isFrameFresh(3.20))
    }

    @Test func trueDepthRecoveryDoesNotRestartWithoutFace() async throws {
        let policy = TrueDepthRecoveryPolicy(progressTimeout: 1.0,
                                             recoveryCooldown: 1.5,
                                             persistentFailureThreshold: 3)

        let decision = policy.decision(referenceTimestamp: 2.0,
                                       lastProgressTimestamp: 0.5,
                                       lastRestartTimestamp: nil,
                                       recoveryAttempt: 0,
                                       failureReason: .noFaceAnchor)

        #expect(decision == .none)
    }

    @Test func trueDepthRecoveryRestartsAfterPersistentNoProgress() async throws {
        let policy = TrueDepthRecoveryPolicy(progressTimeout: 1.0,
                                             recoveryCooldown: 1.5,
                                             persistentFailureThreshold: 3)

        let decision = policy.decision(referenceTimestamp: 2.1,
                                       lastProgressTimestamp: 1.0,
                                       lastRestartTimestamp: nil,
                                       recoveryAttempt: 1,
                                       failureReason: .invalidEyeDepth)

        #expect(decision == .restart(reason: .invalidEyeDepth))
    }

    @Test func trueDepthRecoveryShowsFailureDuringCooldownAfterRepeatedRestarts() async throws {
        let policy = TrueDepthRecoveryPolicy(progressTimeout: 1.0,
                                             recoveryCooldown: 1.5,
                                             persistentFailureThreshold: 3)

        let decision = policy.decision(referenceTimestamp: 8.0,
                                       lastProgressTimestamp: 6.0,
                                       lastRestartTimestamp: 7.0,
                                       recoveryAttempt: 3,
                                       failureReason: .baselineNoiseTooHigh)

        #expect(decision == .showFailure(reason: .baselineNoiseTooHigh))
    }

    @Test func trueDepthBootstrapGateUnlocksOnlyForSensorAlive() async throws {
        let blocked = TrueDepthBootstrapStatus(state: .waitingForFaceAnchor,
                                               failureReason: .noFaceAnchor,
                                               recentSampleCount: 0,
                                               lastValidSampleTimestamp: nil,
                                               lastRejectTimestamp: 1.0)
        let ready = TrueDepthBootstrapStatus(state: .sensorAlive,
                                             failureReason: nil,
                                             recentSampleCount: 2,
                                             lastValidSampleTimestamp: 2.0,
                                             lastRejectTimestamp: nil)

        #expect(!blocked.sensorAlive)
        #expect(ready.sensorAlive)
    }

    @Test func trueDepthBootstrapCanUnlockBeforeCalibrationSamplesExist() async throws {
        let status = TrueDepthBootstrapStatus(state: .sensorAlive,
                                              failureReason: nil,
                                              recentSampleCount: 0,
                                              lastValidSampleTimestamp: nil,
                                              lastRejectTimestamp: 4.0)

        #expect(status.sensorAlive)
        #expect(status.recentSampleCount == 0)
    }

    private func readyInput(timestamp: TimeInterval) -> CaptureReadinessInput {
        CaptureReadinessInput(evaluation: readyEvaluation(timestamp: timestamp),
                              sessionReady: true,
                              calibrationReady: true)
    }

    private func readyEvaluation(timestamp: TimeInterval) -> VerificationFrameEvaluation {
        VerificationFrameEvaluation(timestamp: timestamp,
                                    trackingIsNormal: true,
                                    hasTrackedFaceAnchor: true,
                                    faceDetected: true,
                                    distanceCorrect: true,
                                    faceAligned: true,
                                    headAligned: true)
    }
}
