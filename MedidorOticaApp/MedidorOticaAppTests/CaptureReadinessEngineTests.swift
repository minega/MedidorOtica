//
//  CaptureReadinessEngineTests.swift
//  MedidorOticaAppTests
//
//  Valida a estabilidade exigida antes da captura final.
//

import Foundation
import CoreGraphics
import ImageIO
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

    @Test func rearDepthDistanceUsesPracticalCaptureRange() async throws {
        #expect(RearDepthDistanceLimits.minCm == 35.0)
        #expect(RearDepthDistanceLimits.maxCm == 55.0)
    }

    @Test func rearMonoDistanceUsesCloseMainCameraRange() async throws {
        #expect(RearMonoBridgeDistanceLimits.minCm == 22.0)
        #expect(RearMonoBridgeDistanceLimits.maxCm == 38.0)
        #expect(RearMonoBridgeDistanceLimits.minCm < RearDepthDistanceLimits.minCm)
    }

    @Test func rearMonoDistanceEstimatorMatchesMeasuredCloseTest() async throws {
        let distance = RearMonoBridgeDistanceEstimator.estimate(faceHeightRatio: 0.346,
                                                               eyeDistanceRatio: nil,
                                                               imageSize: CGSize(width: 2160, height: 3840),
                                                               orientation: .right,
                                                               cameraIntrinsics: nil)

        #expect(abs(distance - 25.0) < 0.5)
    }

    @Test func rearMonoDistanceEstimatorUsesEyesToStabilizeFaceBounds() async throws {
        let distance = RearMonoBridgeDistanceEstimator.estimate(faceHeightRatio: 0.346,
                                                               eyeDistanceRatio: 0.23,
                                                               imageSize: CGSize(width: 2160, height: 3840),
                                                               orientation: .right,
                                                               cameraIntrinsics: nil)

        #expect(distance > 24.0)
        #expect(distance < 25.8)
    }

    @Test func rearMonoProjectionConvertsCenterOffsetToEstimatedCentimeters() async throws {
        var intrinsics = matrix_identity_float3x3
        intrinsics.columns.0.x = 3200
        intrinsics.columns.1.y = 3200

        let offset = RearMonoBridgeProjectionEstimator.offsetCentimeters(
            normalizedOffset: SIMD2<Float>(0.04, -0.02),
            imageSize: CGSize(width: 2160, height: 3840),
            orientation: .right,
            cameraIntrinsics: intrinsics,
            distanceCm: 25
        )

        #expect(abs(offset.x - 0.675) < 0.05)
        #expect(abs(offset.y + 0.600) < 0.05)
    }

    @Test func rearDepthModeMessagesExplainLiDARToggle() async throws {
        #expect(RearDepthMode.liDAR.sensorName == "LiDAR")
        #expect(RearDepthMode.estimatedDepth.sensorName == "Depth")
        #expect(RearDepthMode.monoBridge.sensorName == "Mono")
        #expect(RearDepthMode.liDAR.toggleMessage.contains("LiDAR ativo"))
        #expect(RearDepthMode.estimatedDepth.toggleMessage.contains("LiDAR desligado"))
        #expect(RearDepthMode.monoBridge.toggleMessage.contains("ponte"))
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

    @Test func rearCameraPoseInstructionTellsUserToMovePhone() async throws {
        let snapshot = HeadPoseSnapshot(rollDegrees: 0,
                                        yawDegrees: 8,
                                        pitchDegrees: 0,
                                        timestamp: 8.2,
                                        sensor: .rearDepth)
        let adjustment = HeadPoseInstructionBuilder.adjustment(from: snapshot)
        let instruction = adjustment?.instruction(for: .rearDepth) ?? ""

        #expect(instruction.contains("celular"))
        #expect(!instruction.contains("cabeca"))
    }

    @Test func rearLiDARPoseInstructionAlsoTellsUserToMovePhone() async throws {
        let snapshot = HeadPoseSnapshot(rollDegrees: -8,
                                        yawDegrees: 0,
                                        pitchDegrees: 0,
                                        timestamp: 8.25,
                                        sensor: .liDAR)
        let adjustment = HeadPoseInstructionBuilder.adjustment(from: snapshot)
        let instruction = adjustment?.instruction(for: .liDAR) ?? ""

        #expect(instruction.contains("celular"))
        #expect(!instruction.contains("cabeca"))
    }

    @Test func frontCameraPoseInstructionStillTargetsHead() async throws {
        let snapshot = HeadPoseSnapshot(rollDegrees: 0,
                                        yawDegrees: 8,
                                        pitchDegrees: 0,
                                        timestamp: 8.3,
                                        sensor: .trueDepth)
        let adjustment = HeadPoseInstructionBuilder.adjustment(from: snapshot)
        let instruction = adjustment?.instruction(for: .trueDepth) ?? ""

        #expect(instruction.contains("cabeca"))
        #expect(!instruction.contains("celular"))
    }

    @Test func rearDepthPoseInstructionUsesDedicatedTolerance() async throws {
        let snapshot = HeadPoseSnapshot(rollDegrees: 2.2,
                                        yawDegrees: 2.2,
                                        pitchDegrees: 2.4,
                                        timestamp: 8.5,
                                        sensor: .rearDepth)

        #expect(HeadPoseInstructionBuilder.adjustment(from: snapshot) == nil)
    }

    @Test func rearMonoPoseInstructionUsesDedicatedTolerance() async throws {
        let snapshot = HeadPoseSnapshot(rollDegrees: 2.0,
                                        yawDegrees: 2.2,
                                        pitchDegrees: 2.3,
                                        timestamp: 8.7,
                                        sensor: .rearMonoBridge)

        #expect(HeadPoseInstructionBuilder.adjustment(from: snapshot) == nil)
    }

    @Test func rearMonoPoseDoesNotInventMissingAxes() async throws {
        let landmarks = rearMonoPoseLandmarks(lowerNosePoint: nil,
                                              lowerFacePoint: nil)

        let snapshot = RearMonoBridgePoseEstimator.makeHeadPose(visionRoll: nil,
                                                                visionYaw: nil,
                                                                visionPitch: nil,
                                                                landmarks: landmarks,
                                                                timestamp: 8.8)

        #expect(snapshot == nil)
    }

    @Test func rearMonoPoseUsesGeometricAxesWhenVisionAnglesAreMissing() async throws {
        let landmarks = rearMonoPoseLandmarks()

        let snapshot = RearMonoBridgePoseEstimator.makeHeadPose(visionRoll: nil,
                                                                visionYaw: nil,
                                                                visionPitch: nil,
                                                                landmarks: landmarks,
                                                                timestamp: 8.9)

        #expect(snapshot != nil)
        #expect(abs(snapshot?.rollDegrees ?? 99) < 0.2)
        #expect(abs(snapshot?.yawDegrees ?? 99) < 0.2)
        #expect(abs(snapshot?.pitchDegrees ?? 99) < 0.2)
    }

    @Test func rearMonoPitchDoesNotLockOnNeutralFaceBoxBias() async throws {
        let eyeY: CGFloat = 0.385
        let landmarks = rearMonoPoseLandmarks(leftEye: NormalizedPoint(x: 0.40, y: eyeY),
                                              rightEye: NormalizedPoint(x: 0.60, y: eyeY),
                                              lowerNosePoint: NormalizedPoint(x: 0.50, y: eyeY + 0.11),
                                              lowerFacePoint: NormalizedPoint(x: 0.50, y: eyeY + 0.28))

        let snapshot = RearMonoBridgePoseEstimator.makeHeadPose(visionRoll: nil,
                                                                visionYaw: nil,
                                                                visionPitch: nil,
                                                                landmarks: landmarks,
                                                                timestamp: 8.92)

        #expect(snapshot != nil)
        #expect(abs(snapshot?.pitchDegrees ?? 99) < RearMonoBridgeCapturePrecisionPolicy.pitchToleranceDegrees)
        let adjustment = snapshot.flatMap { HeadPoseInstructionBuilder.adjustment(from: $0) }
        #expect(adjustment == nil)
    }

    @Test func rearMonoPitchStillBlocksActualTiltAfterBoxBiasFix() async throws {
        let eyeY: CGFloat = 0.385
        let landmarks = rearMonoPoseLandmarks(leftEye: NormalizedPoint(x: 0.40, y: eyeY),
                                              rightEye: NormalizedPoint(x: 0.60, y: eyeY),
                                              lowerNosePoint: NormalizedPoint(x: 0.50, y: eyeY + 0.055),
                                              lowerFacePoint: NormalizedPoint(x: 0.50, y: eyeY + 0.16))

        let snapshot = RearMonoBridgePoseEstimator.makeHeadPose(visionRoll: nil,
                                                                visionYaw: nil,
                                                                visionPitch: nil,
                                                                landmarks: landmarks,
                                                                timestamp: 8.93)

        #expect(snapshot != nil)
        #expect(abs(snapshot?.pitchDegrees ?? 0) > RearMonoBridgeCapturePrecisionPolicy.pitchToleranceDegrees)
        let adjustment = snapshot.flatMap { HeadPoseInstructionBuilder.adjustment(from: $0) }
        #expect(adjustment == .pitchDown(4))
    }

    @Test func rearMonoPitchDoesNotIgnoreGeometryWhenVisionIsAligned() async throws {
        let resolved = RearMonoBridgePoseEstimator.resolvedPitchAxis(
            vision: 0,
            geometry: RearMonoBridgePoseAxisEstimate(degrees: -4.0, confidence: 0.90)
        )

        #expect(abs((resolved ?? 0) + 4.0) < 0.1)
    }

    @Test func rearMonoPoseUsesLargestErrorWhenVisionConflictsWithGeometry() async throws {
        let landmarks = rearMonoPoseLandmarks()

        let snapshot = RearMonoBridgePoseEstimator.makeHeadPose(visionRoll: 0,
                                                                visionYaw: 16,
                                                                visionPitch: 0,
                                                                landmarks: landmarks,
                                                                timestamp: 8.95)

        #expect(snapshot != nil)
        #expect(abs(snapshot?.yawDegrees ?? 0) >= 15)
        let adjustment = snapshot.flatMap { HeadPoseInstructionBuilder.adjustment(from: $0) }
        #expect(adjustment == .yawRight(16))
    }

    @Test func rearMonoPoseRejectsClearlyTurnedHead() async throws {
        let landmarks = rearMonoPoseLandmarks(lowerNosePoint: NormalizedPoint(x: 0.56, y: 0.57))

        let snapshot = RearMonoBridgePoseEstimator.makeHeadPose(visionRoll: 0,
                                                                visionYaw: nil,
                                                                visionPitch: 0,
                                                                landmarks: landmarks,
                                                                timestamp: 8.96)

        #expect(snapshot != nil)
        #expect(abs(snapshot?.yawDegrees ?? 0) > RearMonoBridgeCapturePrecisionPolicy.yawToleranceDegrees)
    }

    @Test func rearMonoPoseRejectsWeakEyeGeometry() async throws {
        let landmarks = rearMonoPoseLandmarks(leftEye: NormalizedPoint(x: 0.49, y: 0.46),
                                              rightEye: NormalizedPoint(x: 0.51, y: 0.46))

        let snapshot = RearMonoBridgePoseEstimator.makeHeadPose(visionRoll: 0,
                                                                visionYaw: 0,
                                                                visionPitch: 0,
                                                                landmarks: landmarks,
                                                                timestamp: 8.97)

        #expect(snapshot == nil)
    }

    @Test func rearLiDARAssistToleranceIsWiderThanFinalTolerance() async throws {
        #expect(RearLiDARCapturePrecisionPolicy.alignmentAssistHorizontalTolerance >
            RearLiDARCapturePrecisionPolicy.horizontalCenteringTolerance)
        #expect(RearLiDARCapturePrecisionPolicy.alignmentAssistVerticalTolerance >
            RearLiDARCapturePrecisionPolicy.verticalCenteringTolerance)
    }

    @Test func rearDepthAssistToleranceIsWiderThanFinalTolerance() async throws {
        #expect(RearDepthCapturePrecisionPolicy.alignmentAssistHorizontalTolerance >
            RearDepthCapturePrecisionPolicy.horizontalCenteringTolerance)
        #expect(RearDepthCapturePrecisionPolicy.alignmentAssistVerticalTolerance >
            RearDepthCapturePrecisionPolicy.verticalCenteringTolerance)
    }

    @Test func rearMonoAssistToleranceIsWiderThanFinalTolerance() async throws {
        #expect(RearMonoBridgeCapturePrecisionPolicy.alignmentAssistHorizontalTolerance >
            RearMonoBridgeCapturePrecisionPolicy.horizontalCenteringTolerance)
        #expect(RearMonoBridgeCapturePrecisionPolicy.alignmentAssistVerticalTolerance >
            RearMonoBridgeCapturePrecisionPolicy.verticalCenteringTolerance)
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

    @Test func rearDepthCenteringAssistPredictsTowardNeutralOffsetWhenPoseIsOff() async throws {
        let snapshot = HeadPoseSnapshot(rollDegrees: 0,
                                        yawDegrees: 14,
                                        pitchDegrees: 0,
                                        timestamp: 9.5,
                                        sensor: .rearDepth)
        let strictOffset = SIMD2<Float>(0.018, 0.003)
        let neutralOffset = SIMD2<Float>(0.005, 0.003)

        let assisted = RearDepthCenteringAssist.assistedOffset(strictOffset: strictOffset,
                                                               neutralOffset: neutralOffset,
                                                               headPose: snapshot)

        #expect(assisted.x < strictOffset.x)
        #expect(assisted.x > neutralOffset.x)
        #expect(assisted.y == strictOffset.y)
    }

    @Test func rearMonoCenteringAssistPredictsTowardNeutralOffsetWhenPoseIsOff() async throws {
        let snapshot = HeadPoseSnapshot(rollDegrees: 0,
                                        yawDegrees: 14,
                                        pitchDegrees: 0,
                                        timestamp: 9.7,
                                        sensor: .rearMonoBridge)
        let strictOffset = SIMD2<Float>(0.040, 0.006)
        let neutralOffset = SIMD2<Float>(0.010, 0.006)

        let assisted = RearMonoBridgeCenteringAssist.assistedOffset(strictOffset: strictOffset,
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

    @Test func rearDepthReadinessDoesNotRequireFaceAnchorAndUsesDedicatedPolicy() async throws {
        let engine = CaptureReadinessEngine()
        let first = engine.evaluate(input: rearDepthReadyInput(timestamp: 11.00))
        let second = engine.evaluate(input: rearDepthReadyInput(timestamp: 11.05))
        let third = engine.evaluate(input: rearDepthReadyInput(timestamp: 11.10))
        let fourth = engine.evaluate(input: rearDepthReadyInput(timestamp: 11.15))

        #expect(!first.isStableReady)
        #expect(!second.isStableReady)
        #expect(!third.isStableReady)
        #expect(fourth.isStableReady)
        #expect(fourth.requiredStableSampleCount == RearDepthCapturePrecisionPolicy.stableSampleCount)
    }

    @Test func rearMonoReadinessDoesNotRequireFaceAnchorAndUsesDedicatedPolicy() async throws {
        let engine = CaptureReadinessEngine()
        let first = engine.evaluate(input: rearMonoReadyInput(timestamp: 12.00))
        let second = engine.evaluate(input: rearMonoReadyInput(timestamp: 12.05))
        let third = engine.evaluate(input: rearMonoReadyInput(timestamp: 12.10))
        let fourth = engine.evaluate(input: rearMonoReadyInput(timestamp: 12.15))

        #expect(!first.isStableReady)
        #expect(!second.isStableReady)
        #expect(!third.isStableReady)
        #expect(fourth.isStableReady)
        #expect(fourth.requiredStableSampleCount == RearMonoBridgeCapturePrecisionPolicy.stableSampleCount)
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

    private func rearDepthReadyInput(timestamp: TimeInterval) -> CaptureReadinessInput {
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
                              policy: .rearDepth)
    }

    private func rearMonoReadyInput(timestamp: TimeInterval) -> CaptureReadinessInput {
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
                              policy: .rearMonoBridge)
    }

    private func rearMonoPoseLandmarks(leftEye: NormalizedPoint = NormalizedPoint(x: 0.40, y: 0.46),
                                       rightEye: NormalizedPoint = NormalizedPoint(x: 0.60, y: 0.46),
                                       lowerNosePoint: NormalizedPoint? = NormalizedPoint(x: 0.50, y: 0.57),
                                       lowerFacePoint: NormalizedPoint? = NormalizedPoint(x: 0.50, y: 0.74)) -> RearMonoBridgePoseLandmarks {
        RearMonoBridgePoseLandmarks(imageLeftEyeCenter: leftEye,
                                    imageRightEyeCenter: rightEye,
                                    lowerNosePoint: lowerNosePoint,
                                    lowerFacePoint: lowerFacePoint,
                                    faceBounds: NormalizedRect(x: 0.25,
                                                               y: 0.25,
                                                               width: 0.50,
                                                               height: 0.50))
    }
}
