import SwiftUI

/// Implements a three-state header sort on top of SwiftUI's native `Table`
/// sort, which only toggles ascending↔descending. Feed it the `onChange`
/// (old, new) pair; when the user clicks the *same* column a third time
/// (descending → ascending), it returns an empty order — i.e. sorting off.
enum TableSort {
    static func cycled<T>(
        previous: [KeyPathComparator<T>], next: [KeyPathComparator<T>]
    ) -> [KeyPathComparator<T>] {
        if let previous = previous.first, let next = next.first,
            previous.keyPath == next.keyPath, previous.order == .reverse, next.order == .forward
        {
            return []
        }
        return next
    }
}

extension View {
    /// Applies the three-state cycle to a `Table` sort-order binding.
    func threeStateSort<T>(_ order: Binding<[KeyPathComparator<T>]>) -> some View {
        onChange(of: order.wrappedValue) { old, new in
            let cycled = TableSort.cycled(previous: old, next: new)
            if cycled.isEmpty && !new.isEmpty { order.wrappedValue = [] }
        }
    }
}
