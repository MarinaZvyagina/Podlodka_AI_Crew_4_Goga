// Auto-generated fixture for validators/task_A_functional.sh — not part of any submitted solution.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/
//
// Black-box functional regression test for R09 Task A ("Orphaned backup files after removing a
// browser window's saved tab data"). This test is intentionally independent of any specific
// candidate implementation: it only calls the public TabDataStore API
// (DefaultTabDataStore.removeWindowData(forUUIDs:)) and observes effects through the pre-existing
// MockTabFileManager test double (BrowserKit/Tests/TabDataStoreTests/Mocks/MockTabFileManager.swift),
// never touching any candidate-specific private helper. Any correct fix — regardless of how it is
// internally structured — must make these assertions pass; any implementation that doesn't actually
// clean up the backup file will fail testRemoveWindowData_removesBothPrimaryAndBackupFiles.

import XCTest
import TestKit
@testable import TabDataStore

final class R09TaskAFunctionalTests: XCTestCase, @unchecked Sendable {
    private let uuidToRemove = UUID(uuidString: "E3FF60DA-D1E7-407B-AA3B-130D48B3909D")!
    private let otherUUID = UUID(uuidString: "ABFF60DA-D1E7-407B-AA3B-130D48B31012")!

    /// Functional requirement: "Calling removeWindowData(forUUIDs:) removes both the primary
    /// window-data file AND the corresponding backup window-data file for each UUID in the list."
    func testRemoveWindowData_removesBothPrimaryAndBackupFiles() async throws {
        let mockFileManager = MockTabFileManager()
        mockFileManager.primaryDirectoryURL = URL(string: "some/primary")
        mockFileManager.backupDirectoryURL = URL(string: "some/backup")
        // MockTabFileManager.contentsOfDirectory(at:) returns this same list regardless of which
        // directory URL is passed in, so seeding it once here simulates "this window's file exists
        // in both the primary and backup directory listings" — exactly the on-disk state described
        // in the ticket (a stale backup left behind after the primary copy is removed).
        mockFileManager.pathContents = [
            URL(string: "some/primary/window-\(uuidToRemove.uuidString)")!,
            URL(string: "some/primary/window-\(otherUUID.uuidString)")!
        ]

        let subject = DefaultTabDataStore(fileManager: mockFileManager, throttleTime: 100)

        await subject.removeWindowData(forUUIDs: [uuidToRemove])

        XCTAssertEqual(
            mockFileManager.removeFileAtPathCalledCount,
            2,
            "Expected removeFileAt(path:) once for the primary-directory match and once for the " +
            "backup-directory match; got \(mockFileManager.removeFileAtPathCalledCount). This means " +
            "backup files are not being cleaned up alongside primary files (the ticket's core bug)."
        )
    }

    /// Functional requirement: "If a window has no backup file on disk... removal completes
    /// without throwing/crashing."
    func testRemoveWindowData_noBackupFilePresent_doesNotThrowOrCrash() async throws {
        let mockFileManager = MockTabFileManager()
        mockFileManager.primaryDirectoryURL = URL(string: "some/primary")
        mockFileManager.backupDirectoryURL = URL(string: "some/backup")
        // Only the primary directory has a matching file; the backup directory listing is empty.
        mockFileManager.pathContents = [URL(string: "some/primary/window-\(uuidToRemove.uuidString)")!]

        let subject = DefaultTabDataStore(fileManager: mockFileManager, throttleTime: 100)

        await subject.removeWindowData(forUUIDs: [uuidToRemove])

        XCTAssertGreaterThanOrEqual(mockFileManager.removeFileAtPathCalledCount, 1)
    }

    /// Functional requirement: "Windows whose UUID is not in the forUUIDs list are left untouched,
    /// including their backup files."
    func testRemoveWindowData_untouchedWindow_isNotRemovedFromEitherDirectory() async throws {
        let mockFileManager = MockTabFileManager()
        mockFileManager.primaryDirectoryURL = URL(string: "some/primary")
        mockFileManager.backupDirectoryURL = URL(string: "some/backup")
        mockFileManager.pathContents = [URL(string: "some/primary/window-\(otherUUID.uuidString)")!]

        let subject = DefaultTabDataStore(fileManager: mockFileManager, throttleTime: 100)

        // Removing a UUID that isn't present should not touch the unrelated window's files.
        await subject.removeWindowData(forUUIDs: [uuidToRemove])

        XCTAssertEqual(mockFileManager.removeFileAtPathCalledCount, 0)
    }

    /// Functional requirement: "clearAllWindowsData() behaviour... is unaffected." A quick
    /// regression guard that the unrelated bulk-clear path still touches both directories wholesale
    /// via the same fileManager abstraction (unchanged from the pre-existing implementation).
    func testClearAllWindowsData_stillClearsBothDirectoriesWholesale() async throws {
        let mockFileManager = MockTabFileManager()
        mockFileManager.primaryDirectoryURL = URL(string: "some/primary")
        mockFileManager.backupDirectoryURL = URL(string: "some/backup")

        let subject = DefaultTabDataStore(fileManager: mockFileManager, throttleTime: 100)

        await subject.clearAllWindowsData()

        XCTAssertEqual(mockFileManager.removeAllFilesAtCalledCount, 2)
    }
}
