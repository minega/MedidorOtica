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
    case frameTilt = 6
    case gaze = 7
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .faceDetection: return "Rosto detectado"
        case .distance: return "Distância correta"
        case .centering: return "Rosto centralizado"
        case .headAlignment: return "Cabeça alinhada"
        case .frameDetection: return "Armação detectada"
        case .frameTilt: return "Armação alinhada"
        case .gaze: return "Olhar para câmera"
        }
    }
    
    var description: String {
        switch self {
        case .faceDetection: return "Detecta se há um rosto no oval"
        case .distance: return "Distância entre 40cm e 120cm"
        case .centering: return "Rosto centralizado no oval"
        case .headAlignment: return "Cabeça sem inclinação"
        case .frameDetection: return "Detecta uso de armação"
        case .frameTilt: return "Armação corretamente posicionada"
        case .gaze: return "Olhar diretamente para a câmera"
        }
    }
    
    var isOptional: Bool {
        switch self {
        case .frameDetection, .frameTilt: return true
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
