//
//  Measurement.swift
//  MedidorOticaApp
//
//  Modelo persistido das medicoes de otica.
//

import Foundation
import UIKit

// MARK: - Medicao persistida
/// Representa uma medicao completa salva no historico.
struct Measurement: Identifiable, Codable {
    var id: UUID
    var clientName: String
    /// Numero da ordem de servico associado a medicao.
    var orderNumber: String
    var date: Date
    var distanciaPupilar: Double
    var imageData: Data?
    var postCaptureConfiguration: PostCaptureConfiguration?
    var postCaptureMetrics: PostCaptureMetrics?
    /// Calibracao utilizada para converter valores normalizados em milimetros.
    var postCaptureCalibration: PostCaptureCalibration
    /// Mapa local de escala derivado da malha facial para preservar a precisao.
    var postCaptureLocalCalibration: LocalFaceScaleCalibration?
    /// PC projetado no frame capturado para reduzir vies lateral ao reabrir a medicao.
    var postCaptureCaptureCentralPoint: NormalizedPoint?

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

    // MARK: - Imagem
    func getImage() -> UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Inicializacao
    private enum ImageQuality {
        /// Mantem a foto salva praticamente sem perda visivel.
        static let jpegCompressionQuality: CGFloat = 0.98
    }

    init(clientName: String,
         orderNumber: String,
         capturedImage: UIImage,
         postCaptureConfiguration: PostCaptureConfiguration,
         postCaptureMetrics: PostCaptureMetrics,
         postCaptureCalibration: PostCaptureCalibration,
         postCaptureLocalCalibration: LocalFaceScaleCalibration? = nil,
         postCaptureCaptureCentralPoint: NormalizedPoint? = nil,
         id: UUID = UUID(),
         date: Date = Date()) {
        self.id = id
        self.clientName = clientName
        self.orderNumber = orderNumber
        self.date = date
        self.distanciaPupilar = postCaptureMetrics.distanciaPupilarTotal
        self.postCaptureConfiguration = postCaptureConfiguration
        self.postCaptureMetrics = postCaptureMetrics
        self.postCaptureCalibration = postCaptureCalibration
        self.postCaptureLocalCalibration = postCaptureLocalCalibration
        self.postCaptureCaptureCentralPoint = postCaptureCaptureCentralPoint
        self.imageData = capturedImage.jpegData(compressionQuality: ImageQuality.jpegCompressionQuality)
    }

    // MARK: - Codable
    private enum CodingKeys: String, CodingKey {
        case id
        case clientName
        case orderNumber
        case date
        case distanciaPupilar
        case imageData
        case postCaptureConfiguration
        case postCaptureMetrics
        case postCaptureCalibration
        case postCaptureLocalCalibration
        case postCaptureCaptureCentralPoint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        clientName = try container.decodeIfPresent(String.self, forKey: .clientName) ?? "Cliente"
        orderNumber = try container.decodeIfPresent(String.self, forKey: .orderNumber) ?? ""
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        distanciaPupilar = try container.decodeIfPresent(Double.self, forKey: .distanciaPupilar) ?? 0
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        postCaptureConfiguration = try container.decodeIfPresent(PostCaptureConfiguration.self,
                                                                 forKey: .postCaptureConfiguration)
        postCaptureMetrics = try container.decodeIfPresent(PostCaptureMetrics.self,
                                                           forKey: .postCaptureMetrics)
        postCaptureCalibration = try container.decodeIfPresent(PostCaptureCalibration.self,
                                                               forKey: .postCaptureCalibration) ?? .default
        postCaptureLocalCalibration = try container.decodeIfPresent(LocalFaceScaleCalibration.self,
                                                                    forKey: .postCaptureLocalCalibration)
        postCaptureCaptureCentralPoint = try container.decodeIfPresent(NormalizedPoint.self,
                                                                       forKey: .postCaptureCaptureCentralPoint)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(clientName, forKey: .clientName)
        try container.encode(orderNumber, forKey: .orderNumber)
        try container.encode(date, forKey: .date)
        try container.encode(distanciaPupilar, forKey: .distanciaPupilar)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encodeIfPresent(postCaptureConfiguration, forKey: .postCaptureConfiguration)
        try container.encodeIfPresent(postCaptureMetrics, forKey: .postCaptureMetrics)
        try container.encode(postCaptureCalibration, forKey: .postCaptureCalibration)
        try container.encodeIfPresent(postCaptureLocalCalibration, forKey: .postCaptureLocalCalibration)
        try container.encodeIfPresent(postCaptureCaptureCentralPoint, forKey: .postCaptureCaptureCentralPoint)
    }
}
