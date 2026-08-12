import Foundation

#if canImport(Testing)
  import Testing

  @testable import FootageFlow

  @Suite("Local Search Relevance")
  struct SearchRelevanceTests {
    @Test("Guangzhou food builds ten complete compound queries without a delicacies concept")
    func guangzhouFoodPlan() {
      let plan = MultilingualQueryEngine.plan(
        for: "广州美食", interfaceLanguage: .simplifiedChinese)
      #expect(plan.inputLanguage == .simplifiedChinese)
      #expect(Set(plan.conceptGroupIDs) == ["place.guangzhou", "topic.food"])
      #expect(plan.keywords.count == 14)
      let values = Set(plan.keywords.map(\.text))
      let required: Set<String> = [
        "广州美食", "廣州美食", "Guangzhou cuisine", "gastronomía de Guangzhou",
        "culinária de Guangzhou", "広州料理", "광저우 음식", "Guangzhou-Küche",
        "cuisine de Guangzhou", "кухня Гуанчжоу",
      ]
      #expect(required.isSubset(of: values))
      #expect(!plan.conceptGroupIDs.contains("literal.delicacies"))
      #expect(Set(plan.keywords.compactMap(\.language)).count == 10)

      let intent = SearchRelevanceEngine.intent(
        for: "广州美食", supportingQueries: ["Guangzhou delicacies"])
      #expect(Set(intent.conceptGroups.map(\.id)) == ["place.guangzhou", "topic.food"])
    }

    @Test("Guangzhou food keeps cuisine and filters single-concept results")
    func guangzhouFoodRelevance() {
      let positives = [
        "Cantonese cuisine in Guangzhou", "Guangzhou dim sum and yum cha",
        "广州早茶和粤菜", "廣州街頭小吃", "Guangzhou seafood market",
      ]
      let negatives = [
        "Guangzhou evening news", "Guangzhou military exercise", "Taipei street food",
        "Guangzhou city skyline", "Chinese cuisine in Beijing",
      ]
      let intent = SearchRelevanceEngine.intent(for: "广州美食")
      for title in positives {
        #expect(
          SearchRelevanceEngine.assess(asset(title), intent: intent, mode: .balanced).eligible,
          Comment(rawValue: title))
      }
      for title in negatives {
        #expect(
          !SearchRelevanceEngine.assess(asset(title), intent: intent, mode: .balanced).eligible,
          Comment(rawValue: title))
      }
    }

    @Test("Input and interface language priorities are deterministic")
    func languagePriorities() {
      let chinese = MultilingualQueryEngine.plan(
        for: "广州美食", interfaceLanguage: .japanese)
      #expect(chinese.keywords[0].language == .simplifiedChinese)
      #expect(chinese.keywords[1].language == .japanese)
      #expect(chinese.keywords[2].language == .english)
      let english = MultilingualQueryEngine.plan(
        for: "Guangzhou cuisine", interfaceLanguage: .japanese)
      #expect(english.keywords[0].language == .english)
      #expect(english.keywords[1].language == .japanese)
      let japanese = MultilingualQueryEngine.plan(
        for: "広州料理", interfaceLanguage: .english)
      #expect(japanese.keywords[0].language == .japanese)
      #expect(japanese.keywords[1].language == .english)
      let russian = MultilingualQueryEngine.plan(
        for: "кухня Гуанчжоу", interfaceLanguage: .english)
      #expect(russian.keywords[0].language == .russian)
      #expect(russian.keywords[1].language == .english)
    }

    @Test("Taiwan food intent creates two semantic concept groups")
    func taiwanFoodIntent() {
      let intent = SearchRelevanceEngine.intent(for: "台湾美食")
      #expect(Set(intent.conceptGroups.map(\.id)) == ["place.taiwan", "topic.food"])
      let expandedIntent = SearchRelevanceEngine.intent(
        for: "台湾美食",
        supportingQueries: ["Taiwanese cuisine", "Taiwan street food", "Taiwan night market food"])
      #expect(Set(expandedIntent.conceptGroups.map(\.id)) == ["place.taiwan", "topic.food"])
      let generated = KeywordEngine.keywords(for: "台湾美食").map(\.text)
      #expect(!generated.contains("Taiwan"))
      #expect(!generated.contains("Taiwanese"))
    }

    @Test("Balanced keeps semantic food matches and filters entity-only matches")
    func balancedCompositeCoverage() {
      let positives = [
        "Taiwanese Style Chicken Drums", "Taiwan night market food",
        "Taipei beef noodle soup", "Taiwanese street snacks",
        "Cooking Taiwanese pork rice",
      ]
      let negatives = [
        "Taiwanese investigative journalist", "Taiwanese troops military exercise",
        "Taiwanese folk song", "Taiwan politics",
      ]
      let intent = SearchRelevanceEngine.intent(for: "台湾美食")
      for title in positives {
        #expect(
          SearchRelevanceEngine.assess(
            asset(title), intent: intent, mode: .balanced
          ).eligible, Comment(rawValue: title))
      }
      for title in negatives {
        #expect(
          !SearchRelevanceEngine.assess(
            asset(title), intent: intent, mode: .balanced
          ).eligible, Comment(rawValue: title))
      }
    }

    @Test("Metadata fields use weighted relevance and matched query alone is insufficient")
    func fieldWeights() {
      let intent = SearchRelevanceEngine.intent(for: "台湾美食")
      let tagged = asset(
        "A walk through Taipei", metadata: ["tags": "street food, noodles, local cuisine"])
      #expect(SearchRelevanceEngine.assess(tagged, intent: intent, mode: .balanced).eligible)

      let queryOnly = asset(
        "Taiwanese investigative journalist",
        metadata: ["matchedQuery": "Taiwan cuisine", "category": "News and Politics"])
      #expect(!SearchRelevanceEngine.assess(queryOnly, intent: intent, mode: .balanced).eligible)

      let creatorOnly = asset("Taiwan documentary", creator: "Taiwanese Food Channel")
      #expect(!SearchRelevanceEngine.assess(creatorOnly, intent: intent, mode: .balanced).eligible)
    }

    @Test("Distant matches in a long archive description do not pass Balanced mode")
    func distantArchiveDescriptionMatches() {
      let filler = Array(repeating: "unrelated archive chapter", count: 40).joined(separator: " ")
      let candidate = asset(
        "Lost Media Found in 2023", provider: .internetArchive,
        description: "Taiwan 2001 \(filler) Aliens in Our Food")
      let intent = SearchRelevanceEngine.intent(
        for: "台湾美食", supportingQueries: ["Taiwanese cuisine"])

      #expect(!SearchRelevanceEngine.assess(candidate, intent: intent, mode: .balanced).eligible)
      #expect(SearchRelevanceEngine.assess(candidate, intent: intent, mode: .broad).eligible)
    }

    @Test("Nearby concepts in a description remain eligible")
    func nearbyDescriptionMatches() {
      let candidate = asset(
        "Night Market Documentary", provider: .internetArchive,
        description: "A journey through Taiwan exploring street food, noodles and local cooking.")
      let intent = SearchRelevanceEngine.intent(
        for: "台湾美食", supportingQueries: ["Taiwanese cuisine"])

      #expect(SearchRelevanceEngine.assess(candidate, intent: intent, mode: .balanced).eligible)
    }

    @Test("A conflicting location in the title is not rescued by an incidental description")
    func conflictingLocation() {
      let candidate = asset(
        "Greatest Omurice Artist, Omelet Rice Kyoto Japan", provider: .internetArchive,
        description:
          "This Japanese dish was later brought to Korea and Taiwan, where it is popular cuisine.",
        metadata: ["subjects": "Japanese, cooking"])
      let intent = SearchRelevanceEngine.intent(
        for: "台湾美食", supportingQueries: ["Taiwanese cuisine"])

      #expect(!SearchRelevanceEngine.assess(candidate, intent: intent, mode: .balanced).eligible)
    }

    @Test("Distractor categories cannot use a weak description topic to pass")
    func distractorCategory() {
      let candidate = asset(
        "Taiwan President Meets Business Owners", provider: .internetArchive,
        description: "The visit briefly showcased Taiwan cuisine and culture.",
        metadata: ["subjects": "News & Politics, journalism"])
      let intent = SearchRelevanceEngine.intent(
        for: "台湾美食", supportingQueries: ["Taiwanese cuisine"])

      #expect(!SearchRelevanceEngine.assess(candidate, intent: intent, mode: .balanced).eligible)
      #expect(SearchRelevanceEngine.assess(candidate, intent: intent, mode: .broad).eligible)
    }

    @Test("A huge archive manifest cannot pass from one nearby list entry")
    func hugeArchiveManifest() {
      let filler = Array(repeating: "unrelated program episode chapter", count: 100)
        .joined(separator: " ")
      let candidate = asset(
        "RTHK deleted videos collection", provider: .internetArchive,
        description: "\(filler) Taiwan night market food \(filler)",
        metadata: ["subjects": "archive, deleted videos"])
      let intent = SearchRelevanceEngine.intent(
        for: "台湾美食", supportingQueries: ["Taiwanese cuisine"])

      #expect(!SearchRelevanceEngine.assess(candidate, intent: intent, mode: .balanced).eligible)
      #expect(SearchRelevanceEngine.assess(candidate, intent: intent, mode: .broad).eligible)
    }

    @Test("A noisy archive tag list cannot supply the missing topic by itself")
    func noisyArchiveTags() {
      let candidate = asset(
        "Highway journey toward Taipei", provider: .internetArchive,
        description: "A road trip following signs toward Taiwan and Taipei.",
        metadata: [
          "subjects":
            "video, outdoors, road trip, travel, short film, lifestyle, food, Beijing, Taiwan, highway, driving, tourism, vlog"
        ])
      let intent = SearchRelevanceEngine.intent(
        for: "台湾美食", supportingQueries: ["Taiwanese cuisine"])

      #expect(!SearchRelevanceEngine.assess(candidate, intent: intent, mode: .balanced).eligible)
      #expect(SearchRelevanceEngine.assess(candidate, intent: intent, mode: .broad).eligible)
    }

    @Test("Precise Balanced and Broad have distinct thresholds")
    func searchModes() {
      let intent = SearchRelevanceEngine.intent(for: "台湾美食")
      let strong = asset("Taiwanese street food and night market snacks", provider: .peertube)
      let entityOnly = asset("Taiwanese politics", provider: .peertube)
      let descriptionOnly = asset(
        "Travel diary", description: "A tour of Taipei restaurants and Taiwanese cuisine")

      #expect(SearchRelevanceEngine.assess(strong, intent: intent, mode: .precise).eligible)
      #expect(SearchRelevanceEngine.assess(strong, intent: intent, mode: .balanced).eligible)
      #expect(!SearchRelevanceEngine.assess(entityOnly, intent: intent, mode: .balanced).eligible)
      #expect(SearchRelevanceEngine.assess(entityOnly, intent: intent, mode: .broad).eligible)
      #expect(
        SearchRelevanceEngine.assess(descriptionOnly, intent: intent, mode: .balanced).eligible)
      #expect(
        !SearchRelevanceEngine.assess(descriptionOnly, intent: intent, mode: .precise).eligible)
    }

    @Test("Fixed relevance set improves Precision at 20 without exact phrase matching")
    func precisionAt20() {
      let relevantTitles = [
        "Taiwanese Style Chicken Drums", "Taiwan night market food", "Taipei beef noodle soup",
        "Taiwanese street snacks", "Cooking Taiwanese pork rice", "Taipei dumpling restaurant",
        "Taiwan oyster omelet cooking", "Taiwanese noodle kitchen", "Taipei street food tour",
        "Traditional Taiwanese meal", "Taiwan night market snacks", "Taipei beef soup recipe",
        "Taiwanese rice dish", "Cooking chicken in Taiwan", "Taipei restaurant cuisine",
        "Taiwan pork dumplings", "Taiwanese food market", "Taipei noodle cooking",
        "Taiwanese kitchen recipe", "Taiwan street meal",
      ]
      let irrelevantTitles = [
        "Taiwanese investigative journalist", "Taiwanese troops military exercise",
        "Taiwanese folk song", "Taiwan politics", "Taiwan election debate", "Taiwan earthquake",
        "Taiwan technology conference", "Taiwan stock market news", "Taiwan naval exercise",
        "Taiwan travel documentary", "Taiwanese language lesson", "Taiwan weather forecast",
      ]
      let candidates =
        irrelevantTitles.enumerated().map {
          asset($0.element, id: "n\($0.offset)", providerScore: 1 - Double($0.offset) * 0.001)
        }
        + relevantTitles.enumerated().map {
          asset($0.element, id: "p\($0.offset)", providerScore: 0.5 - Double($0.offset) * 0.001)
        }
      let ranked = SearchRelevanceEngine.rank(candidates, query: "台湾美食", mode: .balanced)
      let top20 = Array(ranked.prefix(20))
      let relevant = top20.filter { $0.id.hasPrefix("p") }.count
      let precision = top20.isEmpty ? 0 : Double(relevant) / Double(top20.count)
      #expect(top20.count == 20)
      #expect(relevant == 20)
      #expect(precision == 1)
      #expect(top20.contains { $0.title == "Taipei beef noodle soup" })
    }

    @Test("General composite queries require useful concept coverage")
    func generalCases() {
      let cases: [(String, String, String)] = [
        ("hamburger", "Chef cooking a cheeseburger", "Hamburg city traffic"),
        ("city night", "Downtown city skyline at night", "City council election"),
        ("Apollo 11", "1969 Apollo 11 moon landing", "Apollo theater concert"),
        (
          "factory worker", "Factory workers on an assembly line", "Factory exterior without people"
        ),
        ("俄乌战争", "Ukraine war and Russian invasion", "Ukrainian folk songs"),
        ("日本料理", "Japanese food and Tokyo noodle restaurant", "Japanese military exercise"),
        ("French cuisine", "French restaurant cooking in Paris", "French political debate"),
      ]
      for (query, relevant, irrelevant) in cases {
        let intent = SearchRelevanceEngine.intent(for: query)
        #expect(
          SearchRelevanceEngine.assess(asset(relevant), intent: intent, mode: .balanced).eligible,
          Comment(rawValue: "expected relevant: \(query) / \(relevant)"))
        #expect(
          !SearchRelevanceEngine.assess(asset(irrelevant), intent: intent, mode: .balanced)
            .eligible,
          Comment(rawValue: "expected filtered: \(query) / \(irrelevant)"))
      }
    }

    @Test("Translated supporting query preserves composite intent for unsegmented Chinese")
    func translatedSupportingQuery() {
      let intent = SearchRelevanceEngine.intent(
        for: "法国街头抗议", supportingQueries: ["French street protest"])
      #expect(intent.conceptGroups.contains { $0.id == "place.france" })
      #expect(intent.conceptGroups.contains { $0.id == "topic.protest" })
      let relevant = asset("Street protest in Paris, France")
      let irrelevant = asset("French cuisine in Paris")
      #expect(SearchRelevanceEngine.assess(relevant, intent: intent, mode: .balanced).eligible)
      #expect(!SearchRelevanceEngine.assess(irrelevant, intent: intent, mode: .balanced).eligible)
    }

    @Test("Unknown translation is an alias and never a new mandatory group")
    func unknownTranslationAlias() {
      let intent = SearchRelevanceEngine.intent(
        for: "珐琅工艺", supportingQueries: ["enamel craft"])
      #expect(intent.conceptGroups.count == 1)
      #expect(intent.conceptGroups[0].id == "literal.query")
      #expect(intent.conceptGroups[0].aliases.contains("enamel craft"))
      #expect(
        SearchRelevanceEngine.assess(
          asset("Traditional enamel craft workshop"), intent: intent, mode: .balanced
        ).eligible)
    }

    private func asset(
      _ title: String, id: String = UUID().uuidString, provider: ProviderID = .peertube,
      description: String? = nil, creator: String? = nil,
      metadata: [String: String] = [:], providerScore: Double = 1
    ) -> MediaAsset {
      MediaAsset(
        id: id, provider: provider, title: title, description: description,
        thumbnailURL: nil, previewURL: nil, downloadURL: nil,
        sourcePageURL: URL(string: "https://example.com/\(id)")!, creator: creator,
        license: nil, licenseURL: nil, licenseStatus: .unknown, width: nil, height: nil,
        duration: nil, fileType: nil, mediaType: .video, publishedDate: nil,
        downloadable: false, originalMetadata: metadata, searchKeyword: "Taiwan cuisine",
        relevanceScore: providerScore)
    }
  }
#endif
