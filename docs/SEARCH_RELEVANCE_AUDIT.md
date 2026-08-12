# Search relevance audit (v0.7.1)

## Root causes

Before v0.7.1, FootageFlow performed high-recall expansion, parallel Provider search, merge, and de-duplication, but it did not perform an intent-aware local relevance pass. Most Providers assigned `relevanceScore` from their returned position. The app then added only small download, resolution, creator, and license bonuses.

That allowed a result matching only a broad entity such as `Taiwan` to outrank an item covering both `Taiwan` and `food`. `matchedQuery` identified which retrieval query produced an item but was not evidence that the item's metadata covered that query.

The live SepiaSearch response for `Taiwan cuisine` reported 546 candidates and began with Taiwan-only geography, earthquake, and civic-politics results. Its public search is intentionally high recall across decentralized instances. Library of Congress general search and Internet Archive Advanced Search likewise returned broad full-text candidates that require local validation. Provider failure isolation was already correct and is unchanged.

## Current two-stage pipeline

1. `KeywordEngine` keeps the original query and up to four bounded, visible translations or related phrases. It does not emit a standalone broad entity for compound intents such as `台湾美食`.
2. Providers retrieve candidates independently and progressively.
3. `SearchRelevanceEngine` derives concept groups from the original query and, when needed, the visible translated query.
4. It scores title, tags/keywords, category, description, creator/channel, bounded Provider relevance, and the matched retrieval query. The matched query alone cannot satisfy concept coverage.
5. Precise, Balanced, or Broad mode filters the candidate pool. Balanced is the persisted default. PeerTube/SepiaSearch, Library of Congress, Internet Archive, and YouTube use a modestly stricter threshold because their search surfaces are empirically broad.
6. De-duplicated accepted items are sorted by local score. Switching mode re-ranks the retained candidate pool without another network search.

Field weights are ordered as follows: title; tags/keywords; category; description; creator/channel. Provider order is only a bounded secondary signal.

## Fixed evaluation

The offline relevance fixture includes positive and negative examples for `台湾美食`, `hamburger`, `city night`, `Apollo 11`, `factory worker`, `俄乌战争`, `日本料理`, and `French cuisine`.

The `台湾美食` fixture gives deliberately irrelevant candidates higher Provider scores. Balanced local ranking still returns 20/20 relevant Top-20 items and retains non-exact matches such as `Taipei beef noodle soup`.

## Live acceptance evidence

Run:

```bash
FootageFlow --relevance-smoke "台湾美食"
```

The final 2026-08-12 public-provider run retrieved 122 candidates from Wikimedia Commons, Internet Archive, Library of Congress, PeerTube/SepiaSearch, Openverse, and Dailymotion. Under the final review rules, the old Provider order contained only 2 relevant items in its Top 20. Balanced returned 14 items and all 14 passed the relevance review; it intentionally did not pad the page with weak matches. PeerTube/SepiaSearch retained 1 of 23 candidates, Wikimedia retained 2 of 7, and Library of Congress retained 0 of 29 broad candidates rather than displaying unrelated items.

The final pass also rejects concepts that occur far apart in long descriptions, topic words found only in oversized archive manifests, a conflicting location in the title, and noisy tag lists that supply a missing topic without support from the title or description. Broad mode remains available when the user explicitly wants those weaker candidates.

The final installed macOS GUI run used the visible queries `台湾美食`, `Taiwanese cuisine`, `Taiwan cuisine`, `Taiwan street food`, and `Taiwan night market food`. It returned 35 real assets. The first 20 cards were reviewed after loading and all 20 covered both Taiwan and food; no journalist, military, folk-song, or politics result remained in that set.

This metric measures deterministic concept coverage in available Provider metadata, not a human copyright, quality, or factual endorsement.
