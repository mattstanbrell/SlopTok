import Foundation

/// Represents the result of an LLM API call
enum LLMResponse<T: Codable> {
    /// Successful response with decoded data and raw content
    case success(T, rawContent: String)
    /// Error during API call or decoding
    case failure(LLMError)
}

/// Possible errors from LLM operations
enum LLMError: Error {
    /// API key is missing or invalid
    case invalidAPIKey
    /// Failed to encode request
    case requestEncodingFailed
    /// Failed to decode response
    case responseDecodingFailed(String)
    /// API returned an error
    case apiError(String)
    /// Network or system error
    case systemError(Error)
    
    var description: String {
        switch self {
        case .invalidAPIKey:
            return "Invalid or missing OpenAI API key"
        case .requestEncodingFailed:
            return "Failed to encode request data"
        case .responseDecodingFailed(let details):
            return "Failed to decode response: \(details)"
        case .apiError(let message):
            return "API error: \(message)"
        case .systemError(let error):
            return "System error: \(error.localizedDescription)"
        }
    }
} 