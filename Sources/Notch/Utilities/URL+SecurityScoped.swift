import Foundation

extension URL {
    func accessSecurityScopedResource<Value>(accessor: (URL) throws -> Value) rethrows -> Value {
        let didStartAccessing = startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                stopAccessingSecurityScopedResource()
            }
        }

        return try accessor(self)
    }

    func accessSecurityScopedResource<Value>(accessor: (URL) async throws -> Value) async rethrows -> Value {
        let didStartAccessing = startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                stopAccessingSecurityScopedResource()
            }
        }

        return try await accessor(self)
    }
}
