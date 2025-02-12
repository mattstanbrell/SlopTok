import Foundation

/// Response from LLM for profile generation
struct ProfileGenerationResponse: Codable {
    /// The identified interests
    let interests: [InterestGeneration]
    /// Natural language description of the profile
    let description: String
}

/// Interest identified by LLM
struct InterestGeneration: Codable {
    /// The main topic of interest
    let topic: String
    /// Examples of this interest seen in the prompts
    let examples: [String]
} 