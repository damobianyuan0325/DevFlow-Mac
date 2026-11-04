import SwiftUI
import DevFlowCore

/// Only the visible slice invokes row builders, including nested links and details.
struct PagedItems<Item, ID: Hashable, Row: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    var pageSize = 10
    @ViewBuilder let row: (Item) -> Row
    @State private var page = 0
    var body: some View {
        let window = PageWindow(count: items.count, requestedPage: page, pageSize: pageSize)
        VStack(alignment: .leading, spacing: 12) {
            if items.count > pageSize {
                HStack {
                    Text("共 \(items.count) 项 · 第 \(window.page + 1)/\(window.pageCount) 页").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("首页") { page = 0 }.disabled(window.page == 0)
                    Button("上一页") { page = window.page - 1 }.disabled(window.page == 0)
                    Button("下一页") { page = window.page + 1 }.disabled(window.page + 1 == window.pageCount)
                    Button("末页") { page = window.pageCount - 1 }.disabled(window.page + 1 == window.pageCount)
                }
            }
            ForEach(Array(items[window.range]), id: id) { item in row(item) }
        }
        .onChange(of: items.count) { _, count in
            page = PageWindow(count: count, requestedPage: page, pageSize: pageSize).page
        }
    }
}

struct DeferredDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = false
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.content = content
    }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if expanded { content() }
        } label: { Text(title).handCursor() }
    }
}
