import Foundation

/// JSON schema for prompt generation responses
enum PromptGenerationSchema {
    /// Schema for mutation prompts that require exactly one parent ID
    static let mutationSchema = """
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
                        "parentId": {
                            "type": "string",
                            "description": "ID of the parent prompt that this prompt is a mutation of"
                        }
                    },
                    "required": ["prompt", "parentId"]
                }
            }
        },
        "required": ["prompts"]
    }
    """
    
    /// Schema for crossover prompts that require exactly two parent IDs
    static let crossoverSchema = """
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
                                "description": "IDs of the parent prompts"
                            },
                            "description": "Two parent IDs for crossover"
                        }
                    },
                    "required": ["prompt", "parentIds"]
                }
            }
        },
        "required": ["prompts"]
    }
    """
    
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