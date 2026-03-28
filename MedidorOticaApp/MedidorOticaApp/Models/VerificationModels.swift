//
//  VerificationModels.swift
//  MedidorOticaApp
//
//  Modelos usados pelo fluxo de verificacoes da captura.
//

import Foundation

// MARK: - Tipo de verificacao
enum VerificationType: Int, CaseIterable, Identifiable {
    case faceDetection = 1
    case distance = 2
    case centering = 3
    case headAlignment = 4

    var id: Int { rawValue }

    /// Indica se a verificacao e opcional para o fluxo atual.
    var isOptional: Bool {
        Self.optionalTypes.contains(self)
    }

    /// Conjunto de verificacoes opcionais.
    private static let optionalTypes: Set<VerificationType> = []

    /// Texto completo usado em telas detalhadas.
    var title: String {
        switch self {
        case .faceDetection:
            return "Rosto no oval"
        case .distance:
            return "Distancia ideal"
        case .centering:
            return "Nariz no centro"
        case .headAlignment:
            return "Cabeca nos 3 eixos"
        }
    }

    /// Explicacao resumida do que a etapa valida.
    var description: String {
        switch self {
        case .faceDetection:
            return "Rosto inteiro dentro do oval"
        case .distance:
            return "Distancia entre \(Int(DistanceLimits.minCm))cm e \(Int(DistanceLimits.maxCm))cm"
        case .centering:
            return "Nariz alinhado ao centro do oval"
        case .headAlignment:
            return "Rosto reto em roll, yaw e pitch"
        }
    }

    /// Texto curto para o menu lateral da camera.
    var menuTitle: String {
        switch self {
        case .faceDetection:
            return "Rosto"
        case .distance:
            return "28-45 cm"
        case .centering:
            return "Nariz"
        case .headAlignment:
            return "Cabeca"
        }
    }
}

// MARK: - Item do menu
struct Verification: Identifiable {
    let id: Int
    let type: VerificationType
    var isChecked: Bool
    var value: String? = nil

    var text: String {
        if let value {
            return "\(type.title): \(value)"
        }
        return type.title
    }
}

// MARK: - Passo atual
enum VerificationStep: Int {
    case idle = 0
    case faceDetection
    case distance
    case centering
    case headAlignment
    case completed
}
