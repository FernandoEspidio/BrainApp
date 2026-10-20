import Foundation

/// Opens the log sheet, optionally with an area already chosen.
struct LogRequest: Identifiable {
    let id = UUID()
    let areaID: String?
}
