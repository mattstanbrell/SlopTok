import Foundation
import FirebaseVertexAI

/// JSON schema for profile generation responses using Gemini
enum ProfileGenerationGeminiSchema {
    /// Schema for structured output from Gemini
    static let schema = Schema.object(
        properties: [
            "interests": .array(
                items: .object(
                    properties: [
                        "topic": .string(description: "The main topic of interest identified from the user's liked images"),
                        "examples": .array(
                            items: .string(description: "A specific example of this interest seen in the liked images"),
                            description: "Examples of this interest seen in the liked images, such as specific subjects, styles, or techniques"
                        )
                    ],
                    description: "An interest identified from the user's liked images"
                ),
                description: "List of identified interests based on image preferences"
            ),
            "description": .string(description: "Natural language description of the user's visual preferences and interests")
        ]
    )
} 