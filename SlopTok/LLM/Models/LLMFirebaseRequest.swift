import Foundation

/// Request structure for Firebase Cloud Function LLM calls
struct LLMFirebaseRequest: Codable {
    /// The main prompt to send
    let prompt: String
    
    /// Optional system prompt
    let systemPrompt: String?
    
    /// JSON schema for response formatting
    let schema: String
    
    /// Model configuration
    let config: LLMRequestConfig
    
    /// Configuration for the request
    struct LLMRequestConfig: Codable {
        let model: String
        let maxTokens: Int
        let temperature: Double
        
        init(from config: LLMConfig) {
            self.model = config.model
            self.maxTokens = config.maxTokens
            self.temperature = config.temperature
        }
    }
} 