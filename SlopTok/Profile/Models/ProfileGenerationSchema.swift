import Foundation

/// JSON schema for profile generation responses
enum ProfileGenerationSchema {
    /// The schema that enforces the structure of ProfileGenerationResponse
    static let schema = """
    {
        "type": "object",
        "properties": {
            "interests": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "topic": {
                            "type": "string",
                            "description": "The main topic of interest"
                        },
                        "examples": {
                            "type": "array",
                            "items": {
                                "type": "string",
                                "description": "Specific activities or aspects within the topic"
                            },
                            "description": "Examples of specific activities or aspects"
                        }
                    },
                    "required": ["topic", "examples"],
                    "additionalProperties": false
                },
                "description": "List of identified interests"
            },
            "description": {
                "type": "string",
                "description": "Natural language description of the user's overall profile"
            }
        },
        "required": ["interests", "description"],
        "additionalProperties": false,
        "strict": true
    }
    """
} 