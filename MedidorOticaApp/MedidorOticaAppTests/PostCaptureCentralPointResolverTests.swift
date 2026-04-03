//
//  PostCaptureCentralPointResolverTests.swift
//  MedidorOticaAppTests
//
//  Protege a politica do PC para evitar regressao no eixo X.
//

import Testing
import CoreGraphics
@testable import MedidorOticaApp

struct PostCaptureCentralPointResolverTests {
    @Test func ignoresBridgeWhenItDisagreesWithFaceSymmetry() async throws {
        let bounds = NormalizedRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8)
        let candidates = PostCaptureCentralPointResolver.Candidates(
            bridgeX: 0.58,
            captureX: 0.56,
            pupilMidlineX: 0.49,
            faceMidlineX: 0.50
        )

        let resolved = PostCaptureCentralPointResolver.resolveX(using: candidates,
                                                                within: bounds)

        #expect(abs(resolved - 0.50) < 0.03)
        #expect(abs(resolved - 0.58) > 0.04)
    }

    @Test func blendsBridgeWhenItMatchesSymmetry() async throws {
        let bounds = NormalizedRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8)
        let candidates = PostCaptureCentralPointResolver.Candidates(
            bridgeX: 0.505,
            captureX: 0.540,
            pupilMidlineX: 0.495,
            faceMidlineX: 0.500
        )

        let resolved = PostCaptureCentralPointResolver.resolveX(using: candidates,
                                                                within: bounds)

        #expect(abs(resolved - 0.50) < 0.01)
    }

    @Test func ignoresCaptureBiasWhenPhotoGeometryIsAvailable() async throws {
        let bounds = NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let candidates = PostCaptureCentralPointResolver.Candidates(
            bridgeX: nil,
            captureX: 0.56,
            pupilMidlineX: 0.51,
            faceMidlineX: 0.50
        )

        let resolved = PostCaptureCentralPointResolver.resolveX(using: candidates,
                                                                within: bounds)

        #expect(abs(resolved - 0.5067) < 0.005)
        #expect(abs(resolved - 0.56) > 0.04)
    }

    @Test func appliesBridgeAsymmetryWhenItMatchesPhotoGeometry() async throws {
        let bounds = NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let candidates = PostCaptureCentralPointResolver.Candidates(
            bridgeX: 0.514,
            captureX: 0.56,
            pupilMidlineX: 0.51,
            faceMidlineX: 0.50
        )

        let resolved = PostCaptureCentralPointResolver.resolveX(using: candidates,
                                                                within: bounds)

        #expect(resolved > 0.5067)
        #expect(resolved < 0.514)
    }
}
