//
//  PostCaptureMetricsTests.swift
//  MedidorOticaAppTests
//
//  Protege a apresentacao e os totais da DNP validada no resumo final.
//

import Testing
@testable import MedidorOticaApp

struct PostCaptureMetricsTests {
    @Test func validatedTotalsPreferValidatedReferenceOverEyeSummaries() async throws {
        let metrics = PostCaptureMetrics(
            rightEye: EyeMeasurementSummary(horizontalMaior: 50,
                                            verticalMaior: 30,
                                            dnp: 31.0,
                                            alturaPupilar: 18),
            leftEye: EyeMeasurementSummary(horizontalMaior: 50,
                                           verticalMaior: 30,
                                           dnp: 30.0,
                                           alturaPupilar: 18),
            ponte: 18,
            validatedDNP: PostCaptureDNPReference(rightNear: 32.4,
                                                  leftNear: 31.6,
                                                  rightFar: 33.1,
                                                  leftFar: 32.3)
        )

        #expect(metrics.distanciaPupilarTotal == 64.0)
        #expect(metrics.distanciaPupilarTotalFar == 65.4)
    }

    @Test func summaryUsesValidatedTitlesWhenConvergenceFails() async throws {
        let metrics = PostCaptureMetrics(
            rightEye: EyeMeasurementSummary(horizontalMaior: 50,
                                            verticalMaior: 30,
                                            dnp: 31.0,
                                            alturaPupilar: 18),
            leftEye: EyeMeasurementSummary(horizontalMaior: 50,
                                           verticalMaior: 30,
                                           dnp: 30.0,
                                           alturaPupilar: 18),
            ponte: 18,
            validatedDNP: PostCaptureDNPReference(rightNear: 32.4,
                                                  leftNear: 31.6,
                                                  rightFar: 33.1,
                                                  leftFar: 32.3),
            noseDNP: PostCaptureDNPReference(rightNear: 32.8,
                                             leftNear: 31.4,
                                             rightFar: 33.5,
                                             leftFar: 32.1),
            bridgeDNP: PostCaptureDNPReference(rightNear: 31.9,
                                               leftNear: 32.0,
                                               rightFar: 32.7,
                                               leftFar: 32.8),
            dnpConverged: false,
            dnpConvergenceToleranceMM: 0.5,
            dnpConvergenceReason: "Nariz e ponte divergiram.",
            farDNPConfidence: 0.9,
            farDNPConfidenceReason: nil
        )

        let entries = metrics.summaryEntries()

        #expect(entries.first(where: { $0.id == "dnpPerto" })?.title == "DNP validada perto (revise)")
        #expect(entries.first(where: { $0.id == "dnpLonge" })?.title == "DNP validada longe")
    }
}
