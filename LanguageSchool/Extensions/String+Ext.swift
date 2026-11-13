import Foundation
import UIKit

extension String {
    var trimmedLines: String {
        self
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }
    
    func containsCaseInsensitive(_ substring: String) -> Bool {
        return self.range(of: substring, options: .caseInsensitive) != nil
    }
}
