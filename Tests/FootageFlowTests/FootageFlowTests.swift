import Foundation
import XCTest
@testable import FootageFlow

final class FootageFlowTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testPexelsFixture() throws {
        let response = try JSONDecoder().decode(PexelsVideoResponse.self, from: fixture("pexels-video"))
        XCTAssertEqual(response.videos.first?.id, 7)
        XCTAssertEqual(response.videos.first?.videoFiles.first?.width, 1920)
    }

    func testPixabayFixture() throws {
        let response = try JSONDecoder().decode(PixabayVideoResponse.self, from: fixture("pixabay-video"))
        XCTAssertEqual(response.hits.first?.duration, 12)
        XCTAssertEqual(response.hits.first?.videos.medium?.height, 1080)
    }

    func testWikimediaFixture() throws {
        let response = try JSONDecoder().decode(WikimediaResponse.self, from: fixture("wikimedia"))
        XCTAssertEqual(response.query?.pages.first?.imageinfo?.first?.mime, "image/jpeg")
        XCTAssertEqual(response.query?.pages.first?.imageinfo?.first?.extmetadata?["LicenseShortName"]?.value, "CC BY 4.0")
    }

    func testYouTubeAndArchiveFixtures() throws {
        let youtube = try JSONDecoder().decode(YouTubeSearchResponse.self, from: fixture("youtube"))
        XCTAssertEqual(youtube.items.first?.id.videoId, "abc")
        let archive = try JSONSerialization.jsonObject(with: fixture("internet-archive")) as? [String: Any]
        let docs = (archive?["response"] as? [String: Any])?["docs"] as? [[String: Any]]
        XCTAssertEqual(docs?.first?["identifier"] as? String, "item1")
    }

    func testUnifiedModelAndDeduplication() throws {
        let asset = sampleAsset()
        let decoded = try JSONDecoder().decode(MediaAsset.self, from: JSONEncoder().encode(asset))
        XCTAssertEqual(decoded, asset)
        XCTAssertEqual(SearchDeduplicator.apply([asset, asset]).count, 1)
    }

    func testLicenseMapping() {
        XCTAssertEqual(ProviderUtilities.licenseStatus(name: "CC BY-SA 4.0"), .attributionRequired)
        XCTAssertEqual(ProviderUtilities.licenseStatus(name: "Public Domain"), .publicDomain)
        XCTAssertEqual(ProviderUtilities.licenseStatus(name: nil), .unknown)
    }

    func testFilenameAndKeywords() {
        XCTAssertFalse(FileNameSanitizer.sanitize("银行/挤兑:2001?.mp4").contains("/"))
        XCTAssertGreaterThanOrEqual(KeywordEngine.keywords(for: "2001年阿根廷银行挤兑").count, 3)
        XCTAssertGreaterThanOrEqual(KeywordEngine.splitScript("第一句话。第二句话。\n\n第三段。").count, 2)
    }

    func testURLValidationAndLogRedaction() throws {
        XCTAssertEqual(try URLValidator.remote(URL(string: "https://example.com/file.mp4")).host, "example.com")
        XCTAssertThrowsError(try URLValidator.remote(URL(string: "http://example.com/file.mp4")))
        XCTAssertThrowsError(try URLValidator.remote(URL(string: "https://user:secret@example.com/file.mp4")))
        XCTAssertFalse(AppLogger.redact("Authorization: Bearer secret-token-value").contains("secret-token-value"))
    }

    func testLegacyDatabaseMigrationPreservesSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("legacy.json")
        let current = directory.appendingPathComponent("current.json")
        try Data("legacy-data".utf8).write(to: legacy)
        DataStore.migrateDatabaseIfNeeded(current: current, legacy: legacy)
        XCTAssertEqual(try String(contentsOf: current, encoding: .utf8), "legacy-data")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    @MainActor func testProjectCRUDAndPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("database.json")
        let first = DataStore(fileURL: databaseURL)
        let project = first.addProject(name: "Test Project")
        first.toggleFavorite(asset: sampleAsset(), projectID: project.id)
        let reopened = DataStore(fileURL: databaseURL)
        XCTAssertEqual(reopened.projects.first?.name, "Test Project")
        XCTAssertEqual(reopened.favorites.count, 1)
        reopened.deleteProject(id: project.id)
        XCTAssertTrue(reopened.projects.isEmpty)
        XCTAssertNil(reopened.favorites.first?.projectID)
    }

    func testSidecarGeneration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mediaURL = directory.appendingPathComponent("test.mp4")
        try SourceSidecar.write(asset: sampleAsset(), mediaURL: mediaURL, projectName: "Test", segmentIndex: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("test.source.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("test.source.json").path))
    }

    private func sampleAsset() -> MediaAsset {
        MediaAsset(id: "1", provider: .wikimedia, title: "Test", description: nil, thumbnailURL: nil, previewURL: nil, downloadURL: URL(string: "https://example.com/test.mp4"), sourcePageURL: URL(string: "https://example.com/source")!, creator: "Creator", license: "CC BY", licenseURL: nil, licenseStatus: .attributionRequired, width: 1920, height: 1080, duration: 10, fileType: "video/mp4", mediaType: .video, publishedDate: nil, downloadable: true, originalMetadata: [:], searchKeyword: "test", relevanceScore: 1)
    }
}
