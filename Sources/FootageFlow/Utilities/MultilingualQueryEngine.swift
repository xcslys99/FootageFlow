import Foundation

struct MultilingualQueryPlan: Codable, Hashable, Sendable {
  let originalQuery: String
  let inputLanguage: AppLanguage
  let interfaceLanguage: AppLanguage
  let conceptGroupIDs: [String]
  let keywords: [SearchKeyword]
}

/// Builds a deterministic search plan in every language supported by FootageFlow.
/// This is intentionally a creator-search lexicon, not a general-purpose translation service.
enum MultilingualQueryEngine {
  private struct Concept: Sendable {
    let id: String
    let aliases: [String]
    let terms: [AppLanguage: String]
  }

  private static let concepts: [Concept] = [
    Concept(
      id: "place.guangzhou",
      aliases: [
        "广州", "廣州", "guangzhou", "canton", "cantonese", "cantón", "cantao", "cantão",
        "kanton", "広州", "광저우", "гуанчжоу",
      ],
      terms: [
        .english: "Guangzhou", .simplifiedChinese: "广州", .traditionalChinese: "廣州",
        .spanish: "Guangzhou", .brazilianPortuguese: "Guangzhou", .japanese: "広州",
        .korean: "광저우", .german: "Guangzhou", .french: "Guangzhou", .russian: "Гуанчжоу",
      ]),
    Concept(
      id: "place.taiwan",
      aliases: [
        "台湾", "台灣", "taiwan", "taiwanese", "taiwanesa", "taiwanes", "taiwanês",
        "taiwanaise", "taiwanesische", "taipei", "台北", "臺北", "대만", "тайван",
      ],
      terms: [
        .english: "Taiwan", .simplifiedChinese: "台湾", .traditionalChinese: "台灣",
        .spanish: "Taiwán", .brazilianPortuguese: "Taiwan", .japanese: "台湾",
        .korean: "대만", .german: "Taiwan", .french: "Taïwan", .russian: "Тайвань",
      ]),
    Concept(
      id: "place.japan",
      aliases: ["日本", "japan", "japanese", "japon", "japón", "japao", "japão", "일본", "япон"],
      terms: [
        .english: "Japan", .simplifiedChinese: "日本", .traditionalChinese: "日本",
        .spanish: "Japón", .brazilianPortuguese: "Japão", .japanese: "日本",
        .korean: "일본", .german: "Japan", .french: "Japon", .russian: "Япония",
      ]),
    Concept(
      id: "place.france",
      aliases: [
        "法国", "法國", "france", "french", "français", "francaise", "franzosisch", "französisch",
        "프랑스", "франц",
      ],
      terms: [
        .english: "France", .simplifiedChinese: "法国", .traditionalChinese: "法國",
        .spanish: "Francia", .brazilianPortuguese: "França", .japanese: "フランス",
        .korean: "프랑스", .german: "Frankreich", .french: "France", .russian: "Франция",
      ]),
    Concept(
      id: "place.argentina",
      aliases: ["阿根廷", "argentina", "argentine", "argentino", "アルゼンチン", "아르헨티나", "аргентин"],
      terms: [
        .english: "Argentina", .simplifiedChinese: "阿根廷", .traditionalChinese: "阿根廷",
        .spanish: "Argentina", .brazilianPortuguese: "Argentina", .japanese: "アルゼンチン",
        .korean: "아르헨티나", .german: "Argentinien", .french: "Argentine", .russian: "Аргентина",
      ]),
    Concept(
      id: "place.buenos-aires",
      aliases: ["布宜诺斯艾利斯", "布宜諾斯艾利斯", "buenos aires", "ブエノスアイレス", "부에노스아이레스", "буэнос айрес"],
      terms: Dictionary(
        uniqueKeysWithValues: AppLanguage.allCases.map {
          (
            $0,
            $0 == .simplifiedChinese
              ? "布宜诺斯艾利斯"
              : $0 == .traditionalChinese
                ? "布宜諾斯艾利斯"
                : $0 == .japanese
                  ? "ブエノスアイレス"
                  : $0 == .korean ? "부에노스아이레스" : $0 == .russian ? "Буэнос-Айрес" : "Buenos Aires"
          )
        })),
    Concept(
      id: "topic.food",
      aliases: [
        "美食", "料理", "食物", "小吃", "夜市", "餐厅", "餐廳", "烹饪", "烹飪", "菜肴",
        "饮食", "飲食", "粤菜", "粵菜", "早茶", "点心", "點心", "飲茶", "food", "foods",
        "cuisine", "delicacies", "gastronomy", "gastronomía", "comida", "cocina", "culinary",
        "cooking", "dish",
        "recipe", "restaurant", "street food", "snack", "meal", "dim sum", "yum cha", "seafood",
        "culinaria", "culinária",
        "gastronomie", "küche", "kueche", "料理", "음식", "요리", "кухня", "еда",
      ],
      terms: [
        .english: "cuisine", .simplifiedChinese: "美食", .traditionalChinese: "美食",
        .spanish: "gastronomía", .brazilianPortuguese: "culinária", .japanese: "料理",
        .korean: "음식", .german: "Küche", .french: "cuisine", .russian: "кухня",
      ]),
    Concept(
      id: "topic.city",
      aliases: [
        "城市", "都市", "夜の街", "city", "urban", "ciudad", "cidade", "ville", "stadt", "город", "도시",
      ],
      terms: [
        .english: "city", .simplifiedChinese: "城市", .traditionalChinese: "城市",
        .spanish: "ciudad", .brazilianPortuguese: "cidade", .japanese: "都市",
        .korean: "도시", .german: "Stadt", .french: "ville", .russian: "город",
      ]),
    Concept(
      id: "topic.night",
      aliases: [
        "夜", "夜景", "夜晚", "night", "evening", "noche", "noite", "nuit", "nacht", "ноч", "ночной",
        "야경", "밤",
      ],
      terms: [
        .english: "night", .simplifiedChinese: "夜景", .traditionalChinese: "夜景",
        .spanish: "de noche", .brazilianPortuguese: "à noite", .japanese: "夜",
        .korean: "야경", .german: "bei Nacht", .french: "de nuit", .russian: "ночной",
      ]),
    Concept(
      id: "topic.factory",
      aliases: [
        "工厂", "工廠", "factory", "industrial", "manufacturing", "fábrica", "usine", "fabrik", "завод",
        "工場", "공장",
      ],
      terms: [
        .english: "factory", .simplifiedChinese: "工厂", .traditionalChinese: "工廠",
        .spanish: "fábrica", .brazilianPortuguese: "fábrica", .japanese: "工場",
        .korean: "공장", .german: "Fabrik", .french: "usine", .russian: "завод",
      ]),
    Concept(
      id: "topic.worker",
      aliases: [
        "工人", "劳工", "勞工", "worker", "laborer", "labourer", "trabajador", "operário", "ouvrier",
        "arbeiter", "рабоч", "労働者", "노동자",
      ],
      terms: [
        .english: "worker", .simplifiedChinese: "工人", .traditionalChinese: "工人",
        .spanish: "trabajador", .brazilianPortuguese: "operário", .japanese: "労働者",
        .korean: "노동자", .german: "Arbeiter", .french: "ouvrier", .russian: "рабочий",
      ]),
    Concept(
      id: "topic.burger",
      aliases: [
        "汉堡", "漢堡", "hamburger", "burger", "cheeseburger", "hamburguesa", "hambúrguer", "ハンバーガー",
        "햄버거",
      ],
      terms: [
        .english: "hamburger", .simplifiedChinese: "汉堡", .traditionalChinese: "漢堡",
        .spanish: "hamburguesa", .brazilianPortuguese: "hambúrguer", .japanese: "ハンバーガー",
        .korean: "햄버거", .german: "Hamburger", .french: "hamburger", .russian: "гамбургер",
      ]),
    Concept(
      id: "topic.fries",
      aliases: [
        "薯条", "薯條", "fries", "french fries", "papas fritas", "batata frita", "フライドポテト", "감자튀김",
      ],
      terms: [
        .english: "french fries", .simplifiedChinese: "薯条", .traditionalChinese: "薯條",
        .spanish: "papas fritas", .brazilianPortuguese: "batata frita", .japanese: "フライドポテト",
        .korean: "감자튀김", .german: "Pommes frites", .french: "frites", .russian: "картофель фри",
      ]),
    Concept(
      id: "topic.coffee-shop",
      aliases: [
        "咖啡店", "咖啡館", "coffee shop", "cafe", "café", "cafetería", "cafeteria", "喫茶店", "커피숍", "кафе",
      ],
      terms: [
        .english: "coffee shop", .simplifiedChinese: "咖啡店", .traditionalChinese: "咖啡館",
        .spanish: "cafetería", .brazilianPortuguese: "cafeteria", .japanese: "喫茶店",
        .korean: "커피숍", .german: "Café", .french: "café", .russian: "кафе",
      ]),
    Concept(
      id: "topic.protest",
      aliases: [
        "抗议", "抗議", "protest", "protests", "demonstration", "protesta", "manifestation", "protesto",
        "протест", "抗議活動", "시위",
      ],
      terms: [
        .english: "protest", .simplifiedChinese: "抗议", .traditionalChinese: "抗議",
        .spanish: "protesta", .brazilianPortuguese: "protesto", .japanese: "抗議活動",
        .korean: "시위", .german: "Protest", .french: "manifestation", .russian: "протест",
      ]),
    Concept(
      id: "topic.finance-crisis",
      aliases: [
        "银行挤兑", "銀行擠兌", "bank run", "bank queue", "economic crisis", "financial crisis", "经济危机",
        "經濟危機", "corralito",
      ],
      terms: [
        .english: "bank run financial crisis", .simplifiedChinese: "银行挤兑经济危机",
        .traditionalChinese: "銀行擠兌經濟危機", .spanish: "crisis financiera corrida bancaria",
        .brazilianPortuguese: "crise financeira corrida bancária", .japanese: "金融危機 銀行取り付け",
        .korean: "금융 위기 뱅크런", .german: "Finanzkrise Bankansturm",
        .french: "crise financière panique bancaire", .russian: "финансовый кризис набег на банки",
      ]),
    Concept(
      id: "event.apollo11",
      aliases: [
        "apollo 11", "apollo eleven", "阿波罗11号", "阿波羅11號", "アポロ11号", "아폴로 11호", "apolo 11",
        "аполлон 11",
      ],
      terms: Dictionary(
        uniqueKeysWithValues: AppLanguage.allCases.map {
          (
            $0,
            $0 == .russian
              ? "Аполлон-11"
              : $0 == .japanese
                ? "アポロ11号"
                : $0 == .korean
                  ? "아폴로 11호"
                  : $0 == .simplifiedChinese
                    ? "阿波罗11号"
                    : $0 == .traditionalChinese
                      ? "阿波羅11號"
                      : $0 == .spanish || $0 == .brazilianPortuguese ? "Apolo 11" : "Apollo 11"
          )
        })),
    Concept(
      id: "topic.conflict",
      aliases: [
        "战争", "戰爭", "冲突", "衝突", "war", "conflict", "invasion", "guerra", "guerre", "krieg", "война",
        "войны", "войн", "戦争", "전쟁",
      ],
      terms: [
        .english: "war", .simplifiedChinese: "战争", .traditionalChinese: "戰爭",
        .spanish: "guerra", .brazilianPortuguese: "guerra", .japanese: "戦争",
        .korean: "전쟁", .german: "Krieg", .french: "guerre", .russian: "война",
      ]),
    Concept(
      id: "place.russia-ukraine",
      aliases: [
        "俄乌", "俄烏", "russia ukraine", "russian ukrainian", "russo ukrainian", "ukraine", "украин",
        "российско украин", "российско украинская война", "ロシア ウクライナ", "러시아 우크라이나",
      ],
      terms: [
        .english: "Russia Ukraine", .simplifiedChinese: "俄乌", .traditionalChinese: "俄烏",
        .spanish: "Rusia Ucrania", .brazilianPortuguese: "Rússia Ucrânia", .japanese: "ロシア・ウクライナ",
        .korean: "러시아-우크라이나", .german: "Russland-Ukraine", .french: "Russie-Ukraine",
        .russian: "Российско-украинская",
      ]),
  ]

  static func plan(
    for rawQuery: String, interfaceLanguage: AppLanguage,
    translatedSupplement: String? = nil, includeVisualExpansions: Bool = true
  ) -> MultilingualQueryPlan {
    let original = rawQuery.cleanedSearchQuery
    let inputLanguage = detectLanguage(in: original, fallback: interfaceLanguage)
    let matched = concepts.filter { concept in
      concept.aliases.contains { contains(alias: $0, in: original) }
    }
    let orderedLanguages = languageOrder(input: inputLanguage, interface: interfaceLanguage)
    var keywords: [SearchKeyword] = []

    for (priority, language) in orderedLanguages.enumerated() {
      var localized = localizedQuery(
        original: original, concepts: matched, language: language)
      let yearText = years(in: original).joined(separator: " ")
      if !yearText.isEmpty && !localized.contains(yearText) {
        localized = "\(yearText) \(localized)"
      }
      let isInput = language == inputLanguage
      keywords.append(
        SearchKeyword(
          text: isInput ? original : localized, language: language,
          origin: isInput ? .input : .multilingualCanonical, priority: priority))
    }

    if includeVisualExpansions {
      let expansionLanguages = uniqueLanguages([inputLanguage, .english])
      for language in expansionLanguages {
        for value in visualExpansions(concepts: matched, language: language).prefix(2) {
          keywords.append(
            SearchKeyword(
              text: value, language: language, origin: .visualExpansion,
              priority: languagePriority(
                language, input: inputLanguage, interface: interfaceLanguage)))
        }
      }
    }

    if matched.isEmpty, let translated = translatedSupplement?.cleanedSearchQuery,
      !translated.isEmpty
    {
      let language = detectLanguage(in: translated, fallback: .english)
      keywords.append(
        SearchKeyword(
          text: translated, language: language, origin: .systemTranslation,
          priority: languagePriority(language, input: inputLanguage, interface: interfaceLanguage)))
    }

    keywords = Array(deduplicated(keywords).prefix(14))
    return MultilingualQueryPlan(
      originalQuery: original, inputLanguage: inputLanguage, interfaceLanguage: interfaceLanguage,
      conceptGroupIDs: matched.map(\.id), keywords: keywords)
  }

  static func detectLanguage(in text: String, fallback: AppLanguage) -> AppLanguage {
    let scalars = text.unicodeScalars
    if scalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) { return .japanese }
    if scalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) }) { return .korean }
    if scalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) { return .russian }
    if text.contains("広州") || text.contains("アポロ") || text.contains("労働者") {
      return .japanese
    }
    if text.range(of: "[廣臺灣體國點飲粵]", options: .regularExpression) != nil {
      return .traditionalChinese
    }
    if scalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }) {
      return .simplifiedChinese
    }

    let normalized = normalize(text)
    let markers: [(AppLanguage, [String])] = [
      (.spanish, ["gastronomía", "comida", "ciudad", "guerra", "de noche"]),
      (.brazilianPortuguese, ["culinária", "cidade", "operário", "à noite", "rússia"]),
      (.german, ["küche", "stadt", "nacht", "arbeiter", "krieg"]),
      (.french, ["cuisine de", "ville", "nuit", "ouvrier", "guerre"]),
      (.english, ["food", "cuisine", "city", "night", "factory", "worker", "war", "apollo"]),
    ]
    var best: (AppLanguage, Int)?
    for (language, words) in markers {
      let score = words.reduce(0) { $0 + (contains(alias: $1, in: normalized) ? 1 : 0) }
      if score > (best?.1 ?? 0) { best = (language, score) }
    }
    return best?.1 ?? 0 > 0 ? best!.0 : fallback
  }

  static func languageOrder(input: AppLanguage, interface: AppLanguage) -> [AppLanguage] {
    uniqueLanguages([input, interface, .english] + AppLanguage.allCases)
  }

  static func languagePriority(
    _ language: AppLanguage, input: AppLanguage, interface: AppLanguage
  ) -> Int {
    languageOrder(input: input, interface: interface).firstIndex(of: language) ?? 99
  }

  private static func localizedQuery(
    original: String, concepts matched: [Concept], language: AppLanguage
  ) -> String {
    guard !matched.isEmpty else { return original }
    let ids = Set(matched.map(\.id))
    if let place = matched.first(where: { $0.id.hasPrefix("place.") }),
      let food = matched.first(where: { $0.id == "topic.food" }),
      let placeTerm = place.terms[language], let foodTerm = food.terms[language]
    {
      switch language {
      case .simplifiedChinese, .traditionalChinese, .japanese:
        return placeTerm + foodTerm
      case .spanish, .brazilianPortuguese:
        return "\(foodTerm) de \(placeTerm)"
      case .german:
        return "\(placeTerm)-\(foodTerm)"
      case .french:
        return "\(foodTerm) de \(placeTerm)"
      case .russian:
        return "\(foodTerm) \(placeTerm)"
      default:
        return "\(placeTerm) \(foodTerm)"
      }
    }
    if ids == Set(["topic.city", "topic.night"]) {
      let city = matched.first { $0.id == "topic.city" }!.terms[language]!
      let night = matched.first { $0.id == "topic.night" }!.terms[language]!
      return language == .japanese ? night + "の" + city : "\(city) \(night)"
    }
    return matched.compactMap { $0.terms[language] }.joined(separator: separator(for: language))
  }

  private static func visualExpansions(concepts: [Concept], language: AppLanguage) -> [String] {
    let ids = Set(concepts.map(\.id))
    if ids.contains("place.guangzhou") && ids.contains("topic.food") {
      switch language {
      case .simplifiedChinese: return ["广州街头美食", "广州早茶粤菜"]
      case .traditionalChinese: return ["廣州街頭美食", "廣州早茶粵菜"]
      case .english: return ["Guangzhou street food", "Cantonese cuisine"]
      case .spanish: return ["comida callejera de Guangzhou", "dim sum cantonés"]
      case .brazilianPortuguese: return ["comida de rua de Guangzhou", "dim sum cantonês"]
      case .japanese: return ["広州屋台料理", "広州飲茶"]
      case .korean: return ["광저우 길거리 음식", "광저우 딤섬"]
      case .german: return ["Guangzhou Streetfood", "kantonesische Küche"]
      case .french: return ["cuisine de rue de Guangzhou", "dim sum cantonais"]
      case .russian: return ["уличная еда Гуанчжоу", "кантонская кухня"]
      }
    }
    if ids.contains("place.taiwan") && ids.contains("topic.food") {
      return language == .english
        ? ["Taiwan street food", "Taiwan night market food"]
        : []
    }
    if ids == Set(["topic.city", "topic.night"]) && language == .english {
      return ["city skyline at night", "downtown night traffic"]
    }
    if ids == Set(["topic.factory", "topic.worker"]) && language == .english {
      return ["factory production line worker", "manufacturing worker"]
    }
    if ids.contains("event.apollo11") && language == .english {
      return ["Apollo 11 moon landing", "1969 moon landing"]
    }
    if ids.contains("place.russia-ukraine") && ids.contains("topic.conflict")
      && language == .english
    {
      return ["Russo-Ukrainian War", "Russian invasion of Ukraine"]
    }
    if ids.contains("topic.burger") && language == .english {
      return ["cheeseburger", "hamburger cooking"]
    }
    if ids.contains("topic.fries") && language == .english {
      return ["potato fries", "french fries cooking"]
    }
    if ids.contains("topic.coffee-shop") && language == .english {
      return ["barista making coffee", "coffee shop customers"]
    }
    return []
  }

  private static func separator(for language: AppLanguage) -> String {
    switch language {
    case .simplifiedChinese, .traditionalChinese, .japanese: ""
    default: " "
    }
  }

  private static func contains(alias: String, in rawText: String) -> Bool {
    let needle = normalize(alias)
    let haystack = normalize(rawText)
    guard !needle.isEmpty else { return false }
    if needle.unicodeScalars.contains(where: { (0x3000...0x9FFF).contains($0.value) }) {
      return haystack.contains(needle)
    }
    return " \(haystack) ".contains(" \(needle) ")
  }

  private static func normalize(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
    )
    .lowercased()
    .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func uniqueLanguages(_ values: [AppLanguage]) -> [AppLanguage] {
    var seen = Set<AppLanguage>()
    return values.filter { seen.insert($0).inserted }
  }

  private static func years(in value: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: "(?:18|19|20)\\d{2}") else { return [] }
    let range = NSRange(value.startIndex..., in: value)
    return regex.matches(in: value, range: range).compactMap {
      Range($0.range, in: value).map { String(value[$0]) }
    }
  }

  private static func deduplicated(_ values: [SearchKeyword]) -> [SearchKeyword] {
    // Keep one entry per language even if an untranslated proper noun is identical. The network
    // layer may coalesce identical text, while the editor still exposes all ten language slots.
    var seen = Set<String>()
    return values.filter { value in
      let key = "\(value.language?.rawValue ?? "unknown")|\(normalize(value.text))"
      return !value.text.cleanedSearchQuery.isEmpty && seen.insert(key).inserted
    }
  }
}

extension String {
  fileprivate var cleanedSearchQuery: String {
    String(prefix(120))
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
