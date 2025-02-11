import Foundation

/// Single generated video prompt with optional parent information
struct PromptGeneration: Codable {
    /// The generated video prompt
    let prompt: String
    
    /// IDs of parent prompts that influenced this generation
    /// - One ID for mutations (variation of a single prompt)
    /// - Two IDs for crossovers (combining elements from two prompts)
    let parentIds: [String]?
}

/// Response from LLM for generating new video prompts
struct PromptGenerationResponse: Codable {
    /// The array of generated prompts
    let prompts: [PromptGeneration]
} 