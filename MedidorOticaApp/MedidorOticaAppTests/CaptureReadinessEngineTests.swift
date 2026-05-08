//
//  CaptureReadinessEngineTests.swift
//  MedidorOticaAppTests
//
//  Valida a estabilidade exigida antes da captura final.
//

import Foundation
import simd
import Testing
@testable import MedidorOticaApp

struct CaptureReadinessEngineTests {
    @Test func distanceVerificationDescriptionReflectsTighterRange() async throws {
        #expect(DistanceLimits.minCm == 30.0)
        #expect(DistanceLimits.maxCm == 40.0)
        #expect(VerificationType.distance.description.contains("30cm"))
        #expect(VerificationType.distance.description.contains("40cm"))
    }

    @Test func rearLiDARDistanceUsesShortCaptureRange() async throws {
        #expect(RearLiDARDistanceLimits.minCm == 35.0)
        #expect(RearLiDARDistanceLimits.maxCm == 55.0)
    }

    @Test func trueDepthNoRecentSamplesMessageIsActionable() async throws {
        #expect(TrueDepthBlockReason.noRecentSamples.shortMessage == "Aproxime o rosto ate aparecer a malha facial.")
    }

    @Test func verificationMenuTitlesReflectDetailedFlow() async throws {
        #expect(VerificationType.faceDetection.menuTitle == "Rosto")
        #expect(VerificationType.distance.menuTitle == "30-40 cm")
        #expect(VerificationType.centering.menuTitle == "Nariz")
        #expect(VerificationType.headAlignment.menuTitle == "Cabeca")
    }

    @Test func verificationDescriptionsMatchDetailedCaptureChecks() async throws {
        #expect(VerificationType.faceDetection.description == "Rosto inteiro dentro do oval")
        #expect(VerificationType.centering.description == "Nariz alinhado ao centro do oval")
        #expect(VerificationType.headAlignment.description == "Rosto reto em roll, yaw e pitch")
    }

    @Test func headPoseInstructionPrioritizesPitchBeforeYawAndRoll() async throws {
        let snapshot = HeadPoseSnapshot(rollDegrees: 10,
                                        yawDegrees: 8,
                                        pitchDegrees: -12,
                                        timestamp: 1,
                                        sensor: .trueDepth)

        #expect(HeadPoseInstructionBuilder.adjustment(from: snapshot) == .pitchDown(11))
    }

    @Test func headPoseInstructionUsesYawBeforeRollWhenPitchIsAligned() async throws {
        let snapshot = HeadPoseSnapshot(rollDegrees: 11,
                                        yawDegrees: 7,
                                        pitchDegrees: 0.4,
                                        timestamp: 1,
                                        sensor: .trueDepth)

        #expect(HeadPoseInstructionBuilder.adjustment(from: snapshot) == .yawRight(6))
    }

    @Test func headPoseInstructionReturnsNilWhenThreeAxesAreWithinTolerance() async throws {
        let snapshot = HeadPoseSnapshot(rollDegrees: 0.5,
                                        yawDegrees: -0.7,
                                        pitchDegrees: 0.9,
                                        timestamp: 1,
                                        sensor: .trueDepth)

        #expect(HeadPoseInstructionBuilder.adjustment(from: snapshot) == nil)
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

    @Test func defaultCapturePolicyUsesShortStableBlock() async throws {
        #expect(CaptureReadinessEngine.defaultStableSampleCount == 4)
        #expect(CaptureReadinessEngine.defaultMaximumFrameGap == 0.16)
        #expect(CaptureReadinessEngine.defaultMaximumCaptureAge == 0.12)
    }

    @Test func keepsStabilityWhenCalibrationPreviewOscillates() async throws {
        let engine = CaptureReadinessEngine(requiredStableSampleCount: 2,
                                            maximumFrameGap: 0.20,
                                            maximumCaptureAge: 0.15)

        _ = engine.evaluate(input: readyInput(timestamp: 2.00))
        let stable = engine.evaluate(input: CaptureReadinessInput(evaluation: readyEvaluation(timestamp: 2.05),
                                                                  sessionReady: true,
                                                                  calibrationReady: false))

        #expect(stable.blockReason == nil)
        #expect(stable.isStableReady)
        #expect(stable.progress == 1.0)
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

    @Test func captureReadinessBlocksWhenHeadPoseIsUnavailable() async throws {
        let engine = CaptureReadinessEngine(requiredStableSampleCount: 2,
                                            maximumFrameGap: 0.20,
                                            maximumCaptureAge: 0.15)
        let evaluation = VerificationFrameEvaluation(timestamp: 5,
                                                     trackingIsNormal: true,
                                                     hasTrackedFaceAnchor: true,
                                                     faceDetected: true,
                                                     distanceCorrect: true,
                                                     faceAligned: true,
                                                     headPoseAvailable: false,
                                                     headAligned: false)

        let status = engine.evaluate(input: CaptureReadinessInput(evaluation: evaluation,
                                                                  sessionReady: true,
                                                                  calibrationReady: true))

        #expect(status.blockReason == .headPoseUnavailable)
    }

    @Test func rearLiDARReadinessDoesNotRequireFaceAnchor() async throws {
        let engine = CaptureReadinessEngine(requiredStableSampleCount: 1,
                                            maximumFrameGap: 0.20,
                                            maximumCaptureAge: 0.15)
        let evaluation = VerificationFrameEvaluation(timestamp: 6,
                                                     trackingIsNormal: true,
                                                     hasTrackedFaceAnchor: false,
                                                     faceDetected: true,
                                                     distanceCorrect: true,
                                                     faceAligned: true,
                                                     headPoseAvailable: true,
                                                     headAligned: true)

        let status = engine.evaluate(input: CaptureReadinessInput(evaluation: evaluation,
                                                                  sessionReady: true,
                                                                  calibrationReady: true,
                                                                  requiresTrackedFaceAnchor: false))

        #expect(status.isStableReady)
        #expect(evaluation.allChecksPassed(requiresTrackedFaceAnchor: false))
    }

    @Test func rearLiDARReadinessUsesShorterStablePolicy() async throws {
        let engine = CaptureReadinessEngine()
        let first = engine.evaluate(input: rearReadyInput(timestamp: 7.00))
        let second = engine.evaluate(input: rearReadyInput(timestamp: 7.08))
        let third = engine.evaluate(input: rearReadyInput(timestamp: 7.16))

        #expect(!first.isStableReady)
        #expect(!second.isStableReady)
        #expect(third.isStableReady)
        #expect(third.requiredStableSampleCount == RearLiDARCapturePrecisionPolicy.stableSampleCount)
    }

    @Test func rearLiDARPoseInstructionUsesVisionTolerance() async throws {
        let snapshot = HeadPoseSnapshot(rollDegrees: 1.5,
                                        yawDegrees: 1.5,
                                        pitchDegrees: 1.5,
                                        timestamp: 8,
                                        sensor: .liDAR)

        #expect(HeadPoseInstructionBuilder.adjustment(from: snapshot) == nil)
    }

    @Test func rearLiDARAssistToleranceIsWiderThanFinalTolerance() async throws {
        #expect(RearLiDARCapturePrecisionPolicy.alignmentAssistHorizontalTolerance >
            RearLiDARCapturePrecisionPolicy.horizontalCenteringTolerance)
        #expect(RearLiDARCapturePrecisionPolicy.alignmentAssistVerticalTolerance >
            RearLiDARCapturePrecisionPolicy.verticalCenteringTolerance)
    }

    @Test func rearLiDARCenteringAssistPredictsTowardNeutralOffsetWhenPoseIsOff() async throws {
        let snapshot = HeadPoseSnapshot(rollDegrees: 0,
                                        yawDegrees: 12,
                                        pitchDegrees: 0,
                                        timestamp: 9,
                                        sensor: .liDAR)
        let strictOffset = SIMD2<Float>(0.015, 0.002)
        let neutralOffset = SIMD2<Float>(0.004, 0.002)

        let assisted = RearLiDARCenteringAssist.assistedOffset(strictOffset: strictOffset,
                                                               neutralOffset: neutralOffset,
                                                               headPose: snapshot)

        #expect(assisted.x < strictOffset.x)
        #expect(assisted.x > neutralOffset.x)
        #expect(assisted.y == strictOffset.y)
    }

    @Test func rearLiDARAssistedCenteringStillBlocksCaptureUntilHeadAligned() async throws {
        let engine = CaptureReadinessEngine(requiredStableSampleCount: 1,
                                            maximumFrameGap: 0.20,
                                            maximumCaptureAge: 0.15)
        let evaluation = VerificationFrameEvaluation(timestamp: 10,
                                                     trackingIsNormal: true,
                                                     hasTrackedFaceAnchor: false,
                                                     faceDetected: true,
                                                     distanceCorrect: true,
                                                     faceAligned: true,
                                                     headPoseAvailable: true,
                                                     headAligned: false)

        let status = engine.evaluate(input: CaptureReadinessInput(evaluation: evaluation,
                                                                  sessionReady: true,
                                                                  calibrationReady: true,
                                                                  requiresTrackedFaceAnchor: false,
                                                                  policy: .rearLiDAR))

        #expect(status.blockReason == .headNotAligned)
        #expect(!status.isStableReady)
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
                                    headPoseAvailable: true,
                                    headAligned: true)
    }

    private func rearReadyInput(timestamp: TimeInterval) -> CaptureReadinessInput {
        CaptureReadinessInput(evaluation: VerificationFrameEvaluation(timestamp: timestamp,
                                                                      trackingIsNormal: true,
                                                                      hasTrackedFaceAnchor: false,
                                                                      faceDetected: true,
                                                                      distanceCorrect: true,
                                                                      faceAligned: true,
                                                                      headPoseAvailable: true,
                                                                      headAligned: true),
                              sessionReady: true,
                              calibrationReady: true,
                              requiresTrackedFaceAnchor: false,
                              policy: .rearLiDAR)
    }
}
