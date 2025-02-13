import Foundation

struct PromptDistribution {
    let mutationCount: Int
    let crossoverCount: Int
    let profileBasedCount: Int
    let explorationCount: Int

    subscript(type: PromptType) -> Int {
        switch type {
        case .mutation: return mutationCount
        case .crossover: return crossoverCount
        case .profileBased: return profileBasedCount
        case .exploration: return explorationCount
    }

    func distributeExcess(excessCount: Int, currentCounts: [PromptType: Int]) -> [PromptType: Int] {
        var distribution: [PromptType: Int] = [:]
        var remaining = excessCount

        // Remove types with non-zero count in original distribution. We didn't want them anyway!
        // Remove types that already have desired count. 
        // Sorted by delta between desired and current count, descending
        let activeTypesSorted = PromptType.allCases
            .filter { type in 
                let currentCount = currentCounts[type, default: 0]
                let desiredCount = self[type]
                return desiredCount > 0 && currentCount < desiredCount 
            }
            .sorted { a, b in 
                let deltaA = self[a] - currentCounts[a, default: 0]
                let deltaB = self[b] - currentCounts[b, default: 0]
                return deltaA > deltaB
            }

        // Distribute remaining prompts to types that need them
        while remaining > 0 {
            for type in activeTypesSorted {
                if remaining > 0 {
                    distribution[type] = currentCounts[type, default: 0] + 1
                    remaining -= 1
                }
            }
        }

        return distribution
    }

    func calculateDistribution(likedCount: Int, totalCount: Int) -> PromptDistribution {
        switch likedCount {
            case 0:
                return PromptDistribution(
                    mutationCount: 0,
                    crossoverCount: 0,
                    profileBasedCount: 15,
                    explorationCount: 5
                )

            case 1:
                return PromptDistribution(
                    mutationCount: 4,
                    crossoverCount: 0,
                    profileBasedCount: 12,
                    explorationCount: 4
                )

            case 2:
                return PromptDistribution(
                    mutationCount: 6,
                    crossoverCount: 2,
                    profileBasedCount: 8,
                    explorationCount: 4
                )
            
            case 3...5:
                let mutations = min(10, likedCount * 2)
                let crossovers = min(5, likedCount)
                let profileBased = totalCount - mutations - crossovers
                let exploration = 2  // Fixed amount
                
                return PromptDistribution(
                    mutationCount: mutations,
                    crossoverCount: crossovers,
                    profileBasedCount: profileBased,
                    explorationCount: exploration
                )

            default:
                return PromptDistribution(
                    mutationCount: min(10, likedCount),
                    crossoverCount: 5,
                    profileBasedCount: 3,
                    explorationCount: 2
                )
        }
    }
}
