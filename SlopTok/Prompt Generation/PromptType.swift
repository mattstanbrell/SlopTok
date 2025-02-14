/// Types of prompts that can be generated
enum PromptType: CaseIterable {
    /// Mutations of existing prompts
    case mutation
    
    /// Combinations of two existing prompts
    case crossover
    
    /// Prompts based on user profile interests
    case profileBased
    
    /// Random exploration prompts
    case exploration
} 