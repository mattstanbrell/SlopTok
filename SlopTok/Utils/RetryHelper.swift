import Foundation

/// Helper for executing operations with exponential backoff retries
public struct RetryHelper {
    /// Maximum number of retries before giving up
    public static let maxRetries = 5
    
    /// Executes a task with exponential backoff retries
    /// - Parameters:
    ///   - operation: The async operation to retry
    ///   - shouldRetry: Optional closure that determines if an error should trigger a retry.
    ///                  Defaults to retrying on all errors.
    /// - Returns: The operation result
    /// - Throws: The last error encountered if all retries fail, or if shouldRetry returns false
    public static func retry<T>(
        operation: () async throws -> T,
        shouldRetry: (Error) -> Bool = { _ in true }
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                if attempt > 0 {
                    // Exponential backoff: 1s, 2s, 4s, 8s, 16s
                    let delay = pow(2.0, Double(attempt - 1))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    print("🔄 Retry attempt \(attempt) after \(delay)s delay")
                }
                return try await operation()
            } catch {
                lastError = error
                if !shouldRetry(error) || attempt == maxRetries {
                    throw error
                }
                print("❌ Attempt \(attempt) failed: \(error.localizedDescription)")
            }
        }
        
        throw lastError ?? NSError(
            domain: "RetryHelper",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown error during retry"]
        )
    }
} 