import SwiftUI

/// Layout follows allocated space and system division regions, never hinge angle.
/// A horizontal fold does not change the column arrangement.
struct MessagesColumnLayout: Equatable {
    static let minimumWideWidth: CGFloat = 660
    let usesColumns: Bool
    let inboxWidth: CGFloat
    let gap: CGFloat

    init(size: CGSize, divisions: [CGRect] = [], usesColumns: Bool? = nil) {
        let bounds = CGRect(origin: .zero, size: size)
        let verticalDivision = divisions.map { $0.intersection(bounds) }.first {
            !$0.isNull && $0.height >= size.height * 0.5
                && $0.width < size.width * 0.2
                && $0.midX >= 280 && size.width - $0.midX >= 280
        }
        self.usesColumns = usesColumns ?? (size.width >= Self.minimumWideWidth || verticalDivision != nil)
        if self.usesColumns, let verticalDivision {
            // Division frames include the system's fold clearance. Equal panes
            // meet at the fold; do not fabricate an interim center region.
            inboxWidth = verticalDivision.minX
            gap = verticalDivision.width
        } else {
            inboxWidth = self.usesColumns ? 360 : size.width
            gap = self.usesColumns ? 1 : 0
        }
    }
}

extension GeometryProxy {
    var messagesDivisionFrames: [CGRect] {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            return reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
        }
        #endif
        return []
    }
}
