//
//  VerificationModels.swift
//  MedidorOticaApp
//
//  Modelos de dados para as verificações de medição óptica
//

import Foundation

// Enum para os tipos de verificações
enum VerificationType: Int, CaseIterable, Identifiable {
    case faceDetection = 1
    case distance = 2
    case centering = 3
    case headAlignment = 4
    case frameDetection = 5
    case gaze = 6
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .faceDetection: return "Rosto detectado"
        case .distance: return "Distância correta"
        case .centering: return "Rosto centralizado"
        case .headAlignment: return "Cabeça alinhada"
        case .frameDetection: return "Armação detectada"
        case .gaze: return "Olhar para câmera"
        }
    }
    
    var description: String {
        switch self {
        case .faceDetection: return "Detecta se há um rosto no oval"
        case .distance:
            return "Distância entre \(Int(DistanceLimits.minCm))cm e \(Int(DistanceLimits.maxCm))cm"
        case .centering: return "Rosto centralizado no oval"
        case .headAlignment: return "Cabeça sem inclinação"
        case .frameDetection: return "Detecta uso de armação"
        case .gaze: return "Olhar diretamente para a câmera"
        }
    }
    
    var isOptional: Bool {
        switch self {
        case .frameDetection: return true
        default: return false
        }
    }
}

// Modelo de dados para as verificações
struct Verification: Identifiable {
    let id: Int
    let type: VerificationType
    var isChecked: Bool
    var value: String? = nil
    
    var text: String {
        if let value = value {
            return "\(type.title): \(value)"
        }
        return type.title
    }
}

/// Máquina de estados para controlar o passo atual das verificações
enum VerificationStep: Int {
    case idle = 0
    case faceDetection
    case distance
    case centering
    case headAlignment
    case gaze
    case completed
}

