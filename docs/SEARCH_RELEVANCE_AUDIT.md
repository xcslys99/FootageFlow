# Search relevance and multilingual retrieval audit (v0.7.2)

## v0.7.2 Guangzhou root cause

In v0.7.1, `广州美食` was not covered by the local place lexicon. The macOS translation path produced `Guangzhou delicacies`; `delicacies` was also missing from the food aliases. The relevance engine therefore treated the original Chinese text and translated words as unrelated literal requirements and filtered every candidate. Provider query budgets then searched only the first two to four visible phrases.

v0.7.2 adds Guangzhou/Canton/Cantonese and food vocabulary across all ten UI languages. More importantly, the original text is now the only authority for mandatory concept groups. Translation and visual phrases improve retrieval but cannot add a third requirement. `广州美食` deterministically resolves to exactly `place.guangzhou` plus `topic.food`.

## Root causes

Before v0.7.1, FootageFlow performed high-recall expansion, parallel Provider search, merge, and de-duplication, but it did not perform an intent-aware local relevance pass. Most Providers assigned `relevanceScore` from their returned position. The app then added only small download, resolution, creator, and license bonuses.

That allowed a result matching only a broad entity such as `Taiwan` to outrank an item covering both `Taiwan` and `food`. `matchedQuery` identified which retrieval query produced an item but was not evidence that the item's metadata covered that query.

The live SepiaSearch response for `Taiwan cuisine` reported 546 candidates and began with Taiwan-only geography, earthquake, and civic-politics results. Its public search is intentionally high recall across decentralized instances. Library of Congress general search and Internet Archive Advanced Search likewise returned broad full-text candidates that require local validation. Provider failure isolation was already correct and is unchanged.

## Current two-stage pipeline

1. `MultilingualQueryEngine` creates one complete compound query in every supported interface language. Input-language and English visual expansions can add at most four more records, for a maximum of 14. It does not emit a standalone broad entity for a compound intent.
2. All enabled languages enter the same bounded wave: 12 requests globally, two per official/public Provider, and one per direct/tool Provider. Providers still return independently and progressively.
3. `SearchRelevanceEngine` derives mandatory concept groups only from the original query. Translations remain retrieval hints.
4. It scores title, tags/keywords, category, description, creator/channel, bounded Provider relevance, and the matched retrieval query. The matched query alone cannot satisfy concept coverage.
5. Precise, Balanced, or Broad mode filters the candidate pool. Balanced is the persisted default. PeerTube/SepiaSearch, Library of Congress, Internet Archive, and YouTube use a modestly stricter threshold because their search surfaces are empirically broad.
6. De-duplicated accepted items are sorted by local score with a small input-language, interface-language, English, other preference applied only after eligibility. Switching mode re-ranks the retained candidate pool without another network search.

Field weights are ordered as follows: title; tags/keywords; category; description; creator/channel. Provider order is only a bounded secondary signal.

## Fixed evaluation

The offline relevance fixture includes positive and negative examples for `广州美食`, `台湾美食`, `hamburger`, `city night`, `Apollo 11`, `factory worker`, `俄乌战争`, `日本料理`, and `French cuisine`. It also verifies all ten canonical Guangzhou queries, Chinese/English/Japanese/Russian priority, and legacy history decoding.

The `台湾美食` fixture gives deliberately irrelevant candidates higher Provider scores. Balanced local ranking still returns 20/20 relevant Top-20 items and retains non-exact matches such as `Taipei beef noodle soup`.

## Live acceptance evidence

The v0.7.2 run is:

```bash
FootageFlow --relevance-smoke "广州美食"
```

The final 2026-08-12 public-provider run issued the ten canonical queries plus four bounded visual expansions and retrieved 323 de-duplicated candidates from Wikimedia Commons, Internet Archive, Library of Congress, PeerTube/SepiaSearch, Openverse, and Dailymotion. Provider order contained 7 locally relevant items in its Top 20 (0.35). Balanced returned 20/20 relevant items (1.00), led by Guangzhou wedding cuisine, Cantonese dishes, morning tea, dim sum, seafood markets, and street food. One empty or broad Provider did not affect the others.

The final pass also rejects concepts that occur far apart in long descriptions, topic words found only in oversized archive manifests, a conflicting location in the title, and noisy tag lists that supply a missing topic without support from the title or description. Broad mode remains available when the user explicitly wants those weaker candidates.

The final installed macOS GUI run showed `广州美食`, `Guangzhou cuisine`, `Guangzhou street food`, and `Cantonese cuisine` by default. **View all languages** exposed the other eight canonical language rows plus input-language visual expansions, all editable and individually enabled. The previous `Guangzhou delicacies`-driven zero-result behavior did not recur.

This metric measures deterministic concept coverage in available Provider metadata, not a human copyright, quality, or factual endorsement.
