import Foundation

/// JSON schema for prompt generation responses
enum PromptGenerationSchema {
    /// The schema that enforces the structure of PromptGeneration
    static let schema = """
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
                        },
                        "parentIds": {
                            "type": "array",
                            "items": {
                                "type": "string",
                                "description": "ID of a parent prompt"
                            },
                            "description": "IDs of parent prompts (1 for mutation, 2 for crossover)"
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