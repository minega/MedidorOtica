//
//  PostCaptureFarDNPResolverTests.swift
//  MedidorOticaAppTests
//
//  Protege a conversao geometrica estavel de DNP perto para DNP longe.
//

import Testing
import simd
@testable import MedidorOticaApp

struct PostCaptureFarDNPResolverTests {
    @Test func fallsBackToNearValuesWhenEyeGeometryIsMissing() async throws {
        let scale = PostCaptureScale(calibration: .init(horizontalReferenceMM: 100,
                                                        verticalReferenceMM: 80))
        let result = PostCaptureFarDNPResolver.resolve(rightPupilNear: NormalizedPoint(x: 0.65, y: 0.50),
                                                       leftPupilNear: NormalizedPoint(x: 0.35, y: 0.50),
                                                       centralPoint: NormalizedPoint(x: 0.50, y: 0.50),
                                                       scale: scale,
                                                       eyeGeometry: nil)

        #expect(result.rightDNPFar == 15.0)
        #expect(result.leftDNPFar == 15.0)
        #expect(result.confidence == 0)
        #expect(result.confidenceReason != nil)
    }

    @Test func deconvergenceProducesMeaningfulFarOffset() async throws {
        let scale = PostCaptureScale(calibration: .init(horizontalReferenceMM: 100,
                                                        verticalReferenceMM: 80))
        let snapshot = makeSnapshot(leftProjectedCenter: NormalizedPoint(x: 0.34, y: 0.50),
                                    rightProjectedCenter: NormalizedPoint(x: 0.66, y: 0.50),
                                    xScalePerMeter: 8.0,
                                    fixationConfidence: 0.92,
                                    fixationConfidenceReason: nil)

        let result = PostCaptureFarDNPResolver.resolve(rightPupilNear: NormalizedPoint(x: 0.65, y: 0.50),
                                                       leftPupilNear: NormalizedPoint(x: 0.35, y: 0.50),
                                                       centralPoint: NormalizedPoint(x: 0.50, y: 0.50),
                                                       scale: scale,
                                                       eyeGeometry: snapshot)

        #expect(result.rightDNPFar > 15.5)
        #expect(result.leftDNPFar > 15.5)
        #expect((result.rightDNPFar + result.leftDNPFar) > 31.5)
        #expect(result.confidence == 0.92)
        #expect(result.confidenceReason == nil)
    }

    @Test func keepsFarOffsetInsideStableClinicalBand() async throws {
        let scale = PostCaptureScale(calibration: .init(horizontalReferenceMM: 100,
                                                        verticalReferenceMM: 80))
        let snapshot = makeSnapshot(leftProjectedCenter: NormalizedPoint(x: 0.34, y: 0.50),
                                    rightProjectedCenter: NormalizedPoint(x: 0.66, y: 0.50),
                                    xScalePerMeter: 8.0,
                                    fixationConfidence: 0.90,
                                    fixationConfidenceReason: nil)

        let result = PostCaptureFarDNPResolver.resolve(rightPupilNear: NormalizedPoint(x: 0.65, y: 0.50),
                                                       leftPupilNear: NormalizedPoint(x: 0.35, y: 0.50),
                                                       centralPoint: NormalizedPoint(x: 0.50, y: 0.50),
                                                       scale: scale,
                                                       eyeGeometry: snapshot)

        let rightDelta = result.rightDNPFar - 15.0
        let leftDelta = result.leftDNPFar - 15.0
        #expect(rightDelta >= 0.4)
        #expect(rightDelta <= 2.0)
        #expect(leftDelta >= 0.4)
        #expect(leftDelta <= 2.0)
    }

    @Test func keepsFarMeasurementVisibleWithLowConfidenceFixation() async throws {
        let scale = PostCaptureScale(calibration: .init(horizontalReferenceMM: 100,
                                                        verticalReferenceMM: 80))
        let snapshot = makeSnapshot(leftProjectedCenter: NormalizedPoint(x: 0.34, y: 0.50),
                                    rightProjectedCenter: NormalizedPoint(x: 0.66, y: 0.50),
                                    xScalePerMeter: 8.0,
                                    fixationConfidence: 0.40,
                                    fixationConfidenceReason: "Fixacao oscilou.")

        let result = PostCaptureFarDNPResolver.resolve(rightPupilNear: NormalizedPoint(x: 0.65, y: 0.50),
                                                       leftPupilNear: NormalizedPoint(x: 0.35, y: 0.50),
                                                       centralPoint: NormalizedPoint(x: 0.50, y: 0.50),
                                                       scale: scale,
                                                       eyeGeometry: snapshot)

        #expect(result.rightDNPFar > 15.0)
        #expect(result.leftDNPFar > 15.0)
        #expect(result.confidence == 0.40)
        #expect(result.confidenceReason == "Fixacao oscilou.")
    }

    @Test func acceptsRearLiDAREstimatedGeometryWithoutUnavailableFallback() async throws {
        let scale = PostCaptureScale(calibration: .init(horizontalReferenceMM: 100,
                                                        verticalReferenceMM: 80))
        let snapshot = makeRearLiDAREstimatedSnapshot()

        let result = PostCaptureFarDNPResolver.resolve(rightPupilNear: NormalizedPoint(x: 0.65, y: 0.50),
                                                       leftPupilNear: NormalizedPoint(x: 0.35, y: 0.50),
                                                       centralPoint: NormalizedPoint(x: 0.50, y: 0.50),
                                                       scale: scale,
                                                       eyeGeometry: snapshot)

        #expect(result.rightDNPFar > 15.3)
        #expect(result.leftDNPFar > 15.3)
        #expect(result.confidence == 0.68)
        #expect(result.confidenceReason == nil)
    }

    private func makeSnapshot(leftProjectedCenter: NormalizedPoint,
                              rightProjectedCenter: NormalizedPoint,
                              xScalePerMeter: Float,
                              fixationConfidence: Double,
                              fixationConfidenceReason: String?) -> CaptureEyeGeometrySnapshot {
        let leftProjection = CaptureEyeGeometrySnapshot.LinearizedProjection(
            projectedCenter: leftProjectedCenter,
            normalizedXPerMeter: CodableVector3(SIMD3<Float>(xScalePerMeter, 0, 0)),
            normalizedYPerMeter: CodableVector3(SIMD3<Float>(0, 1.5, 0))
        )
        let rightProjection = CaptureEyeGeometrySnapshot.LinearizedProjection(
            projectedCenter: rightProjectedCenter,
            normalizedXPerMeter: CodableVector3(SIMD3<Float>(xScalePerMeter, 0, 0)),
            normalizedYPerMeter: CodableVector3(SIMD3<Float>(0, 1.5, 0))
        )

        return CaptureEyeGeometrySnapshot(
            leftEye: .init(centerCamera: CodableVector3(SIMD3<Float>(-0.031, 0.0, -0.30)),
                           gazeCamera: CodableVector3(SIMD3<Float>(0.10, 0.0, 0.995)),
                           projection: leftProjection),
            rightEye: .init(centerCamera: CodableVector3(SIMD3<Float>(0.031, 0.0, -0.30)),
                            gazeCamera: CodableVector3(SIMD3<Float>(-0.10, 0.0, 0.995)),
                            projection: rightProjection),
            pcCameraPosition: CodableVector3(SIMD3<Float>(0.0, 0.0, -0.34)),
            faceForwardCamera: CodableVector3(SIMD3<Float>(0.0, 0.0, 1.0)),
            fixationConfidence: fixationConfidence,
            fixationConfidenceReason: fixationConfidenceReason,
            strongestGazeDeviation: 0.1
        )
    }

    private func makeRearLiDAREstimatedSnapshot() -> CaptureEyeGeometrySnapshot {
        CaptureEyeGeometrySnapshot(
            leftEye: .init(centerCamera: CodableVector3(SIMD3<Float>(-0.031, 0.0, 0.45)),
                           gazeCamera: CodableVector3(SIMD3<Float>(0.0, 0.0, -1.0)),
                           projection: nil),
            rightEye: .init(centerCamera: CodableVector3(SIMD3<Float>(0.031, 0.0, 0.45)),
                            gazeCamera: CodableVector3(SIMD3<Float>(0.0, 0.0, -1.0)),
                            projection: nil),
            pcCameraPosition: CodableVector3(SIMD3<Float>(0.0, 0.0, 0.45)),
            faceForwardCamera: CodableVector3(SIMD3<Float>(0.0, 0.0, -1.0)),
            fixationConfidence: 0.68,
            fixationConfidenceReason: "Geometria ocular estimada pelo LiDAR traseiro.",
            strongestGazeDeviation: 0
        )
    }
}
