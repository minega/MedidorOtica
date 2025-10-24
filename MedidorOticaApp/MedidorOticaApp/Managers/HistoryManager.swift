//
//  HistoryManager.swift
//  MedidorOticaApp
//
//  Gerenciador otimizado para histórico de medições
//

import Foundation
import Combine
import os.log
import UIKit

/// Gerenciador responsável por armazenar e recuperar o histórico de medições
extension OSLog {
    static let historyLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.medidorotica.app",
        category: "HistoryManager"
    )
}

@MainActor
final class HistoryManager: ObservableObject {
    // MARK: - Singleton
    
    static let shared = HistoryManager()
    
    // MARK: - Properties
    
    @Published private(set) var measurements: [Measurement] = []
    
    private let fileManager: FileManager
    private let saveDirectory: URL
    private let saveFile: URL
    private let maxStorageSize: Int64 // 10MB em bytes
    private let queue = DispatchQueue(
        label: "com.medidorotica.history.queue",
        qos: .userInitiated,
        attributes: .concurrent
    )
    
    private var saveTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        
        // Configura o diretório de salvamento
        let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        
        saveDirectory = documentsDirectory.appendingPathComponent("Measurements")
        saveFile = saveDirectory.appendingPathComponent("measurements.json")
        maxStorageSize = 10 * 1024 * 1024 // 10MB
        
        // Cria o diretório se não existir
        try? fileManager.createDirectory(
            at: saveDirectory,
            withIntermediateDirectories: true
        )
        
        // Carrega as medições iniciais
        Task {
            await loadMeasurements()
            await cleanupOldMeasurementsIfNeeded()
        }
        
        // Configura observadores
        setupObservers()
    }
    
    deinit {
        saveTask?.cancel()
        cancellables.forEach { $0.cancel() }
    }
    
    // MARK: - Public Methods
    
    /// Adiciona uma nova medição ao histórico
    /// - Parameter measurement: A medição a ser adicionada
    func addMeasurement(_ measurement: Measurement) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else { return }

                let startTime = Date()
                Task { @MainActor in
                    self.measurements.insert(measurement, at: 0)
                    self.scheduleSave()
                }

                let duration = Date().timeIntervalSince(startTime)
                os_log("Medição adicionada em %.4f segundos",
                       log: .historyLog,
                       type: .debug,
                       duration)

                continuation.resume()
            }
        }
    }

    /// Atualiza uma medição existente preservando o ID original
    /// - Parameter measurement: Medição atualizada
    func updateMeasurement(_ measurement: Measurement) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else { return continuation.resume() }

                Task { @MainActor in
                    guard let index = self.measurements.firstIndex(where: { $0.id == measurement.id }) else {
                        continuation.resume()
                        return
                    }

                    self.measurements[index] = measurement
                    self.scheduleSave()
                    continuation.resume()
                }
            }
        }
    }
    
    /// Remove uma medição do histórico pelo índice
    /// - Parameter index: O índice da medição a ser removida
    func removeMeasurement(at index: Int) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else { return continuation.resume() }

                Task { @MainActor in
                    guard self.measurements.indices.contains(index) else {
                        return continuation.resume()
                    }

                    self.measurements.remove(at: index)
                    self.scheduleSave()
                    continuation.resume()
                }
            }
        }
    }
    
    /// Remove uma medição específica do histórico pelo ID
    /// - Parameter id: O ID da medição a ser removida
    func removeMeasurement(id: UUID) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else { return continuation.resume() }

                Task { @MainActor in
                    guard let index = self.measurements.firstIndex(where: { $0.id == id }) else {
                        return continuation.resume()
                    }

                    self.measurements.remove(at: index)
                    self.scheduleSave()
                    continuation.resume()
                }
            }
        }
    }
    
    /// Limpa todo o histórico de medições
    func clearHistory() async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else { return continuation.resume() }

                Task { @MainActor in
                    self.measurements.removeAll()
                    self.scheduleSave()
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Observa notificações do app para salvar antes de encerrar
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.saveMeasurements()
                }
            }
            .store(in: &cancellables)
            
        // Observa mudanças no armazenamento
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.cleanupOldMeasurementsIfNeeded()
                }
            }
            .store(in: &cancellables)
    }
    
    private func scheduleSave() {
        saveTask?.cancel()
        
        saveTask = Task {
            // Aguarda 1 segundo de inatividade antes de salvar
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await saveMeasurements()
        }
    }
    
    private func loadMeasurements() async {
        let saveFile = saveFile
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [weak self, saveFile] in
                guard let self else { return }
                let fm = FileManager.default

                let startTime = Date()

                guard fm.fileExists(atPath: saveFile.path) else {
                    return continuation.resume()
                }

                do {
                    let data = try Data(contentsOf: saveFile)
                    let decoder = JSONDecoder()
                    let loadedMeasurements = try decoder.decode([Measurement].self, from: data)

                    Task { @MainActor in
                        self.measurements = loadedMeasurements
                        let duration = Date().timeIntervalSince(startTime)
                        os_log("Carregadas %d medições em %.4f segundos",
                               log: .historyLog,
                               type: .info,
                               loadedMeasurements.count,
                               duration)
                        continuation.resume()
                    }
                } catch {
                    os_log("Falha ao carregar medições: %{public}@",
                           log: .historyLog,
                           type: .error,
                           error.localizedDescription)
                    continuation.resume()
                }
            }
        }
    }
    
    private func saveMeasurements() async {
        let measurementsToSave = self.measurements
        let saveDir = saveDirectory
        let saveFile = saveFile
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async(flags: .barrier) { [measurementsToSave, saveDir, saveFile] in
                let fm = FileManager.default
                let startTime = Date()

                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(measurementsToSave)
                    
                    // Cria um arquivo temporário primeiro
                    let tempURL = saveDir
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("tmp")

                    try data.write(to: tempURL, options: [.atomic])

                    // Move o arquivo temporário para o local final
                    if fm.fileExists(atPath: saveFile.path) {
                        try fm.removeItem(at: saveFile)
                    }
                    try fm.moveItem(at: tempURL, to: saveFile)

                    // Configura proteção de dados
                    try (saveFile as NSURL).setResourceValue(
                        URLFileProtection.complete,
                        forKey: .fileProtectionKey
                    )

                    let duration = Date().timeIntervalSince(startTime)
                    os_log("Salvas %d medições em %.4f segundos",
                           log: .historyLog,
                           type: .debug,
                           measurementsToSave.count,
                           duration)
                    
                } catch {
                    os_log("Falha ao salvar medições: %{public}@",
                           log: .historyLog,
                           type: .error,
                           error.localizedDescription)
                }
                
                continuation.resume()
            }
        }
    }
    
    private func cleanupOldMeasurementsIfNeeded() async {
        let dir = saveDirectory
        let limit = maxStorageSize
        let current = measurements
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async(flags: .barrier) { [weak self, dir, limit, current] in
                guard let self else { return }
                let fm = FileManager.default

                guard let directorySize = try? fm.sizeOfDirectory(at: dir) else {
                    return continuation.resume()
                }

                guard directorySize > limit else {
                    return continuation.resume()
                }

                let sortedMeasurements = current.sorted(by: { $0.date < $1.date })
                var remainingSize = directorySize
                var index = 0
                
                // Remove as medições mais antigas até ficar abaixo do limite
                while remainingSize > limit / 2 && index < sortedMeasurements.count {
                    // Estimativa do tamanho de cada medição (aproximada)
                    let measurementSize = 1024 // 1KB por medição (estimativa)
                    remainingSize -= Int64(measurementSize)
                    index += 1
                }
                
                // Atualiza a lista de medições
                if index > 0 {
                    let idsToRemove = Set(sortedMeasurements.prefix(index).map { $0.id })
                    Task { @MainActor in
                        self.measurements.removeAll { idsToRemove.contains($0.id) }
                        await self.saveMeasurements()
                        os_log("Removidas %d medições antigas para economizar espaço",
                               log: .historyLog,
                               type: .info,
                               index)
                    }
                }
                
                continuation.resume()
            }
        }
    }
}

// MARK: - FileManager Extension

private extension FileManager {
    func sizeOfDirectory(at url: URL) throws -> Int64 {
        let contents = try contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]
        )
        
        var totalSize: Int64 = 0
        
        for url in contents {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            
            if let isDirectory = resourceValues.isDirectory, isDirectory {
                totalSize += try sizeOfDirectory(at: url)
            } else if let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
}
