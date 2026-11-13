import Foundation

nonisolated
enum LangGrade: String, Codable, Identifiable, CaseIterable, Sendable {
    var id: Self { self }

    case aOne, aTwo, bOne
    
    var title: LocalizedStringResource {
        switch self {
        case .aOne:
            "None at all. Start me from zero."
        case .aTwo:
            "I can hold a simple conversation."
        case .bOne:
            "I speak, but it’s gone rusty."
        }
    }
    
    var grade: String {
        switch self {
        case .aOne:
            "A1"
        case .aTwo:
            "A2"
        case .bOne:
            "B1"
        }
    }
}
