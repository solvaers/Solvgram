import Foundation

/// A merged version retains its source indices so file manifests can keep the
/// corresponding transition dates. Equal text may recur in a real edit history.
struct SolvgramHistoryVersion {
    let text: String
    let previousIndex: Int?
    let incomingIndex: Int?
}

/// Merge overlapping histories, including bounded server windows that retain
/// the original text and drop intermediate versions. Inputs are bounded before
/// the sequence table is allocated. Ambiguous gaps follow the snapshot's age.
func solvgramMergeHistory(_ previous: [String], _ incoming: [String], limit: Int, incomingIsNewer: Bool) -> [SolvgramHistoryVersion] {
    let limit = min(100, max(1, limit))
    func indices(_ texts: [String]) -> [Int] {
        if texts.count <= limit { return Array(texts.indices) }
        return [0] + Array(texts.indices.suffix(limit - 1))
    }
    let old = indices(previous)
    let new = indices(incoming)
    if old.count == new.count && zip(old, new).allSatisfy({ previous[$0.0] == incoming[$0.1] }) {
        return zip(old, new).map { SolvgramHistoryVersion(text: previous[$0.0], previousIndex: $0.0, incomingIndex: $0.1) }
    }
    let width = new.count + 1
    var lengths = [Int](repeating: 0, count: (old.count + 1) * width)
    for i in old.indices.reversed() {
        for j in new.indices.reversed() {
            lengths[i * width + j] = previous[old[i]] == incoming[new[j]]
                ? 1 + lengths[(i + 1) * width + j + 1]
                : max(lengths[(i + 1) * width + j], lengths[i * width + j + 1])
        }
    }
    var result: [SolvgramHistoryVersion] = []
    var i = 0
    var j = 0
    while i < old.count || j < new.count {
        if i < old.count, j < new.count, previous[old[i]] == incoming[new[j]] {
            result.append(SolvgramHistoryVersion(text: previous[old[i]], previousIndex: old[i], incomingIndex: new[j]))
            i += 1; j += 1
        } else if i < old.count && (j == new.count || lengths[(i + 1) * width + j] > lengths[i * width + j + 1] || lengths[(i + 1) * width + j] == lengths[i * width + j + 1] && incomingIsNewer) {
            result.append(SolvgramHistoryVersion(text: previous[old[i]], previousIndex: old[i], incomingIndex: nil))
            i += 1
        } else {
            result.append(SolvgramHistoryVersion(text: incoming[new[j]], previousIndex: nil, incomingIndex: new[j]))
            j += 1
        }
    }
    if result.count > limit { result = [result[0]] + result.suffix(limit - 1) }
    return result
}
