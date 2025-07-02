//
//  Measurement.swift
//  MedidorOticaApp
//
//  Modelo de dados para armazenar medições de ótica
//

import Foundation
import UIKit

struct Measurement: Identifiable, Codable {
    var id = UUID()
    var clientName: String
    var date: Date
    var distanciaPupilar: Double
    var imageData: Data?
    
    // Propriedades computadas
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: date)
    }
    
    var formattedDistanciaPupilar: String {
        return String(format: "%.1f mm", distanciaPupilar)
    }
    
    // Método para recuperar a imagem
    func getImage() -> UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }
    
    // Inicializador com UIImage
    init(clientName: String, distanciaPupilar: Double, image: UIImage? = nil) {
        self.clientName = clientName
        self.date = Date()
        self.distanciaPupilar = distanciaPupilar
        
        if let image = image, let data = image.jpegData(compressionQuality: 0.7) {
            self.imageData = data
        }
    }
}
