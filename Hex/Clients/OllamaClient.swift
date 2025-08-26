//
//  OllamaClient.swift
//  Hex
//
//  Created on 1/26/25.
//

import ComposableArchitecture
import Foundation

struct OllamaClient {
  var generate: @Sendable (String, String) async throws -> String
  var listModels: @Sendable () async throws -> [OllamaModel]
  var isRunning: @Sendable () async -> Bool
}

struct OllamaModel: Equatable, Codable {
  let name: String
  let modifiedAt: String
  let size: Int64
}

extension OllamaClient: DependencyKey {
  static let liveValue = OllamaClient(
    generate: { prompt, model in
      let url = URL(string: "http://localhost:11434/api/generate")!
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      
      let body: [String: Any] = [
        "model": model,
        "prompt": prompt,
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
      let (data, _) = try await URLSession.shared.data(from: url)
      
      struct ModelsResponse: Decodable {
        let models: [OllamaModel]
      }
      
      let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
      return response.models
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
    }
  )
}

extension DependencyValues {
  var ollama: OllamaClient {
    get { self[OllamaClient.self] }
    set { self[OllamaClient.self] = newValue }
  }
}