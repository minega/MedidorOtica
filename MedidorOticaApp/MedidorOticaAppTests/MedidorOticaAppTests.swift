//
//  MedidorOticaAppTests.swift
//  MedidorOticaAppTests
//
//  Created by user942665 on 5/9/25.
//

import Testing
@testable import MedidorOticaApp

struct MedidorOticaAppTests {

    @Test func stateMachineTransitions() async throws {
        let manager = VerificationManager.shared
        manager.reset()

        // Sem rosto detectado
        manager.faceDetected = false
        manager.updateAllVerifications()
        #expect(manager.currentStep == .faceDetection)

        // Após detectar rosto, mas distância incorreta
        manager.faceDetected = true
        manager.distanceCorrect = false
        manager.updateAllVerifications()
        #expect(manager.currentStep == .distance)

        // Distância correta e rosto alinhado
        manager.distanceCorrect = true
        manager.faceAligned = true
        manager.headAligned = true
        manager.gazeCorrect = true
        manager.updateAllVerifications()
        #expect(manager.currentStep == .completed)
    }

}
