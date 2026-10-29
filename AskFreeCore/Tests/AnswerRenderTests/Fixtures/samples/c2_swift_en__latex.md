Use a **Combine** pipeline with `.debounce` on the text binding, then trigger the search from the debounced value.

### Basic approach

```swift
import SwiftUI
import Combine

struct SearchView: View {
    @State private var query = ""
    @State private var results: [String] = []

    var body: some View {
        List(results, id: \.self) { Text($0) }
            .searchable(text: $query)
            .onChange(of: query) { _, newValue in
                // optional: cancel in-flight work here
            }
            .task(id: query) {
                // simple modern alternative, see below
            }
    }
}
```

### Debounce with Combine

```swift
import SwiftUI
import Combine

final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [String] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        $query
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                self?.search(text)
            }
            .store(in: &cancellables)
    }

    private func search(_ text: String) {
        guard !text.isEmpty else { results = []; return }
        // replace with real async call
        results = ["result for \(text)"]
    }
}

struct SearchView: View {
    @StateObject private var vm = SearchViewModel()

    var body: some View {
        List(vm.results, id: \.self) { Text($0) }
            .searchable(text: $vm.query)
    }
}
```

### Modern alternative (no Combine)

`.task(id:)` cancels the previous task when `query` changes, so a `Task.sleep` gives you debounce for free:

```swift
.searchable(text: $query)
.task(id: query) {
    guard !query.isEmpty else { results = []; return }
    try? await Task.sleep(for: .milliseconds(300))
    guard !Task.isCancelled else { return }
    results = await performSearch(query)
}
```

### Key points

- **`.debounce`** delays emission until the user pauses typing; **`.removeDuplicates()`** avoids repeat searches for the same text.
- **`RunLoop.main`** or `DispatchQueue.main` as scheduler keeps UI updates on the main thread.
- For network calls, add **`.flatMap(maxPublishers: .max(1))`** with `switchToLatest`-style handling, or prefer the `task(id:)` version so cancellation is automatic.
- `Task.sleep` throws on cancellation, so `try?` plus a `Task.isCancelled` check is the safe pattern.