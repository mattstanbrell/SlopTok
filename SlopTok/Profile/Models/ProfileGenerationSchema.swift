import Foundation

/// JSON schema for profile generation responses
enum ProfileGenerationSchema {
    /// The schema that enforces the structure of ProfileGenerationResponse
    static let schema = """
    {
        "name": "profile_generation",
        "description": "Response format for generating a user profile based on their image preferences",
        "strict": true,
        "schema": {
            "type": "object",
            "properties": {
                "interests": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "topic": {
                                "type": "string",
                                "description": "The main topic of interest identified from the user's liked images"
                            },
                            "examples": {
                                "type": "array",
                                "items": {
                                    "type": "string",
                                    "description": "A specific example of this interest seen in the liked images"
                                },
                                "description": "Examples of this interest seen in the liked images, such as specific subjects, styles, or techniques"
                            }
                        },
                        "required": ["topic", "examples"],
                        "additionalProperties": false
                    },
                    "description": "List of identified interests based on image preferences"
                },
                "description": {
                    "type": "string",
                    "description": "Natural language description of the user's visual preferences and interests"
                }
            },
            "required": ["interests", "description"],
            "additionalProperties": false
        }
    }
    """
} 