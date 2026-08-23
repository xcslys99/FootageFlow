import Foundation

#if canImport(Testing)
  import Testing
  @testable import FootageFlow

  @Suite("Research and culture workflow")
  struct ResearchWorkflowTests {
    @Test("research query budget remains bounded and keeps the original concept")
    func queryBudget() {
      let values = ResearchQueryPlanner.queries(for: "广州美食", interfaceLanguage: .simplifiedChinese)
      #expect(values.count <= 2)
      #expect(values.first?.text == "广州美食")
      #expect(values.allSatisfy { !$0.text.isEmpty })
    }

    @Test("in-app language catalog reads the selected locale instead of the system locale")
    func explicitLanguageCatalog() {
      let catalog = LocalizationCatalog()
      #expect(catalog.text("nav.quickSearch", language: .english, arguments: []) == "Quick Search")
      #expect(
        catalog.text("nav.quickSearch", language: .simplifiedChinese, arguments: []) == "快速搜索")
    }

    @Test("research citations use source facts and do not invent rights")
    func citations() throws {
      let record = try fixture(provider: .crossref, id: "10.1234/example", title: "Research title")
      let citation = record.citationText
      #expect(citation.contains("Research title"))
      #expect(citation.contains("https://doi.org/10.1234/example"))
      #expect(record.license == nil)
    }

    @Test("only source-confirmed public collection images become downloadable media")
    func publicCollectionMedia() throws {
      var publicRecord = try fixture(provider: .metropolitanMuseum, id: "42", title: "Public work")
      publicRecord.license = "Public Domain"
      publicRecord.providerMetadata = [
        "publicDomain": "true", "publicImageURL": "https://example.com/public-work.jpg",
      ]
      let asset = try #require(ResearchMediaAdapter.asset(for: publicRecord))
      #expect(asset.mediaType == .image)
      #expect(asset.downloadable)
      #expect(asset.licenseStatus == .publicDomain)

      var restricted = publicRecord
      restricted.providerMetadata["publicDomain"] = "false"
      #expect(ResearchMediaAdapter.asset(for: restricted) == nil)
    }

    @Test("research references persist, deduplicate and survive portable v2 backup")
    func persistenceAndBackup() throws {
      let store = PersistentStore(inMemory: true)
      let project = store.addProject(name: "Research")
      let record = try fixture(provider: .wikidata, id: "Q405", title: "Apollo 11")
      let reference = ResearchReferenceRecord(
        projectID: project.id, record: record, myNote: "Use launch context", tags: ["space"])
      #expect(store.addResearchReference(reference))
      #expect(!store.addResearchReference(reference))
      let manifest = PortableProjectCodec.manifest(project: project, database: store.database)
      #expect(manifest.schemaVersion == 2)
      #expect(manifest.researchReferences?.count == 1)
      let imported = try PortableProjectCodec.importedPayload(
        from: try PortableProjectCodec.decode(PortableProjectCodec.data(manifest)),
        existingProjectNames: [])
      #expect(imported.researchReferences.count == 1)
      #expect(imported.researchReferences[0].projectID == imported.project.id)
      #expect(imported.researchReferences[0].myNote == "Use launch context")
    }

    @Test("balanced research relevance requires all composite concepts")
    func relevance() throws {
      let related = try fixture(
        provider: .wikipedia, id: "guangzhou-food", title: "Guangzhou cuisine",
        summary: "Cantonese food and dim sum")
      let unrelated = try fixture(
        provider: .gdelt, id: "guangzhou-news", title: "Guangzhou local politics",
        summary: "News report")
      let ranked = ResearchRelevanceEngine.rank(
        [unrelated, related], query: "广州美食", mode: .balanced,
        supportingQueries: ["Guangzhou cuisine"], inputLanguage: .simplifiedChinese,
        interfaceLanguage: .simplifiedChinese)
      #expect(ranked.map(\.id) == [related.id])
    }

    @Test("research-only and combined exports keep categories separate and escape notes")
    func researchExports() throws {
      let project = ProjectRecord(name: "Research export")
      let record = try fixture(provider: .wikidata, id: "Q405", title: "Apollo 11")
      let reference = ResearchReferenceRecord(
        projectID: project.id, record: record, myNote: "<verify & cite>", tags: ["space"])
      let researchCSV = try #require(
        String(
          data: AttributionExporter.data(
            format: .csv, project: project, items: [], researchReferences: [reference],
            section: .researchReferences), encoding: .utf8))
      #expect(researchCSV.contains("Research Type"))
      #expect(researchCSV.contains("Apollo 11"))
      let combinedHTML = try #require(
        String(
          data: AttributionExporter.data(
            format: .html, project: project, items: [], researchReferences: [reference],
            section: .combined), encoding: .utf8))
      #expect(combinedHTML.contains("Research Notes"))
      #expect(combinedHTML.contains("&lt;verify &amp; cite&gt;"))
    }

    private func fixture(
      provider: ResearchProviderID, id: String, title: String, summary: String? = nil
    ) throws -> ResearchRecord {
      ResearchRecord(
        id: id, provider: provider,
        type: provider == .crossref ? .academic : provider == .gdelt ? .news : .structuredData,
        title: title, source: provider.displayName, sourceNativeID: id,
        canonicalURL: try #require(URL(string: "https://example.com/\(id)")), summary: summary,
        authors: ["Author"], publishedDate: nil, year: "1969", language: .english,
        doi: provider == .crossref ? id : nil, wikidataQID: provider == .wikidata ? id : nil,
        license: nil, licenseURL: nil, thumbnailURL: nil, providerMetadata: [:],
        searchKeyword: title, relevanceScore: 1, relatedMediaQueryHints: [title])
    }
  }
#endif
