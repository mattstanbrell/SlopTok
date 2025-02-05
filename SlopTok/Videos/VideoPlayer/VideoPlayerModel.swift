import SwiftUI

// VideoPlayerData.swift
struct VideoPlayerModel: Identifiable, Equatable {
    let id: String        // Video ID
    let timestamp: Date   // When it was liked
    let index: Int        // Position in scroll list
    
    var next: Int? { index + 1 }  // Next video index or nil if last
    var previous: Int? { index > 0 ? index - 1 : nil }  // Previous video index or nil if first
}