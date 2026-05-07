import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct SpotlightTestView: View {
    @State private var query = ""
    @State private var results: [[String: Any]] = []
    @State private var isSearching = false
    @State private var scope = "home"
    @State private var kind = "any"
    
    private let manager = SpotlightManager()
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search files, apps, docs...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .onSubmit {
                        runSearch()
                    }
                
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Filters
            HStack {
                Picker("Scope", selection: $scope) {
                    Text("Home").tag("home")
                    Text("Apps").tag("applications")
                    Text("Docs").tag("documents")
                    Text("Desktop").tag("desktop")
                    Text("All").tag("all")
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                
                Picker("Kind", selection: $kind) {
                    Text("Any").tag("any")
                    Text("App").tag("app")
                    Text("Folder").tag("folder")
                    Text("Doc").tag("document")
                    Text("PDF").tag("pdf")
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                
                Spacer()
                
                Button("Search") {
                    runSearch()
                }
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Results List
            List {
                if results.isEmpty && !query.isEmpty && !isSearching {
                    Text("No results found.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(0..<results.count, id: \.self) { index in
                        let item = results[index]
                        SearchResultRow(item: item)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
    
    private func runSearch() {
        guard !query.isEmpty else { return }
        isSearching = true
        
        // Capture values on the Main Actor before going to background
        let currentQuery = query
        let currentScope = scope
        let currentKind = kind
        
        // Run on background thread to not freeze UI
        DispatchQueue.global(qos: .userInitiated).async {
            let result = manager.search(
                query: currentQuery,
                limit: 50,
                scope: currentScope,
                kind: currentKind
            )
            
            DispatchQueue.main.async {
                self.results = (result["results"] as? [[String: Any]]) ?? []
                self.isSearching = false
            }
        }
    }
}

struct SearchResultRow: View {
    let item: [String: Any]
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            let path = item["path"] as? String ?? ""
            let icon: NSImage = {
                if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                    return NSWorkspace.shared.icon(forFile: path)
                }
                return NSWorkspace.shared.icon(for: .data)
            }()
            
            Image(nsImage: icon)
                .resizable()
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item["name"] as? String ?? "Unknown")
                    .font(.headline)
                
                Text(path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if let date = item["modifiedAt"] as? String {
                    Text("Modified: \(date)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .onTapGesture(count: 2) {
            if let path = item["path"] as? String {
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            }
        }
        .contextMenu {
            Button("Open File") {
                if let path = item["path"] as? String {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
            }
            Button("Show in Finder") {
                if let path = item["path"] as? String {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
            }
            Button("Copy Path") {
                if let path = item["path"] as? String {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
            }
        }
    }
}
