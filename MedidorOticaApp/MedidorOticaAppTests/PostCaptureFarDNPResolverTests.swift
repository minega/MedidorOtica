//
//  PostCaptureFarDNPResolverTests.swift
//  MedidorOticaAppTests
//
//  Protege a conversao geometrica de DNP perto para DNP longe.
//

import Testing
import simd
@testable import MedidorOticaApp

struct PostCaptureFarDNPResolverTests {
    @Test func fallsBackToNearValuesWhenEyeGeometryIsMissing() async throws {
        let result = PostCaptureFarDNPResolver.resolve(rightDNPNear: 31.4,
                                                       leftDNPNear: 30.9,
                                                       eyeGeometry: nil)

        #expect(result.rightDNPFar == 31.4)
        #expect(result.leftDNPFar == 30.9)
        #expect(result.confidence == 0)
        #expect(result.confidenceReason != nil)
    }

    @Test func deconvergenceIncreasesTotalDNPUsingSameCaptureGeometry() async throws {
        let snapshot = makeSnapshot(leftEyeCenter: SIMD3<Float>(-0.031, 0.0, -0.30),
                                    rightEyeCenter: SIMD3<Float>(0.031, 0.0, -0.30),
                                    leftGaze: SIMD3<Float>(0.08, 0.0, -1.0),
                                    rightGaze: SIMD3<Float>(-0.08, 0.0, -1.0),
                                    pcCameraPosition: SIMD3<Float>(0.0, 0.0, -0.36),
                                    fixationConfidence: 0.92,
                                    fixationConfidenceReason: nil)

        let result = PostCaptureFarDNPResolver.resolve(rightDNPNear: 31.2,
                                                       leftDNPNear: 30.8,
                                                       eyeGeometry: snapshot)

        #expect(result.rightDNPFar >= 31.2)
        #expect(result.leftDNPFar >= 30.8)
        #expect((result.rightDNPFar + result.leftDNPFar) > 62.0)
        #expect(result.confidence == 0.92)
        #expect(result.confidenceReason == nil)
    }

    @Test func preservesFarMeasurementButFlagsLowConfidenceFixation() async throws {
        let snapshot = makeSnapshot(leftEyeCenter: SIMD3<Float>(-0.03, 0.0, -0.30),
                                    rightEyeCenter: SIMD3<Float>(0.03, 0.0, -0.30),
                                    leftGaze: SIMD3<Float>(0.06, 0.0, -1.0),
                                    rightGaze: SIMD3<Float>(-0.06, 0.0, -1.0),
                                    pcCameraPosition: SIMD3<Float>(0.0, 0.0, -0.35),
                                    fixationConfidence: 0.40,
                                    fixationConfidenceReason: "Fixacao oscilou.")

        let result = PostCaptureFarDNPResolver.resolve(rightDNPNear: 31.0,
                                                       leftDNPNear: 31.0,
                                                       eyeGeometry: snapshot)

        #expect(result.rightDNPFar > 31.0)
        #expect(result.leftDNPFar > 31.0)
        #expect(result.confidence == 0.40)
        #expect(result.confidenceReason == "Fixacao oscilou.")
    }

    private func makeSnapshot(leftEyeCenter: SIMD3<Float>,
                              rightEyeCenter: SIMD3<Float>,
                              leftGaze: SIMD3<Float>,
                              rightGaze: SIMD3<Float>,
                              pcCameraPosition: SIMD3<Float>,
                              fixationConfidence: Double,
                              fixationConfidenceReason: String?) -> CaptureEyeGeometrySnapshot {
        CaptureEyeGeometrySnapshot(
            leftEye: .init(centerCamera: CodableVector3(leftEyeCenter),
                           gazeCamera: CodableVector3(leftGaze)),
            rightEye: .init(centerCamera: CodableVector3(rightEyeCenter),
                            gazeCamera: CodableVector3(rightGaze)),
            pcCameraPosition: CodableVector3(pcCameraPosition),
            fixationConfidence: fixationConfidence,
            fixationConfidenceReason: fixationConfidenceReason,
            strongestGazeDeviation: 0.1
        )
    }
}
