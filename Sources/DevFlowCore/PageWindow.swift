/// A bounded display window; never changes or drops source records.
public struct PageWindow {
    public let page: Int
    public let pageCount: Int
    public let range: Range<Int>
    public init(count: Int, requestedPage: Int, pageSize: Int = 10) {
        let total = max(0, count), size = max(1, pageSize)
        pageCount = total == 0 ? 1 : (total - 1) / size + 1
        page = min(max(0, requestedPage), pageCount - 1)
        let start = page * size
        range = start..<min(total, start + min(size, total - start))
    }
}
