import FirebaseVertexAI
import Foundation
import UIKit

class VertexAIService {
    static let shared = VertexAIService()
    private let vertex = VertexAI.vertexAI()
    private let model: GenerativeModel
    
    /// Creates a Gemini model with consistent safety settings
    /// - Parameters:
    ///   - modelName: Name of the model to use (e.g. "gemini-2.0-flash")
    ///   - generationConfig: Optional generation config for structured output
    /// - Returns: Configured GenerativeModel instance
    static func createGeminiModel(
        modelName: String,
        generationConfig: GenerationConfig? = nil
    ) -> GenerativeModel {
        let safetySettings = [
            SafetySetting(harmCategory: .harassment, threshold: .blockOnlyHigh),
            SafetySetting(harmCategory: .hateSpeech, threshold: .blockOnlyHigh),
            SafetySetting(harmCategory: .sexuallyExplicit, threshold: .blockOnlyHigh),
            SafetySetting(harmCategory: .dangerousContent, threshold: .blockOnlyHigh),
            SafetySetting(harmCategory: .civicIntegrity, threshold: .blockOnlyHigh)
        ]
        
        return VertexAI.vertexAI().generativeModel(
            modelName: modelName,
            generationConfig: generationConfig,
            safetySettings: safetySettings
        )
    }
    
    private init() {
        self.model = Self.createGeminiModel(modelName: "gemini-2.0-flash")
    }
    
    func analyzeText(_ prompt: String) async throws -> String {
        let response = try await model.generateContent(prompt)
        return response.text ?? "No analysis available"
    }
    
    func analyzeImage(_ image: UIImage, prompt: String = "What's in this picture?") async throws -> String {
        let response = try await model.generateContent(image, prompt)
        return response.text ?? "No analysis available"
    }
    
    func generateContent(_ textA: String, _ imageA: UIImage, _ textB: String, _ imageB: UIImage, _ prompt: String) async throws -> String {
        let response = try await model.generateContent(textA, imageA, textB, imageB, prompt)
        return response.text ?? "No analysis available"
    }
    
    func generateContentForFive(images: [(label: String, image: UIImage)], prompt: String) async throws -> String {
        guard !images.isEmpty else {
            return "No images to analyze"
        }
        
        var parts: [PartsRepresentable] = []
        for (index, imageData) in images.prefix(5).enumerated() {
            parts.append("Image \(index + 1)" as PartsRepresentable)
            parts.append(imageData.image as PartsRepresentable)
        }
        
        let description = (0..<min(images.count, 5)).map { "Image \($0 + 1)" }.joined(separator: ", ")
        parts.append("Describe \(description)" as PartsRepresentable)
        
        return try await model.generateContent(parts).text ?? "No analysis available"
    }
} 
