import Foundation

/// Configuration for LLM API calls
struct LLMConfig {
    /// The model to use (e.g., "gpt-4o-mini")
    let model: String
    
    /// Base URL for the OpenAI API
    let baseURL: URL
    
    /// API key for authentication
    let apiKey: String
    
    /// Maximum tokens to generate
    let maxTokens: Int
    
    /// Temperature for response generation (0.0-1.0)
    let temperature: Double
    
    /// Creates a new configuration with default values
    /// - Parameter apiKey: OpenAI API key
    /// - Parameter model: Model name, defaults to "gpt-4o-mini"
    init(
        apiKey: String,
        model: String = "gpt-4o-mini",
        maxTokens: Int = 1000,
        temperature: Double = 0.7
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
} 