# SlopTok Product Requirements Document

## Overview
SlopTok is a video-sharing platform that uses AI to generate personalized video prompts based on user preferences and interactions. The system learns from user behavior to create increasingly relevant and engaging video suggestions.

## Core Components

### 1. User Profile System

#### 1.1 Profile Structure
```swift
struct UserProfile {
    struct Interest {
        let topic: String
        var weight: Double  // 0-1
        let examples: [String]
        var lastUpdated: Date
        }
    
    var interests: [Interest]
    var description: String
    var lastUpdated: Date
}
```

#### 1.2 Profile Generation
- **Initial Profile Creation**
  - Occurs after user views and likes some of the 10 seed videos
  - Uses liked seed videos to infer initial interests and preferences
  - All new interests start with weight 0.5
  - We prompt an LLM (gpt-4o-mini) using structure outputs to generate the profile

- **Profile Updates**
  - Triggered every 50 videos viewed
  - Uses liked videos from the most recent 50 watched videos
  - Updates weights of existing interests based on whether they appear in new profile:
    - +0.1 if interest appears in new profile
    - -0.1 if interest doesn't appear
    - Remove interest if weight reaches 0
  - We prompt an LLM (gpt-4o-mini) using structure outputs to generate the profile
  - The LLM never sees or sets weights.

The profile update process follows these steps:
1. Give the LLM the successful prompts (and not the current profile) and have it return the interests, examples, and description. The LLM never sees or sets weights.
2. If any interest categories are the same (exact string match) between existing and new, merge them and set the duplicates aside. When merging interests, combine their examples.
3. Give the LLM the existing profile (without description and any interests that were merged) and the new profile (again without description and any interests that were merged) and have it produce some structured output where it identifies categories and examples that are semantically the same but our basic merging code didn't identify them (eg "mountain biking" and "mtb"). Make it clear that there isn't necessarily any such duplicates.
4. If it identifies duplicates, merge them by combining their examples.
5. For all interests:
   - If an interest appears in the new profile (either directly or through merging), increase its weight by 0.1
   - If an interest only exists in the old profile, decrease its weight by 0.1
   - If an interest's weight reaches 0, remove it from the profile
6. Give the LLM this merged profile (sans descriptions) and separately the existing description and new description, and tell it to update the description.

#### 1.3 Example User Profiles

##### Example 1: Initial Profile After Seed Videos
```json
{
    "interests": [
        {
            "topic": "Mountain Biking",
            "weight": 0.5,  // Initial weight for new interests
            "examples": [
                "downhill trails",
                "bike park jumps",
                "technical singletrack"
            ]
        },
        {
            "topic": "Rock Climbing",
            "weight": 0.5,  // Initial weight for new interests
            "examples": [
                "bouldering problems",
                "sport climbing routes",
                "climbing techniques"
            ]
        }
    ],
    "description": "An outdoor sports enthusiast with a focus on technical challenges and adrenaline activities. Shows strong interest in both mountain biking and climbing, particularly enjoying technical aspects of both sports."
}
```

##### Example 2: Updated Profile After 50 Videos
```json
{
    "interests": [
        {
            "topic": "Mountain Biking",
            "weight": 0.7,  // Appeared in new profile (+0.2)
            "examples": [
                "downhill trails",
                "bike park jumps",
                "technical singletrack",
                "trail maintenance",  // New example
                "bike setup"         // New example
            ]
        },
        {
            "topic": "Rock Climbing",
            "weight": 0.4,  // Didn't appear in new profile (-0.1)
            "examples": [
                "bouldering problems",
                "sport climbing routes",
                "climbing techniques"
            ]
        },
        {
            "topic": "Trail Running",  // New interest
            "weight": 0.5,  // Initial weight
            "examples": [
                "technical trails",
                "ultrarunning",
                "trail gear"
            ]
        }
    ],
    "description": "An outdoor sports enthusiast who has developed a strong focus on mountain biking while maintaining interests in climbing and discovering trail running. Shows particular engagement with technical aspects of mountain biking, including trail knowledge and equipment setup."
}
```

##### Example 3: Profile After Semantic Merging
Before merging:
```json
{
    "interests": [
        {
            "topic": "MTB",
            "weight": 0.7,
            "examples": ["downhill", "jumps"]
        }
    ]
}
```
```json
{
    "interests": [
        {
            "topic": "Mountain Biking",
            "weight": 0.5,
            "examples": ["trail riding", "bike setup"]
        }
    ]
}
```

After LLM semantic matching and merging:
```json
{
    "interests": [
        {
            "topic": "Mountain Biking",
            "weight": 0.9,  // Appeared in new profile through merging (+0.2)
            "examples": [
                "downhill",
                "jumps",
                "trail riding",
                "bike setup"
            ]
        }
    ]
}
```

### 2. Video Prompt System

#### 2.1 Prompt Structure
```swift
struct VideoPrompt {
    let prompt: String
    let parentIds: [String]?  // For tracking lineage
}
```

#### 2.2 Prompt Generation Types
1. **Initial Prompts**
   - Generated after user views all 10 seed videos, we assume they have liked some.
   - 10 new prompts generated using genetic algorithm approach:
    - some come from taking the successful (liked) seed prompts and mutatintg them
    - some come from taking pairs of successful prompts and performing crossover
   - 7 new prompts are generated not using the liked prompts, but based purely on the user profile
   - 3 random prompts are generated for exploration
   - We prompt an LLM (gpt-4o-mini) using structure outputs to generate the prompts

2. **Ongoing Prompts**
   - Generated every 20 videos viewed
   - We take the liked videos from those most recent 20 videos
   - Uses genetic algorithm approach:
     - Crossover: Combining elements from successful prompts
     - Mutation: Variations on successful prompts
     - Exploration: Prompts generated from the user profile
     - Random: Complete novelty for discovery
   - The distribution of techniques depends on how many liked videos the user has.  
   - We prompt an LLM (gpt-4o-mini) using structure outputs to generate the prompts

### 3. OpenAI Integration

#### 3.1 API Configuration
```swift
struct LLMConfig {
    let model = "gpt-4o-mini"
    let baseURL = "https://api.openai.com/v1/chat/completions"
    let responseFormat = "json_schema"
}
```

#### 3.2 Schema Definitions

##### Profile Generation Schema
```json
{
    "type": "object",
    "properties": {
        "interests": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "topic": {"type": "string"},
                    "examples": {
                        "type": "array",
                        "items": {"type": "string"}
                    }
                },
                "required": ["topic", "examples"]
            }
        },
        "description": {"type": "string"}
    },
    "required": ["interests", "description"]
}
```

##### Prompt Generation Schema
```json
{
    "type": "array",
    "items": {
        "type": "object",
        "properties": {
            "prompt": {"type": "string"},
            "parentIds": {
                "type": "array",
                "items": {"type": "string"}
            },
            "targetLength": {"type": "integer"},
            "style": {"type": "string"}
        },
        "required": ["prompt", "targetLength", "style"]
    }
}
```

### 4. Data Storage

#### 4.1 Firestore Structure
```
users/
  {userId}/
    description: string
    lastUpdated: timestamp
    watchCounts/
      videosWatchedSinceLastPrompt: number  // Reset to 0 after generating prompts
      videosWatchedSinceLastProfile: number  // Reset to 0 after updating profile
      lastPromptGeneration: timestamp
      lastProfileUpdate: timestamp
    interests/
      {interestId}/
        topic: string
        weight: number
        examples: array<string>
        lastUpdated: timestamp
    videoInteractions/
      {videoId}/
        liked: boolean
        last_seen: timestamp
        isFirstWatch: boolean  // True if this is the first time watching this video
```

#### 4.2 Watch Count Tracking
- Each time a user watches a video:
  1. Check if this is the first time watching (`isFirstWatch` is true)
  2. If it is a first watch:
     - Increment `videosWatchedSinceLastPrompt`
     - Increment `videosWatchedSinceLastProfile`
     - Set `isFirstWatch` to false
  3. Update `last_seen` timestamp
  4. If `videosWatchedSinceLastPrompt` reaches 20:
     - Generate new prompts
     - Reset `videosWatchedSinceLastPrompt` to 0
     - Update `lastPromptGeneration` timestamp
  5. If `videosWatchedSinceLastProfile` reaches 50:
     - Update user profile
     - Reset `videosWatchedSinceLastProfile` to 0
     - Update `lastProfileUpdate` timestamp

### 5. Business Rules

#### 5.1 Profile Updates
- New interests start with weight 0.5
- Interests with weight 0 are removed
- Weight updates:
  - +0.1 when appearing in new profile
  - -0.1 when not appearing
  - Capped at 0.0-1.0 range

#### 5.2 Prompt Generation
- Initial prompts:
  - Must use liked seed videos as strong signals
  - Balance between refinement and exploration
  - Include style variety

- Ongoing prompts:
  - Must track lineage for genetic algorithm
  - Avoid repeating failed approaches
  - Maintain quality even in random exploration
  - Adapt ratios based on available liked videos:
    ```
    if likedVideos < 3:
        (explore: 10, random: 5, crossover: 0, mutate: 5)
    else if likedVideos < 5:
        (explore: 5, random: 5, crossover: 3, mutate: 7)
    else:
        (explore: 3, random: 2, crossover: 5, mutate: 10)
    ```

#### 5.3 Prompt Lineage and Backtracking
- Each prompt tracks its parent prompts through `parentIds`
- When a video from a prompt isn't liked:
  1. System backtracks to the parent prompt if it was successful
  2. Generates a new mutation of the parent, informing the LLM of:
     - The original successful prompt
     - All previous failed mutations
     - Instructions to try a different approach
  3. This backtracking process can repeat up to 5 times per successful prompt
  4. After 5 failed mutations, the system abandons that lineage

Example lineage flow:
```
Prompt A (successful video)
    └─> Prompt B (failed) - First mutation attempt
    └─> Prompt C (failed) - Second attempt, LLM informed about B's failure
    └─> Prompt D (failed) - Third attempt, LLM informed about B and C's failures
    └─> Prompt E (failed) - Fourth attempt
    └─> Prompt F (failed) - Final attempt before abandoning A's lineage
```

The LLM uses this lineage information to:
- Avoid approaches similar to failed attempts
- Try increasingly different variations
- Learn from what hasn't worked
- Make informed decisions about when to abandon a lineage

