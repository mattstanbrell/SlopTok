import Foundation
import FirebaseVertexAI

/// JSON schema for prompt generation responses using Gemini
enum PromptGenerationGeminiSchema {
    /// Schema for structured output from Gemini
    static let schema = Schema.object(
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
} 