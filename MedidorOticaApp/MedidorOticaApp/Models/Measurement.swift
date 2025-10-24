//
//  Measurement.swift
//  MedidorOticaApp
//
//  Modelo de dados para armazenar medições de ótica
//

import Foundation
import UIKit

// MARK: - Medição Persistida
/// Representa uma medição completa salva no histórico.
struct Measurement: Identifiable, Codable {
    var id: UUID
    var clientName: String
    var date: Date
    var distanciaPupilar: Double
    var imageData: Data?
    var postCaptureConfiguration: PostCaptureConfiguration?
    var postCaptureMetrics: PostCaptureMetrics?

    // MARK: - Computados
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: date)
    }

    var formattedDistanciaPupilar: String {
        let value = postCaptureMetrics?.distanciaPupilarTotal ?? distanciaPupilar
        return String(format: "%.1f mm", value)
    }

    var formattedBridge: String {
        guard let ponte = postCaptureMetrics?.ponte else { return "-" }
        return String(format: "%.1f mm", ponte)
    }

    // MARK: - Acesso à Imagem
    func getImage() -> UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Inicialização
    init(clientName: String,
         capturedImage: UIImage,
         postCaptureConfiguration: PostCaptureConfiguration,
         postCaptureMetrics: PostCaptureMetrics,
         id: UUID = UUID(),
         date: Date = Date()) {
        self.id = id
        self.clientName = clientName
        self.date = date
        self.distanciaPupilar = postCaptureMetrics.distanciaPupilarTotal
        self.postCaptureConfiguration = postCaptureConfiguration
        self.postCaptureMetrics = postCaptureMetrics
        self.imageData = capturedImage.jpegData(compressionQuality: 0.75)
    }

    // MARK: - Codable
    private enum CodingKeys: String, CodingKey {
        case id
        case clientName
        case date
        case distanciaPupilar
        case imageData
        case postCaptureConfiguration
        case postCaptureMetrics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        clientName = try container.decodeIfPresent(String.self, forKey: .clientName) ?? "Cliente"
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        distanciaPupilar = try container.decodeIfPresent(Double.self, forKey: .distanciaPupilar) ?? 0
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        postCaptureConfiguration = try container.decodeIfPresent(PostCaptureConfiguration.self, forKey: .postCaptureConfiguration)
        postCaptureMetrics = try container.decodeIfPresent(PostCaptureMetrics.self, forKey: .postCaptureMetrics)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(clientName, forKey: .clientName)
        try container.encode(date, forKey: .date)
        try container.encode(distanciaPupilar, forKey: .distanciaPupilar)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encodeIfPresent(postCaptureConfiguration, forKey: .postCaptureConfiguration)
        try container.encodeIfPresent(postCaptureMetrics, forKey: .postCaptureMetrics)
    }
}
