import Foundation
import UIKit

/// Service responsible for generating images using various models
actor ImageGenerationService {
    /// Shared instance
    static let shared = ImageGenerationService()
    
    private init() {}
    
    /// Generates an image using the specified model
    /// - Parameters:
    ///   - modelName: Name of the model to use (e.g., "flux-schnell")
    ///   - prompt: The prompt to generate the image from
    /// - Returns: The generated image data
    /// - Throws: Error if image generation fails
    func generateImage(modelName: String, prompt: String) async throws -> Data {
        print("🖼️ Generating image using \(modelName) for prompt: \(prompt)")
        
        // Currently only supports Flux Schnell
        guard modelName == "flux-schnell" else {
            throw LLMError.apiError("Unsupported model: \(modelName)")
        }
        
        var request = URLRequest(url: URL(string: "https://sloptok-schnell.mattstanbrell.workers.dev/")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ["prompt": prompt]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(FluxSchnellResponse.self, from: data)
        
        guard response.success,
              let imageUrl = URL(string: response.imageUrl) else {
            throw LLMError.apiError("Invalid image response")
        }
        
        // Download the image data from the URL
        let (imageData, _) = try await URLSession.shared.data(from: imageUrl)
        return imageData
    }
}

/// Response from the Flux Schnell worker
private struct FluxSchnellResponse: Codable {
    let success: Bool
    let imageUrl: String
} 