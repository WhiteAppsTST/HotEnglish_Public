import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    var id: Self { self }
    
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7
}
