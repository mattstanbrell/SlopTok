struct GenerationResponse: Codable {
    let success: Bool
    let videoUrl: String?
    let status: String
    let error: String?
}

// Note: We don't need the other structs anymore since we're not using the full Replicate response 