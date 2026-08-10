import Foundation

enum SelfTestRunner {
    @MainActor static func run() -> Int32 {
        var passed = 0
        var failed: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            if condition() { passed += 1 } else { failed.append(name) }
        }
        check(ProviderUtilities.licenseStatus(name: "CC BY 4.0") == .attributionRequired, "License CC BY")
        check(ProviderUtilities.licenseStatus(name: "Public Domain") == .publicDomain, "License public domain")
        check(ProviderUtilities.licenseStatus(name: nil) == .unknown, "License unknown")
        check(!FileNameSanitizer.sanitize("阿根廷/银行:挤兑?.mp4").contains("/"), "Filename sanitization")
        check(KeywordEngine.keywords(for: "2001年阿根廷银行挤兑").count >= 3, "Keyword expansion")
        check(KeywordEngine.splitScript("第一句话。第二句话。\n\n第三段。").count >= 2, "Script segmentation")

        let sample = MediaAsset(id: "1", provider: .wikimedia, title: "Test", description: nil, thumbnailURL: nil, previewURL: nil, downloadURL: URL(string: "https://example.com/a.mp4"), sourcePageURL: URL(string: "https://example.com/item")!, creator: "A", license: "CC BY", licenseURL: nil, licenseStatus: .attributionRequired, width: 1920, height: 1080, duration: 10, fileType: "video/mp4", mediaType: .video, publishedDate: nil, downloadable: true, originalMetadata: [:], searchKeyword: "test", relevanceScore: 1)
        let duplicate = sample
        check(SearchDeduplicator.apply([sample, duplicate]).count == 1, "Search deduplication")
        check((try? JSONDecoder().decode(MediaAsset.self, from: JSONEncoder().encode(sample))) == sample, "Unified model Codable")

        let store = DataStore(inMemory: true)
        let project = store.addProject(name: "Test Project")
        check(store.projects.count == 1 && store.projects.first?.name == "Test Project", "Project create")
        store.toggleFavorite(asset: sample, projectID: project.id)
        check(store.favorites.count == 1, "Favorite persist model")
        store.deleteProject(id: project.id)
        check(store.projects.isEmpty && store.favorites.first?.projectID == nil, "Project delete isolation")

        let pexelsJSON = Data("{\"videos\":[{\"id\":7,\"width\":1920,\"height\":1080,\"duration\":8,\"url\":\"https://pexels.com/v/7\",\"image\":\"https://img/7.jpg\",\"user\":{\"name\":\"Creator\",\"url\":\"https://pexels.com/u\"},\"video_files\":[{\"width\":1920,\"height\":1080,\"link\":\"https://cdn/7.mp4\",\"file_type\":\"video/mp4\"}]}]}".utf8)
        check((try? JSONDecoder().decode(PexelsVideoResponse.self, from: pexelsJSON).videos.first?.id) == 7, "Pexels fixture parse")
        let pixabayJSON = Data("{\"hits\":[{\"id\":8,\"pageURL\":\"https://pixabay.com/videos/8\",\"videos\":{\"medium\":{\"url\":\"https://cdn/8.mp4\",\"width\":1920,\"height\":1080}}}]}".utf8)
        check((try? JSONDecoder().decode(PixabayVideoResponse.self, from: pixabayJSON).hits.first?.id) == 8, "Pixabay fixture parse")
        let wikiJSON = Data("{\"query\":{\"pages\":[{\"pageid\":9,\"title\":\"File:Test.jpg\",\"imageinfo\":[{\"url\":\"https://upload/test.jpg\",\"width\":100,\"height\":80}]}]}}".utf8)
        check((try? JSONDecoder().decode(WikimediaResponse.self, from: wikiJSON).query?.pages.first?.pageid) == 9, "Wikimedia fixture parse")
        let youtubeJSON = Data("{\"items\":[{\"id\":{\"videoId\":\"abc\"},\"snippet\":{\"publishedAt\":\"2020-01-01T00:00:00Z\",\"channelId\":\"c\",\"title\":\"T\",\"description\":\"D\",\"channelTitle\":\"C\",\"thumbnails\":{}}}]}".utf8)
        check((try? JSONDecoder().decode(YouTubeSearchResponse.self, from: youtubeJSON).items.first?.id.videoId) == "abc", "YouTube fixture parse")
        let archiveJSON = Data("{\"response\":{\"docs\":[{\"identifier\":\"item1\",\"title\":\"Archive\"}]}}".utf8)
        let archiveRoot = try? JSONSerialization.jsonObject(with: archiveJSON) as? [String: Any]
        let archiveDocs = (archiveRoot?["response"] as? [String: Any])?["docs"] as? [[String: Any]]
        check(archiveDocs?.first?["identifier"] as? String == "item1", "Internet Archive fixture parse")

        print("SELF_TEST passed=\(passed) failed=\(failed.count)")
        for name in failed { print("FAIL \(name)") }
        return failed.isEmpty ? 0 : 1
    }
}
