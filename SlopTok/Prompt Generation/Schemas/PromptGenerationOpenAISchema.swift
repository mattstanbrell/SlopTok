import Foundation

/// JSON schemas for OpenAI prompt generation responses
enum PromptGenerationOpenAISchema {
    /// Schema for profile-based prompts (no parent IDs)
    static let profileBasedSchema = """
    {
        "type": "object",
        "properties": {
            "prompts": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "prompt": {
                            "type": "string",
                            "description": "The generated image prompt"
                        }
                    },
                    "required": ["prompt"]
                }
            }
        },
        "required": ["prompts"]
    }
    """

    /// Schema for random exploration prompts (no parent IDs)
    static let randomSchema = """
    {
        "type": "object",
        "properties": {
            "prompts": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "prompt": {
                            "type": "string",
                            "description": "The generated image prompt"
                        }
                    },
                    "required": ["prompt"]
                }
            }
        },
        "required": ["prompts"]
    }
    """
} 