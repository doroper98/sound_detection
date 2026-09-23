import Foundation

struct SavedNativeReport: Codable, Identifiable {
    let id: UUID
    let date: Date
    let version: String
    let status: String
    let json: Data
}
