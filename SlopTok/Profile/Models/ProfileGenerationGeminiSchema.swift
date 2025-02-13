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
                        "topic": .string(description: """
                            The main topic of interest identified from the user's liked images.
                            Example: "Nature Photography" or "Architectural Design"
                            """
                        ),
                        "examples": .array(
                            items: .string(description: """
                                A specific example of this interest seen in the liked images.
                                Examples: "macro flower details", "soft natural lighting", "geometric patterns"
                                """
                            ),
                            description: """
                            Examples of this interest seen in the liked images, such as specific subjects, styles, or techniques.
                            Example array: ["macro flower details", "soft natural lighting", "botanical compositions"]
                            """
                        )
                    ],
                    description: """
                    An interest identified from the user's liked images.
                    Example: {"topic": "Nature Photography", "examples": ["macro flower details", "soft natural lighting", "botanical compositions"]}
                    """
                ),
                description: """
                List of identified interests based on image preferences.
                Example: [
                    {
                        "topic": "Nature Photography",
                        "examples": ["macro flower details", "soft natural lighting", "botanical compositions"]
                    },
                    {
                        "topic": "Architectural Photography",
                        "examples": ["geometric patterns", "dramatic building angles", "minimalist structures"]
                    }
                ]
                """
            ),
            "description": .string(description: """
                Natural language description of the user's visual preferences and interests.
                Example: "Based on this limited initial set of interactions, the user appears to show interest in detailed nature photography, particularly images that capture intricate botanical details. They've also engaged with architectural content, suggesting a possible appreciation for geometric forms and structural compositions. As more data becomes available, these preferences may evolve or reveal different patterns."
                """
            )
        ]
    )
} 