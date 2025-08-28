//
//  OllamaClient.swift
//  Hex
//
//  Created on 1/26/25.
//

import ComposableArchitecture
import Foundation

public struct OllamaClient {
  var generate: @Sendable (String, String, String?) async throws -> String
  var listModels: @Sendable () async throws -> [OllamaModel]
  var isRunning: @Sendable () async -> Bool
  var pullModel: @Sendable (String, @escaping (Double) -> Void) async throws -> Void
  var deleteModel: @Sendable (String) async throws -> Void
}

public struct OllamaModel: Equatable, Codable {
  public let name: String
  public let modifiedAt: String?  // Made optional - may not be in API response
  public let size: Int64
  
  // Handle alternative field names Ollama might use
  private enum CodingKeys: String, CodingKey {
    case name
    case modifiedAt = "modified_at"  // Try both modifiedAt and modified_at
    case size
  }
  
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    modifiedAt = try container.decodeIfPresent(String.self, forKey: .modifiedAt)
    size = try container.decodeIfPresent(Int64.self, forKey: .size) ?? 0
  }
}

extension OllamaClient: DependencyKey {
  public static let liveValue = OllamaClient(
    generate: { prompt, model, customSystemPrompt in
      let url = URL(string: "http://localhost:11434/api/generate")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      
      let systemPrompt = customSystemPrompt ?? "Be concise and helpful. For simple calculations or yes/no questions, give just the answer. For explanations or how-to questions, provide clear but brief responses with essential details. Avoid unnecessary preambles or conclusions."
      
      let body: [String: Any] = [
        "model": model,
        "prompt": prompt,
        "system": systemPrompt,
        "stream": false
      ]
      
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      
      let (data, _) = try await URLSession.shared.data(for: request)
      
      struct GenerateResponse: Decodable {
        let response: String
      }
      
      let response = try JSONDecoder().decode(GenerateResponse.self, from: data)
      return response.response
    },
    
    listModels: {
      let url = URL(string: "http://localhost:11434/api/tags")!
      print("[OllamaClient] Fetching models list from: \(url)")
      let (data, _) = try await URLSession.shared.data(from: url)
      
      // Debug: Print raw JSON
      if let jsonString = String(data: data, encoding: .utf8) {
        print("[OllamaClient] Raw JSON response: \(jsonString)")
      }
      
      struct ModelsResponse: Decodable {
        let models: [OllamaModel]
      }
      
      do {
        let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
        print("[OllamaClient] Successfully decoded \(response.models.count) models")
        for model in response.models {
          print("[OllamaClient] - Model: '\(model.name)', Size: \(model.size) bytes")
        }
        return response.models
      } catch {
        print("[OllamaClient] Failed to decode models: \(error)")
        // Try to decode raw to see structure
        if let json = try? JSONSerialization.jsonObject(with: data) {
          print("[OllamaClient] Raw JSON structure: \(json)")
        }
        throw error
      }
    },
    
    isRunning: {
      let url = URL(string: "http://localhost:11434/api/tags")!
      
      do {
        let (_, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse {
          return httpResponse.statusCode == 200
        }
        return false
      } catch {
        return false
      }
    },
    
    pullModel: { modelName, progressHandler in
      print("[OllamaClient] Pulling model: '\(modelName)'")
      let url = URL(string: "http://localhost:11434/api/pull")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.timeoutInterval = 600 // 10 minutes for large models
      
      let body = ["name": modelName, "stream": true] as [String : Any]
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      print("[OllamaClient] Request body: \(body)")
      
      let (bytes, response) = try await URLSession.shared.bytes(for: request)
      
      guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200 else {
        throw NSError(domain: "OllamaClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to pull model"])
      }
      
      var lastStatus = ""
      for try await line in bytes.lines {
        guard let data = line.data(using: .utf8) else { continue }
        
        struct PullResponse: Decodable {
          let status: String?
          let total: Int64?
          let completed: Int64?
        }
        
        if let response = try? JSONDecoder().decode(PullResponse.self, from: data) {
          if let status = response.status, status != lastStatus {
            print("[OllamaClient] Pull status: \(status)")
            lastStatus = status
          }
          
          if let total = response.total, let completed = response.completed, total > 0 {
            let progress = Double(completed) / Double(total)
            progressHandler(progress)
          }
          
          // Check if download is complete
          if response.status?.contains("success") == true {
            print("[OllamaClient] Pull completed successfully")
            progressHandler(1.0)
            break
          }
        } else {
          print("[OllamaClient] Could not decode line: \(line)")
        }
      }
    },
    
    deleteModel: { modelName in
      let url = URL(string: "http://localhost:11434/api/delete")!
      var request = URLRequest(url: url)
      request.httpMethod = "DELETE"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      
      let body = ["name": modelName]
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      
      let (_, response) = try await URLSession.shared.data(for: request)
      
      guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200 else {
        throw NSError(domain: "OllamaClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to delete model"])
      }
    }
  )
}

extension DependencyValues {
  public var ollama: OllamaClient {
    get { self[OllamaClient.self] }
    set { self[OllamaClient.self] = newValue }
  }
}