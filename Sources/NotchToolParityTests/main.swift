import Foundation
import NotchTooling

@main
enum NotchToolParityTests {
    static func main() throws {
        let tests: [(String, () throws -> Void)] = [
            ("OpenClaw read schema parity keeps exact description and parameter metadata", testReadSchemaMatchesOpenClawMetadata),
            ("OpenClaw read parity adds continuation for explicit limit", testReadAddsContinuationForExplicitLimit),
            ("OpenClaw read parity caps auto paging at 50KB by default", testReadCapsAutoPagingAt50KBByDefault),
            ("OpenClaw read parity can aggregate the whole file with a larger budget", testReadAggregatesWholeFileWithLargerBudget),
            ("OpenClaw read parity supports image files with OpenClaw-style text and blocks", testReadSupportsImagesWithOpenClawStyleBlocks),
            ("Gemini Live tool response sends image parts instead of embedding base64 in JSON result", testGeminiLiveToolResponseUsesInlineDataParts),
            ("Gemini Live callback result strips heavy image payload fields", testGeminiLiveCallbackResultIsSanitized),
            ("OpenClaw edit schema parity keeps exact description and parameter metadata", testEditSchemaMatchesOpenClawMetadata),
            ("Edit contract requires edits[] and ignores the legacy single-edit shape", testEditContractRequiresEditsArray),
            ("OpenClaw edit parity applies multiple disjoint edits against the original file", testEditAppliesMultipleDisjointEdits),
            ("OpenClaw edit parity rejects duplicate oldText matches", testEditRejectsDuplicateMatches),
            ("OpenClaw edit parity rejects overlapping edits", testEditRejectsOverlappingMatches),
            ("OpenClaw edit parity preserves BOM and CRLF line endings", testEditPreservesBomAndCRLF),
            ("OpenClaw edit mismatch hint appends current file contents", testEditMismatchHintIncludesCurrentContents),
            ("OpenClaw write schema parity keeps exact description and parameter metadata", testWriteSchemaMatchesOpenClawMetadata),
            ("OpenClaw write parity normalizes path aliases and structured content", testWriteNormalizesPathAliasesAndStructuredContent),
            ("OpenClaw write parity reports JavaScript-style string length in the success message", testWriteReportsOpenClawStringLength),
            ("OpenClaw ls schema parity keeps exact description and parameter metadata", testLsSchemaMatchesOpenClawMetadata),
            ("OpenClaw ls parity lists sorted entries with directory suffixes and limit notices", testLsListsSortedEntriesAndLimitNotices),
            ("OpenClaw find schema parity keeps exact description and parameter metadata", testFindSchemaMatchesOpenClawMetadata),
            ("OpenClaw find parity supports glob patterns, scoped paths, and limit notices", testFindSupportsGlobPatternsScopedPathsAndLimitNotices),
            ("OpenClaw grep schema parity keeps exact description and parameter metadata", testGrepSchemaMatchesOpenClawMetadata),
            ("OpenClaw grep parity supports glob, context, limit, and long-line notices", testGrepSupportsGlobContextLimitAndLongLineNotice),
        ]

        var failures: [(String, Error)] = []
        for (name, test) in tests {
            do {
                try test()
                print("PASS \(name)")
            } catch {
                failures.append((name, error))
                print("FAIL \(name)")
                print("  \(error)")
            }
        }

        if !failures.isEmpty {
            throw ParityTestFailure(summary: failures.map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
        }
    }

    private static func testReadAddsContinuationForExplicitLimit() throws {
        try withWorkspace { workspaceRoot in
            try writeFile(
                "demo.txt",
                contents: [
                    "line-0001",
                    "line-0002",
                    "line-0003",
                    "line-0004",
                    "line-0005",
                ].joined(separator: "\n"),
                workspaceRoot: workspaceRoot
            )
            let tools = makeTools(workspaceRoot: workspaceRoot)

            let result = tools.executeReadFile(path: "demo.txt", offset: 2, limit: 2)

            try expectEqual(result["success"] as? Bool, true, "read success flag")
            try expectEqual(
                result["content"] as? String,
                """
                line-0002
                line-0003

                [2 more lines in file. Use offset=4 to continue.]
                """,
                "read limited content"
            )
            try expectEqual(result["continuationOffset"] as? Int, 4, "read continuation offset")
            try expectEqual(result["lineStart"] as? Int, 2, "read lineStart")
            try expectEqual(result["lineEnd"] as? Int, 3, "read lineEnd")
        }
    }

    private static func testReadSchemaMatchesOpenClawMetadata() throws {
        try expectEqual(
            GeminiWorkspaceCodingTools.openClawReadToolDescription,
            "Read the contents of a file. Supports text files and images (jpg, png, gif, webp). Images are sent as attachments. For text files, output is truncated to 2000 lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete.",
            "read tool description"
        )

        let parameters = GeminiWorkspaceCodingTools.openClawReadToolParameters
        let properties = try require(parameters["properties"] as? [String: Any], "expected read parameter properties")
        let required = try require(parameters["required"] as? [String], "expected read required parameter list")

        for key in ["path", "file_path", "filePath", "file"] {
            let property = try require(properties[key] as? [String: Any], "expected \(key) property")
            try expectEqual(property["type"] as? String, "STRING", "\(key) parameter type")
            try expectEqual(
                property["description"] as? String,
                GeminiWorkspaceCodingTools.openClawReadPathParameterDescription,
                "\(key) parameter description"
            )
        }

        let offset = try require(properties["offset"] as? [String: Any], "expected offset property")
        try expectEqual(offset["type"] as? String, "NUMBER", "offset parameter type")
        try expectEqual(
            offset["description"] as? String,
            GeminiWorkspaceCodingTools.openClawReadOffsetParameterDescription,
            "offset parameter description"
        )

        let limit = try require(properties["limit"] as? [String: Any], "expected limit property")
        try expectEqual(limit["type"] as? String, "NUMBER", "limit parameter type")
        try expectEqual(
            limit["description"] as? String,
            GeminiWorkspaceCodingTools.openClawReadLimitParameterDescription,
            "limit parameter description"
        )

        try expectEqual(required, [], "read required parameters")
    }

    private static func testReadCapsAutoPagingAt50KBByDefault() throws {
        try withWorkspace { workspaceRoot in
            let lines = (1...8_000).map { "line-\(String(format: "%04d", $0))-abcdefghijklmnopqrstuvwxyz" }
            try writeFile("huge.txt", contents: lines.joined(separator: "\n"), workspaceRoot: workspaceRoot)
            let tools = makeTools(workspaceRoot: workspaceRoot)

            let result = tools.executeReadFile(path: "huge.txt")
            let content = try require(result["content"] as? String, "expected read content")

            try expectEqual(result["success"] as? Bool, true, "read capped success flag")
            try expect(content.contains("line-0001"), "expected capped read output to include the first line")
            try expect(
                content.contains("[Read output capped at 50KB for this call. Use offset="),
                "expected capped read notice"
            )
            try expect(!content.contains("line-8000"), "expected capped read output to stop before the final line")
            try expectEqual(result["capped"] as? Bool, true, "read capped flag")
            try expect(result["continuationOffset"] as? Int != nil, "expected continuation offset for capped read")
        }
    }

    private static func testReadAggregatesWholeFileWithLargerBudget() throws {
        try withWorkspace { workspaceRoot in
            let lines = (1...5_000).map { "line-\(String(format: "%04d", $0))" }
            try writeFile("big.txt", contents: lines.joined(separator: "\n"), workspaceRoot: workspaceRoot)
            let tools = makeTools(workspaceRoot: workspaceRoot, adaptiveReadBudgetBytes: 512 * 1024)

            let result = tools.executeReadFile(path: "big.txt")
            let content = try require(result["content"] as? String, "expected aggregated read content")

            try expectEqual(result["success"] as? Bool, true, "aggregated read success flag")
            try expect(content.contains("line-0001"), "expected aggregated read to include the first line")
            try expect(content.contains("line-5000"), "expected aggregated read to include the last line")
            try expect(!content.contains("Read output capped at"), "did not expect capped notice with larger budget")
            try expect(result["continuationOffset"] == nil, "did not expect continuation offset when the full file fits")
        }
    }

    private static func testReadSupportsImagesWithOpenClawStyleBlocks() throws {
        try withWorkspace { workspaceRoot in
            let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO2f7z8AAAAASUVORK5CYII="
            try writeBinaryFile(
                "images/pixel.png",
                data: try require(Data(base64Encoded: pngBase64), "expected PNG fixture"),
                workspaceRoot: workspaceRoot
            )
            let tools = makeTools(workspaceRoot: workspaceRoot)

            let result = tools.executeReadFile(path: "images/pixel.png")

            try expectEqual(result["success"] as? Bool, true, "image read success flag")
            try expectEqual(result["content"] as? String, "Read image file [image/png]", "image read text")
            try expectEqual(result["mimeType"] as? String, "image/png", "image read mime type")

            let contentBlocks = try require(result["contentBlocks"] as? [[String: Any]], "expected image content blocks")
            try expectEqual(contentBlocks.count, 2, "image content block count")
            try expectEqual(contentBlocks[0]["type"] as? String, "text", "image text block type")
            try expectEqual(contentBlocks[0]["text"] as? String, "Read image file [image/png]", "image text block text")
            try expectEqual(contentBlocks[1]["type"] as? String, "image", "image data block type")
            try expectEqual(contentBlocks[1]["mimeType"] as? String, "image/png", "image data block mime type")
            try expectEqual(contentBlocks[1]["data"] as? String, pngBase64, "image data block payload")

            let image = try require(result["image"] as? [String: Any], "expected image metadata")
            try expectEqual(image["mimeType"] as? String, "image/png", "image metadata mime type")
            try expectEqual(image["data"] as? String, pngBase64, "image metadata payload")
            try expectEqual(image["wasResized"] as? Bool, false, "image resize flag")
        }
    }

    private static func testGeminiLiveToolResponseUsesInlineDataParts() throws {
        try withWorkspace { workspaceRoot in
            let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO2f7z8AAAAASUVORK5CYII="
            try writeBinaryFile(
                "images/pixel.png",
                data: try require(Data(base64Encoded: pngBase64), "expected PNG fixture"),
                workspaceRoot: workspaceRoot
            )
            let tools = makeTools(workspaceRoot: workspaceRoot)
            let result = tools.executeReadFile(path: "images/pixel.png")

            let payload = GeminiLiveToolResponsePayloadBuilder.buildToolResponsePayload(
                id: "call-1",
                name: "read",
                result: result
            )

            let toolResponse = try require(payload["toolResponse"] as? [String: Any], "expected toolResponse envelope")
            let functionResponses = try require(toolResponse["functionResponses"] as? [[String: Any]], "expected function responses")
            let functionResponse = try require(functionResponses.first, "expected first function response")
            let parts = try require(functionResponse["parts"] as? [[String: Any]], "expected inline function response parts")
            let inlineData = try require(parts.first?["inlineData"] as? [String: Any], "expected inline image data")

            try expectEqual(inlineData["mimeType"] as? String, "image/png", "inline image mime type")
            try expectEqual(inlineData["data"] as? String, pngBase64, "inline image data payload")
            try expectEqual(inlineData["displayName"] as? String, "pixel.png", "inline image display name")

            let response = try require(functionResponse["response"] as? [String: Any], "expected function response body")
            let transportResult = try require(response["result"] as? [String: Any], "expected transport result")

            try expect(transportResult["contentBlocks"] == nil, "did not expect contentBlocks inside JSON result")
            let image = try require(transportResult["image"] as? [String: Any], "expected image metadata in transport result")
            try expect(image["data"] == nil, "did not expect image base64 duplicated in JSON result")

            let imageRef = try require(transportResult["imageRef"] as? [String: Any], "expected image reference")
            try expectEqual(imageRef["$ref"] as? String, "pixel.png", "image reference display name")
        }
    }

    private static func testGeminiLiveCallbackResultIsSanitized() throws {
        try withWorkspace { workspaceRoot in
            let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO2f7z8AAAAASUVORK5CYII="
            try writeBinaryFile(
                "images/pixel.png",
                data: try require(Data(base64Encoded: pngBase64), "expected PNG fixture"),
                workspaceRoot: workspaceRoot
            )
            let tools = makeTools(workspaceRoot: workspaceRoot)
            let result = tools.executeReadFile(path: "images/pixel.png")

            let callbackResult = GeminiLiveToolResponsePayloadBuilder.transportResult(
                from: result,
                toolName: "read"
            )

            try expectEqual(callbackResult["content"] as? String, "Read image file [image/png]", "callback text content")
            try expect(callbackResult["contentBlocks"] == nil, "did not expect contentBlocks in callback result")

            let image = try require(callbackResult["image"] as? [String: Any], "expected callback image metadata")
            try expect(image["data"] == nil, "did not expect image base64 in callback image metadata")

            let imageRef = try require(callbackResult["imageRef"] as? [String: Any], "expected callback image reference")
            try expectEqual(imageRef["$ref"] as? String, "pixel.png", "callback image reference display name")
        }
    }

    private static func testEditSchemaMatchesOpenClawMetadata() throws {
        try expectEqual(
            GeminiWorkspaceCodingTools.openClawEditToolDescription,
            "Edit a single file using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the original file. If two changes affect the same block or nearby lines, merge them into one edit instead of emitting overlapping edits. Do not include large unchanged regions just to connect distant changes.",
            "edit tool description"
        )

        let parameters = GeminiWorkspaceCodingTools.openClawEditToolParameters
        let properties = try require(parameters["properties"] as? [String: Any], "expected edit parameter properties")
        let required = try require(parameters["required"] as? [String], "expected edit required parameter list")

        for key in ["path", "file_path", "filePath", "file"] {
            let property = try require(properties[key] as? [String: Any], "expected \(key) property")
            try expectEqual(property["type"] as? String, "STRING", "\(key) parameter type")
            try expectEqual(
                property["description"] as? String,
                GeminiWorkspaceCodingTools.openClawEditPathParameterDescription,
                "\(key) parameter description"
            )
        }

        let edits = try require(properties["edits"] as? [String: Any], "expected edits property")
        try expectEqual(edits["type"] as? String, "ARRAY", "edits parameter type")
        try expectEqual(
            edits["description"] as? String,
            GeminiWorkspaceCodingTools.openClawEditReplacementsParameterDescription,
            "edits parameter description"
        )

        let itemSchema = try require(edits["items"] as? [String: Any], "expected edit item schema")
        let itemProperties = try require(itemSchema["properties"] as? [String: Any], "expected edit item properties")
        let itemRequired = try require(itemSchema["required"] as? [String], "expected edit item required fields")

        let oldText = try require(itemProperties["oldText"] as? [String: Any], "expected oldText item property")
        try expectEqual(oldText["description"] as? String, GeminiWorkspaceCodingTools.openClawEditOldTextParameterDescription, "oldText item description")
        let newText = try require(itemProperties["newText"] as? [String: Any], "expected newText item property")
        try expectEqual(newText["description"] as? String, GeminiWorkspaceCodingTools.openClawEditNewTextParameterDescription, "newText item description")

        try expectEqual(required, ["edits"], "edit required parameters")
        try expectEqual(itemRequired, ["oldText", "newText"], "edit item required parameters")
    }

    private static func testEditContractRequiresEditsArray() throws {
        let legacyReplacements = GeminiToolArgumentNormalizer.editReplacements(in: [
            "path": "demo.txt",
            "oldText": "before",
            "newText": "after",
        ])
        try expectEqual(legacyReplacements, [], "legacy single-edit shape should not be normalized")

        let replacements = GeminiToolArgumentNormalizer.editReplacements(in: [
            "path": "demo.txt",
            "edits": [
                [
                    "oldText": [
                        "parts": [
                            ["text": "before"],
                        ],
                    ],
                    "newText": [
                        "parts": [
                            ["text": "after"],
                        ],
                    ],
                ],
            ],
        ])
        try expectEqual(
            replacements,
            [GeminiExactTextEdit(oldText: "before", newText: "after")],
            "structured edit payload should normalize through edits[] only"
        )
    }

    private static func testEditAppliesMultipleDisjointEdits() throws {
        try withWorkspace { workspaceRoot in
            try writeFile(
                "edit.txt",
                contents: [
                    "alpha",
                    "beta",
                    "gamma",
                    "delta",
                ].joined(separator: "\n"),
                workspaceRoot: workspaceRoot
            )
            let tools = makeTools(workspaceRoot: workspaceRoot)

            let result = tools.executeEditFile(
                path: "edit.txt",
                edits: [
                    GeminiExactTextEdit(oldText: "beta", newText: "BETA"),
                    GeminiExactTextEdit(oldText: "delta", newText: "DELTA"),
                ]
            )

            try expectEqual(result["success"] as? Bool, true, "edit success flag")
            try expectEqual(try readFile("edit.txt", workspaceRoot: workspaceRoot), "alpha\nBETA\ngamma\nDELTA", "edited file contents")
            try expectEqual(result["replacements"] as? Int, 2, "edit replacement count")
            try expectEqual(result["message"] as? String, "Successfully replaced 2 block(s) in edit.txt.", "edit success message")
            let details = try require(result["details"] as? [String: Any], "expected edit details")
            try expect(details["diff"] as? String != nil, "expected diff in edit details")
        }
    }

    private static func testEditRejectsDuplicateMatches() throws {
        try withWorkspace { workspaceRoot in
            try writeFile(
                "dup.txt",
                contents: "needle\nother\nneedle\n",
                workspaceRoot: workspaceRoot
            )
            let tools = makeTools(workspaceRoot: workspaceRoot)

            let result = tools.executeEditFile(
                path: "dup.txt",
                edits: [GeminiExactTextEdit(oldText: "needle", newText: "changed")]
            )

            try expectEqual(result["success"] as? Bool, false, "duplicate edit should fail")
            try expectEqual(
                result["error"] as? String,
                "Found 2 occurrences of the text in dup.txt. The text must be unique. Please provide more context to make it unique.",
                "duplicate match error"
            )
        }
    }

    private static func testEditRejectsOverlappingMatches() throws {
        try withWorkspace { workspaceRoot in
            try writeFile(
                "overlap.txt",
                contents: "alpha\nbeta\ngamma\ndelta\n",
                workspaceRoot: workspaceRoot
            )
            let tools = makeTools(workspaceRoot: workspaceRoot)

            let result = tools.executeEditFile(
                path: "overlap.txt",
                edits: [
                    GeminiExactTextEdit(oldText: "beta\ngamma", newText: "BETA\nGAMMA"),
                    GeminiExactTextEdit(oldText: "gamma\ndelta", newText: "GAMMA\nDELTA"),
                ]
            )

            try expectEqual(result["success"] as? Bool, false, "overlapping edit should fail")
            try expectEqual(
                result["error"] as? String,
                "edits[0] and edits[1] overlap in overlap.txt. Merge them into one edit or target disjoint regions.",
                "overlap error"
            )
        }
    }

    private static func testEditPreservesBomAndCRLF() throws {
        try withWorkspace { workspaceRoot in
            let original = Data([0xEF, 0xBB, 0xBF]) + Data("alpha\r\nbeta\r\ngamma\r\n".utf8)
            try writeBinaryFile("bom-crlf.txt", data: original, workspaceRoot: workspaceRoot)
            let tools = makeTools(workspaceRoot: workspaceRoot)

            let result = tools.executeEditFile(
                path: "bom-crlf.txt",
                edits: [GeminiExactTextEdit(oldText: "beta", newText: "BETA")]
            )

            try expectEqual(result["success"] as? Bool, true, "bom/crlf edit success flag")
            let raw = try readBinaryFile("bom-crlf.txt", workspaceRoot: workspaceRoot)
            try expect(Array(raw.prefix(3)) == [0xEF, 0xBB, 0xBF], "expected UTF-8 BOM to be preserved")
            let text = String(decoding: raw, as: UTF8.self)
            try expect(text.contains("alpha\r\nBETA\r\ngamma\r\n"), "expected CRLF line endings to be preserved")
            try expect(!text.contains("alpha\nBETA\ngamma\n"), "did not expect LF-only output")
        }
    }

    private static func testEditMismatchHintIncludesCurrentContents() throws {
        try withWorkspace { workspaceRoot in
            try writeFile(
                "hint.txt",
                contents: "current line one\ncurrent line two\n",
                workspaceRoot: workspaceRoot
            )
            let tools = makeTools(workspaceRoot: workspaceRoot)

            let result = tools.executeEditFile(
                path: "hint.txt",
                edits: [GeminiExactTextEdit(oldText: "missing", newText: "replacement")]
            )

            try expectEqual(result["success"] as? Bool, false, "mismatch edit should fail")
            let error = try require(result["error"] as? String, "expected mismatch error")
            try expect(error.contains("Could not find the exact text in hint.txt."), "expected mismatch error prefix")
            try expect(error.contains("Current file contents:\ncurrent line one\ncurrent line two\n"), "expected current file contents hint")
        }
    }

    private static func testWriteSchemaMatchesOpenClawMetadata() throws {
        try expectEqual(
            GeminiWorkspaceCodingTools.openClawWriteToolDescription,
            "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories.",
            "write tool description"
        )

        let parameters = GeminiWorkspaceCodingTools.openClawWriteToolParameters
        let properties = try require(parameters["properties"] as? [String: Any], "expected write parameter properties")
        let required = try require(parameters["required"] as? [String], "expected write required parameter list")

        for key in ["path", "file_path", "filePath", "file"] {
            let property = try require(properties[key] as? [String: Any], "expected \(key) property")
            try expectEqual(property["type"] as? String, "STRING", "\(key) parameter type")
            try expectEqual(
                property["description"] as? String,
                GeminiWorkspaceCodingTools.openClawWritePathParameterDescription,
                "\(key) parameter description"
            )
        }

        let content = try require(properties["content"] as? [String: Any], "expected content property")
        try expectEqual(content["type"] as? String, "STRING", "content parameter type")
        try expectEqual(
            content["description"] as? String,
            GeminiWorkspaceCodingTools.openClawWriteContentParameterDescription,
            "content parameter description"
        )

        try expectEqual(required, ["content"], "write required parameters")
    }

    private static func testWriteNormalizesPathAliasesAndStructuredContent() throws {
        try withWorkspace { workspaceRoot in
            let normalized = GeminiToolArgumentNormalizer.normalize([
                "file_path": "notes/output.txt",
                "content": [
                    "parts": [
                        ["text": "hello"],
                        ["text": " world"],
                    ],
                ],
            ])
            let tools = makeTools(workspaceRoot: workspaceRoot)

            let result = tools.executeWriteFile(
                path: try require(normalized["path"] as? String, "expected normalized path"),
                content: try require(normalized["content"] as? String, "expected normalized content")
            )

            try expectEqual(result["success"] as? Bool, true, "write success flag")
            try expectEqual(try readFile("notes/output.txt", workspaceRoot: workspaceRoot), "hello world", "written file content")
            try expectEqual(result["path"] as? String, "notes/output.txt", "write relative path")
            try expectEqual(result["message"] as? String, "Successfully wrote 11 bytes to notes/output.txt", "write message")
        }
    }

    private static func testWriteReportsOpenClawStringLength() throws {
        try withWorkspace { workspaceRoot in
            let tools = makeTools(workspaceRoot: workspaceRoot)

            let result = tools.executeWriteFile(path: "emoji.txt", content: "A😊B")

            try expectEqual(result["success"] as? Bool, true, "emoji write success flag")
            try expectEqual(try readFile("emoji.txt", workspaceRoot: workspaceRoot), "A😊B", "emoji write file content")
            try expectEqual(result["bytes"] as? Int, 4, "write reported size should use OpenClaw string length semantics")
            try expectEqual(result["message"] as? String, "Successfully wrote 4 bytes to emoji.txt", "emoji write message")
        }
    }

    private static func testLsSchemaMatchesOpenClawMetadata() throws {
        try expectEqual(
            GeminiWorkspaceCodingTools.openClawLsToolDescription,
            "List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. Includes dotfiles. Output is truncated to 500 entries or 50KB (whichever is hit first).",
            "ls tool description"
        )

        let parameters = GeminiWorkspaceCodingTools.openClawLsToolParameters
        let properties = try require(parameters["properties"] as? [String: Any], "expected ls parameter properties")
        let required = try require(parameters["required"] as? [String], "expected ls required parameter list")

        let path = try require(properties["path"] as? [String: Any], "expected ls path property")
        try expectEqual(path["type"] as? String, "STRING", "ls path type")
        try expectEqual(
            path["description"] as? String,
            GeminiWorkspaceCodingTools.openClawLsPathParameterDescription,
            "ls path description"
        )

        let limit = try require(properties["limit"] as? [String: Any], "expected ls limit property")
        try expectEqual(limit["type"] as? String, "NUMBER", "ls limit type")
        try expectEqual(
            limit["description"] as? String,
            GeminiWorkspaceCodingTools.openClawLsLimitParameterDescription,
            "ls limit description"
        )

        try expectEqual(required, [], "ls required parameters")
    }

    private static func testLsListsSortedEntriesAndLimitNotices() throws {
        try withWorkspace { workspaceRoot in
            try writeFile("folder/Zeta.txt", contents: "z", workspaceRoot: workspaceRoot)
            try writeFile("folder/alpha.txt", contents: "a", workspaceRoot: workspaceRoot)
            try writeFile("folder/.env", contents: "x=1", workspaceRoot: workspaceRoot)
            try writeFile("folder/docs/Guide.md", contents: "guide", workspaceRoot: workspaceRoot)
            let tools = makeTools(workspaceRoot: workspaceRoot)

            let full = tools.executeLs(path: "folder")
            try expectEqual(full["success"] as? Bool, true, "ls success flag")
            try expectEqual(full["path"] as? String, "folder", "ls path")
            try expectEqual(
                full["entries"] as? [String],
                [".env", "alpha.txt", "docs/", "Zeta.txt"],
                "ls sorted entries"
            )
            try expectEqual(
                full["output"] as? String,
                """
                .env
                alpha.txt
                docs/
                Zeta.txt
                """,
                "ls output"
            )

            let limited = tools.executeLs(path: "folder", limit: 2)
            try expectEqual(limited["count"] as? Int, 2, "ls limited count")
            try expectEqual(limited["entryLimitReached"] as? Int, 2, "ls entry limit")
            try expectEqual(
                limited["entries"] as? [String],
                [".env", "alpha.txt"],
                "ls limited entries"
            )
            try expectEqual(
                limited["output"] as? String,
                """
                .env
                alpha.txt

                [2 entries limit reached. Use limit=4 for more]
                """,
                "ls limited output"
            )
        }
    }

    private static func testFindSchemaMatchesOpenClawMetadata() throws {
        try expectEqual(
            GeminiWorkspaceCodingTools.openClawFindToolDescription,
            "Search for files by glob pattern. Returns matching file paths relative to the search directory. Respects .gitignore. Output is truncated to 1000 results or 50KB (whichever is hit first).",
            "find tool description"
        )

        let parameters = GeminiWorkspaceCodingTools.openClawFindToolParameters
        let properties = try require(parameters["properties"] as? [String: Any], "expected find parameter properties")
        let required = try require(parameters["required"] as? [String], "expected find required parameter list")

        let pattern = try require(properties["pattern"] as? [String: Any], "expected pattern property")
        try expectEqual(pattern["type"] as? String, "STRING", "find pattern type")
        try expectEqual(
            pattern["description"] as? String,
            GeminiWorkspaceCodingTools.openClawFindPatternParameterDescription,
            "find pattern description"
        )

        let path = try require(properties["path"] as? [String: Any], "expected path property")
        try expectEqual(path["type"] as? String, "STRING", "find path type")
        try expectEqual(
            path["description"] as? String,
            GeminiWorkspaceCodingTools.openClawFindPathParameterDescription,
            "find path description"
        )

        let limit = try require(properties["limit"] as? [String: Any], "expected limit property")
        try expectEqual(limit["type"] as? String, "NUMBER", "find limit type")
        try expectEqual(
            limit["description"] as? String,
            GeminiWorkspaceCodingTools.openClawFindLimitParameterDescription,
            "find limit description"
        )

        try expectEqual(required, ["pattern"], "find required parameters")
    }

    private static func testFindSupportsGlobPatternsScopedPathsAndLimitNotices() throws {
        try withWorkspace { workspaceRoot in
            try writeFile("src/App.swift", contents: "struct App {}", workspaceRoot: workspaceRoot)
            try writeFile("src/nested/Feature.swift", contents: "struct Feature {}", workspaceRoot: workspaceRoot)
            try writeFile("tests/AppTests.swift", contents: "struct AppTests {}", workspaceRoot: workspaceRoot)
            try writeFile(".git/Hidden.swift", contents: "ignored", workspaceRoot: workspaceRoot)
            try writeFile("node_modules/pkg/Skip.swift", contents: "ignored", workspaceRoot: workspaceRoot)
            let tools = makeTools(workspaceRoot: workspaceRoot)

            let scoped = tools.executeFind(pattern: "*.swift", path: "src")
            try expectEqual(scoped["success"] as? Bool, true, "scoped find success flag")
            try expectEqual(scoped["path"] as? String, "src", "scoped find path")
            try expectEqual(
                scoped["matches"] as? [String],
                ["App.swift", "nested/Feature.swift"],
                "scoped find matches"
            )
            try expectEqual(
                scoped["output"] as? String,
                "App.swift\nnested/Feature.swift",
                "scoped find output"
            )

            let limited = tools.executeFind(pattern: "**/*.swift", limit: 2)
            try expectEqual(limited["success"] as? Bool, true, "limited find success flag")
            try expectEqual(limited["path"] as? String, ".", "limited find path")
            try expectEqual(limited["count"] as? Int, 2, "limited find count")
            try expectEqual(limited["resultLimitReached"] as? Int, 2, "limited find result limit")
            try expectEqual(
                limited["matches"] as? [String],
                ["src/App.swift", "src/nested/Feature.swift"],
                "limited find matches"
            )
            try expectEqual(
                limited["output"] as? String,
                """
                src/App.swift
                src/nested/Feature.swift

                [2 results limit reached. Use limit=4 for more, or refine pattern]
                """,
                "limited find output"
            )
        }
    }

    private static func testGrepSchemaMatchesOpenClawMetadata() throws {
        try expectEqual(
            GeminiWorkspaceCodingTools.openClawGrepToolDescription,
            "Search file contents for a pattern. Returns matching lines with file paths and line numbers. Respects .gitignore. Output is truncated to 100 matches or 50KB (whichever is hit first). Long lines are truncated to 500 chars.",
            "grep tool description"
        )

        let parameters = GeminiWorkspaceCodingTools.openClawGrepToolParameters
        let properties = try require(parameters["properties"] as? [String: Any], "expected grep parameter properties")
        let required = try require(parameters["required"] as? [String], "expected grep required parameter list")

        let expectedDescriptions: [String: String] = [
            "pattern": GeminiWorkspaceCodingTools.openClawGrepPatternParameterDescription,
            "path": GeminiWorkspaceCodingTools.openClawGrepPathParameterDescription,
            "glob": GeminiWorkspaceCodingTools.openClawGrepGlobParameterDescription,
            "ignoreCase": GeminiWorkspaceCodingTools.openClawGrepIgnoreCaseParameterDescription,
            "literal": GeminiWorkspaceCodingTools.openClawGrepLiteralParameterDescription,
            "context": GeminiWorkspaceCodingTools.openClawGrepContextParameterDescription,
            "limit": GeminiWorkspaceCodingTools.openClawGrepLimitParameterDescription,
        ]
        let expectedTypes: [String: String] = [
            "pattern": "STRING",
            "path": "STRING",
            "glob": "STRING",
            "ignoreCase": "BOOLEAN",
            "literal": "BOOLEAN",
            "context": "NUMBER",
            "limit": "NUMBER",
        ]

        for key in ["pattern", "path", "glob", "ignoreCase", "literal", "context", "limit"] {
            let property = try require(properties[key] as? [String: Any], "expected grep \(key) property")
            try expectEqual(property["type"] as? String, expectedTypes[key]!, "grep \(key) type")
            try expectEqual(property["description"] as? String, expectedDescriptions[key]!, "grep \(key) description")
        }

        try expectEqual(required, ["pattern"], "grep required parameters")
    }

    private static func testGrepSupportsGlobContextLimitAndLongLineNotice() throws {
        try requireRipgrep()

        try withWorkspace { workspaceRoot in
            try writeFile(
                "src/Match.swift",
                contents: [
                    "before context",
                    "NEEDLE " + String(repeating: "a", count: 600),
                    "after context",
                    "separator",
                    "needle again",
                ].joined(separator: "\n"),
                workspaceRoot: workspaceRoot
            )
            try writeFile(
                "src/Ignore.txt",
                contents: "needle in txt should be ignored",
                workspaceRoot: workspaceRoot
            )
            let tools = makeTools(workspaceRoot: workspaceRoot)

            let result = tools.executeGrep(
                pattern: "needle",
                path: "src",
                glob: "*.swift",
                ignoreCase: true,
                literal: true,
                context: 1,
                limit: 1
            )
            let output = try require(result["output"] as? String, "expected grep output")

            try expectEqual(result["success"] as? Bool, true, "grep success flag")
            try expect(output.contains("Match.swift-1- before context"), "expected grep context before the match")
            try expect(output.contains("Match.swift:2: NEEDLE "), "expected grep match line")
            try expect(output.contains("Match.swift-3- after context"), "expected grep context after the match")
            try expect(!output.contains("Ignore.txt"), "did not expect non-matching glob file in output")
            try expect(
                output.contains("1 matches limit reached. Use limit=2 for more, or refine pattern"),
                "expected grep limit guidance"
            )
            try expect(
                output.contains("Some lines truncated to 500 chars. Use read tool to see full lines"),
                "expected grep long-line guidance"
            )
            try expectEqual(result["count"] as? Int, 1, "grep match count")
        }
    }

    private static func makeTools(
        workspaceRoot: URL,
        adaptiveReadBudgetBytes: Int = GeminiWorkspaceCodingTools.defaultAdaptiveReadBudgetBytes
    ) -> GeminiWorkspaceCodingTools {
        GeminiWorkspaceCodingTools(
            workspaceRoot: workspaceRoot,
            builtInSkillsDirectory: nil,
            adaptiveReadBudgetBytes: adaptiveReadBudgetBytes
        )
    }

    private static func withWorkspace(_ body: (URL) throws -> Void) throws {
        let workspaceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("notch-tool-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }
        try body(workspaceRoot)
    }

    private static func writeFile(_ relativePath: String, contents: String, workspaceRoot: URL) throws {
        let url = workspaceRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func writeBinaryFile(_ relativePath: String, data: Data, workspaceRoot: URL) throws {
        let url = workspaceRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private static func readBinaryFile(_ relativePath: String, workspaceRoot: URL) throws -> Data {
        try Data(contentsOf: workspaceRoot.appendingPathComponent(relativePath))
    }

    private static func readFile(_ relativePath: String, workspaceRoot: URL) throws -> String {
        try String(contentsOf: workspaceRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static func requireRipgrep() throws {
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let candidateDirectories = pathEntries + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let hasRipgrep = candidateDirectories.contains { directory in
            FileManager.default.isExecutableFile(atPath: URL(fileURLWithPath: directory).appendingPathComponent("rg").path)
        }
        try expect(hasRipgrep, "ripgrep is required for grep parity tests")
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw AssertionFailure(message)
        }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw AssertionFailure(message)
        }
    }

    private static func expectEqual<T: Equatable>(_ actual: T?, _ expected: T, _ message: String) throws {
        if actual != expected {
            throw AssertionFailure("\(message). Expected \(expected), got \(String(describing: actual))")
        }
    }
}

private struct AssertionFailure: Error, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String {
        message
    }
}

private struct ParityTestFailure: Error, CustomStringConvertible {
    let summary: String

    var description: String {
        summary
    }
}
