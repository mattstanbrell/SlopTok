import Foundation

/// Helper class for retrying async operations with exponential backoff
enum RetryHelper {
    /// Retries an async operation with exponential backoff
    /// - Parameters:
    ///   - numRetries: Number of retry attempts before giving up
    ///   - operation: Name of the operation for logging purposes
    ///   - task: The async task to retry
    /// - Returns: The result of the successful task execution
    /// - Throws: The last error encountered if all retries fail
    static func retry<T>(
        numRetries: Int,
        operation: String,
        task: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0...numRetries {
            do {
                if attempt > 0 {
                    print("🔄 Retry attempt \(attempt) for \(operation)")
                    try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * Double(attempt)))
                }
                
                return try await task()
            } catch {
                lastError = error
                if attempt == numRetries {
                    throw error
                }
            }
        }
        
        throw lastError ?? LLMError.systemError(NSError(
            domain: "RetryHelper",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown error during \(operation)"]
        ))
    }
} 