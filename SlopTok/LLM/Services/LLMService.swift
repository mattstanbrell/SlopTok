import Foundation

/// Message in a conversation with the LLM
public struct LLMMessage: Codable {
    /// Role of the message sender
    public enum Role: String, Codable {
        case system
        case user
        case assistant
    }
    
    public let role: Role
    public let content: String
}

/// Service for making LLM API calls with structured responses
actor LLMService {
    /// Shared instance for the service
    static let shared = LLMService()
    
    /// Current configuration
    private var config: LLMConfig?
    
    /// Worker URL
    private let workerURL = URL(string: "https://sloptok-llm.mattstanbrell.workers.dev/")!
    
    private init() {}
    
    /// Configures the service with API credentials
    /// - Parameter config: LLM configuration
    func configure(with config: LLMConfig) {
        self.config = config
    }
    
    /// Makes an LLM API call with structured response and conversation history
    /// - Parameters:
    ///   - messages: Array of messages in the conversation
    ///   - responseType: The expected response type (must conform to Codable)
    ///   - schema: JSON schema for the expected response
    /// - Returns: LLMResponse containing either the decoded response or an error
    func complete<T: Codable>(
        messages: [LLMMessage],
        responseType: T.Type,
        schema: String
    ) async -> LLMResponse<T> {
        // Log input
        print("\n🤖 LLM Request:")
        for message in messages {
            print("\(message.role): \(message.content)")
        }
        print("Schema: \(schema)")
        
        // Parse schema string into JSON object
        guard let schemaData = schema.data(using: .utf8),
              let schemaJson = try? JSONSerialization.jsonObject(with: schemaData) else {
            return .failure(.systemError(NSError(domain: "LLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid schema JSON"])))
        }
        
        // Create the request body with parsed schema and messages
        let requestBody: [String: Any] = [
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "schema": schemaJson
        ]
        
        do {
            var request = URLRequest(url: workerURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.systemError(NSError(domain: "LLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])))
            }
            
            guard httpResponse.statusCode == 200 else {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = errorJson["error"] as? String {
                    return .failure(.apiError(errorMessage))
                }
                return .failure(.apiError("HTTP \(httpResponse.statusCode)"))
            }
            
            let responseString = String(data: data, encoding: .utf8) ?? ""
            print("\n🤖 LLM Response:")
            print(responseString)
            
            if let openAIResponse = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
               let content = openAIResponse.choices.first?.message.content,
               let jsonData = content.data(using: .utf8) {
                let decoded = try JSONDecoder().decode(responseType, from: jsonData)
                return .success(decoded, rawContent: content)
            }
            
            // Try direct decoding if the response is already in the expected format
            let decoded = try JSONDecoder().decode(responseType, from: data)
            return .success(decoded, rawContent: String(data: data, encoding: .utf8) ?? "")
            
        } catch {
            print("❌ LLM Error: \(error.localizedDescription)")
            return .failure(.systemError(error))
        }
    }
    
    /// Convenience method for simple prompts (creates a single user message)
    /// - Parameters:
    ///   - userPrompt: The user prompt
    ///   - systemPrompt: Optional system prompt
    ///   - responseType: The expected response type (must conform to Codable)
    ///   - schema: JSON schema for the expected response
    /// - Returns: LLMResponse containing either the decoded response or an error
    func complete<T: Codable>(
        userPrompt: String,
        systemPrompt: String? = nil,
        responseType: T.Type,
        schema: String
    ) async -> LLMResponse<T> {
        var messages: [LLMMessage] = []
        
        if let systemPrompt = systemPrompt {
            messages.append(LLMMessage(role: .system, content: systemPrompt))
        }
        messages.append(LLMMessage(role: .user, content: userPrompt))
        
        return await complete(
            messages: messages,
            responseType: responseType,
            schema: schema
        )
    }
}

// MARK: - Response Types

private struct OpenAIResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct OpenAIError: Codable {
    struct ErrorDetails: Codable {
        let message: String
    }
    let error: ErrorDetails
} 