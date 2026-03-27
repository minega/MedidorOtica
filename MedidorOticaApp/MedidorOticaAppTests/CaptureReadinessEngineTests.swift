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
