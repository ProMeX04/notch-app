import XCTest
import Foundation
@testable import Notch

final class NowPlayingControllerTests: XCTestCase {
    private var tempDir: URL!
    private var logFileURL: URL!

    override func setUp() {
        super.setUp()
        // Create a unique temporary directory for this test run
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        logFileURL = tempDir.appendingPathComponent("command_log.txt")
        setenv("TEST_COMMAND_LOG_FILE", logFileURL.path, 1)

        // Write a dummy mediaremote-adapter.pl perl script
        let dummyPl = """
        #!/usr/bin/perl
        use strict;
        use warnings;
        my $log_file = $ENV{TEST_COMMAND_LOG_FILE};
        if ($log_file) {
            open(my $fh, '>>', $log_file) or die $!;
            print $fh join(' ', @ARGV) . "\\n";
            close($fh);
        }
        while (my $line = <STDIN>) {
            if ($log_file) {
                open(my $fh, '>>', $log_file) or die $!;
                print $fh $line;
                close($fh);
            }
        }
        """
        let scriptURL = tempDir.appendingPathComponent("mediaremote-adapter.pl")
        try! dummyPl.write(to: scriptURL, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // Create dummy MediaRemoteAdapter.framework directory so ProbeResources validation passes
        let frameworkURL = tempDir.appendingPathComponent("MediaRemoteAdapter.framework")
        try! FileManager.default.createDirectory(at: frameworkURL, withIntermediateDirectories: true)
        let dummyFile = frameworkURL.appendingPathComponent("dummy")
        try! "dummy".write(to: dummyFile, atomically: true, encoding: .utf8)

        // Point ProbeResources to our temporary directory
        setenv("NOTCH_RESOURCES_BUNDLE_PATH", tempDir.path, 1)
    }

    override func tearDown() {
        unsetenv("TEST_COMMAND_LOG_FILE")
        unsetenv("NOTCH_RESOURCES_BUNDLE_PATH")
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    func testCommandsAreGuardedWhenNoMetadataAndNoRunningApp() async throws {
        let controller = try XCTUnwrap(NowPlayingController())

        // Set state to have NO track metadata and NO running source app
        var state = PlaybackState(bundleIdentifier: "com.apple.Music")
        state.title = "Nothing Playing" // no track metadata
        controller.setPlaybackStateForTesting(state)

        // Execute play
        await controller.play()

        // Wait a tiny bit and verify no process ran the play command (log file should not contain 'send 0')
        try? await Task.sleep(nanoseconds: 100_000_000)
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            let content = try String(contentsOf: logFileURL, encoding: .utf8)
            XCTAssertFalse(content.contains("send 0"), "Command 'send 0' should have been guarded and not executed")
        }
    }

    @MainActor
    func testCommandsAreAllowedWithTrackMetadata() async throws {
        let controller = try XCTUnwrap(NowPlayingController())

        // Set state to have track metadata
        var state = PlaybackState(bundleIdentifier: "com.apple.Music")
        state.title = "Hello World"
        state.artist = "Some Artist"
        controller.setPlaybackStateForTesting(state)

        // Execute play
        await controller.play()

        // Wait a bit and verify the perl script was executed
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFileURL.path), "Command should have run")
        let content = try String(contentsOf: logFileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("send 0"), "Log content should record 'send 0' execution, got: \(content)")
    }
}
