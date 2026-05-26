import Foundation
import XCTest
@testable import Notch

final class NowPlayingStateReducerTests: XCTestCase {
    private let timestampFormatter = ISO8601DateFormatter()

    func testFullSnapshotCreatesMediaState() throws {
        let update = try decodeUpdate(
            diff: false,
            payload: """
            {
                "title": "Track",
                "artist": "Artist",
                "bundleIdentifier": "com.spotify.client",
                "playing": true,
                "duration": 120,
                "artworkData": "\(Data("art".utf8).base64EncodedString())"
            }
            """
        )

        let state = NowPlayingStateReducer.reduce(
            previousState: PlaybackState(bundleIdentifier: ""),
            update: update,
            timestampFormatter: timestampFormatter
        )

        XCTAssertEqual(state.title, "Track")
        XCTAssertEqual(state.artist, "Artist")
        XCTAssertEqual(state.bundleIdentifier, "com.spotify.client")
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.duration, 120)
        XCTAssertEqual(state.artwork, Data("art".utf8))
    }

    func testDiffPlaybackChangePreservesMetadataAndArtwork() throws {
        var previous = PlaybackState(bundleIdentifier: "com.apple.Music")
        previous.title = "Track"
        previous.artist = "Artist"
        previous.artwork = Data("art".utf8)
        previous.isPlaying = true

        let update = try decodeUpdate(diff: true, payload: #"{"playing": false}"#)
        let state = NowPlayingStateReducer.reduce(
            previousState: previous,
            update: update,
            timestampFormatter: timestampFormatter
        )

        XCTAssertEqual(state.title, previous.title)
        XCTAssertEqual(state.artist, previous.artist)
        XCTAssertEqual(state.bundleIdentifier, previous.bundleIdentifier)
        XCTAssertEqual(state.artwork, previous.artwork)
        XCTAssertFalse(state.isPlaying)
    }

    func testDiffNullFieldsClearMediaStateAndArtwork() throws {
        var previous = PlaybackState(bundleIdentifier: "com.apple.Music")
        previous.title = "Track"
        previous.artist = "Artist"
        previous.album = "Album"
        previous.duration = 120
        previous.artwork = Data("art".utf8)
        previous.isPlaying = true

        let update = try decodeUpdate(
            diff: true,
            payload: """
            {
                "title": null,
                "artist": null,
                "album": null,
                "duration": null,
                "artworkData": null,
                "bundleIdentifier": null,
                "parentApplicationBundleIdentifier": null,
                "playing": false
            }
            """
        )
        let state = NowPlayingStateReducer.reduce(
            previousState: previous,
            update: update,
            timestampFormatter: timestampFormatter
        )

        XCTAssertEqual(state.title, "Nothing Playing")
        XCTAssertEqual(state.artist, "Notch")
        XCTAssertEqual(state.album, "")
        XCTAssertEqual(state.bundleIdentifier, "")
        XCTAssertNil(state.artwork)
        XCTAssertFalse(state.hasMediaContext)
    }

    func testEmptySnapshotResetsToNothingPlaying() throws {
        var previous = PlaybackState(bundleIdentifier: "com.spotify.client")
        previous.title = "Track"
        previous.artwork = Data("art".utf8)
        previous.isPlaying = true

        let update = try decodeUpdate(diff: false, payload: "{}")
        let state = NowPlayingStateReducer.reduce(
            previousState: previous,
            update: update,
            timestampFormatter: timestampFormatter
        )

        XCTAssertEqual(state.title, "Nothing Playing")
        XCTAssertEqual(state.bundleIdentifier, "")
        XCTAssertNil(state.artwork)
        XCTAssertFalse(state.isPlaying)
        XCTAssertFalse(state.hasMediaContext)
    }

    private func decodeUpdate(diff: Bool, payload: String) throws -> NowPlayingUpdate {
        let data = """
        {"payload": \(payload), "diff": \(diff)}
        """.data(using: .utf8)!
        return try JSONDecoder().decode(NowPlayingUpdate.self, from: data)
    }
}
