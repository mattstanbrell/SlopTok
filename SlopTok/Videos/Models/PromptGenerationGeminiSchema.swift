import Foundation
import FirebaseVertexAI

/// JSON schema for prompt generation responses using Gemini
enum PromptGenerationGeminiSchema {
    /// Schema for mutation prompts
    static let mutationSchema = Schema.object(
        properties: [
            "mutatedPrompts": .array(
                items: .object(
                    properties: [
                        "prompt": .string(description: "The generated prompt for creating a new image"),
                        "parentId": .string(description: "ID of the parent prompt this was mutated from")
                    ],
                    description: "A mutated prompt and its parentId"
                ),
                description: "List of generated prompts that build upon the user's liked images"
            )
        ]
    )
    
    /// Schema for crossover prompts
    static let crossoverSchema = Schema.object(
        properties: [
            "crossoverPrompts": .array(
                items: .object(
                    properties: [
                        "prompt": .string(description: "The generated prompt for creating a new image"),
                        "parentIds": .array(
                            items: .string(description: "ID of a parent prompt"),
                            description: "Array of exactly two parent prompt IDs (e.g. ['abc123', 'def456'])"
                        )
                    ],
                    description: "A crossover prompt combining elements from two parent prompts"
                ),
                description: "List of generated prompts that combine elements from pairs of user's liked images"
            )
        ]
    )
} 