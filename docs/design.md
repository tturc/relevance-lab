# Design notes

The interesting decisions, in the order they were made, plus what changes at a
size this project does not have.

## 1. Candidate generation before scoring

The searcher never iterates the collection. It looks up each query term in the
postings, unions the document ids, and scores only those. Two consequences:

- Cost scales with the number of matching documents, not with the corpus. A
  query for a rare term on a billion-document index touches almost nothing.
- A document that matches no query term cannot score above zero, so skipping it
  is not an optimisation, it is the definition of the retrieval model.

The AND mode is implemented as a filter on that candidate set (count the terms
each candidate matched) rather than as a second retrieval pass. Cheap, and it
keeps one code path for scoring.

## 2. Why BM25 and not TF-IDF

Plain TF-IDF multiplies term frequency by inverse document frequency and sums.
That has no term-frequency ceiling: a document that repeats a keyword twenty
times keeps gaining. BM25 adds two things that matter on real text:

- `k1` makes each additional occurrence worth less, so a document cannot win by
  repetition. At `k1 = 1.2` the ninth occurrence is worth very little.
- `b` normalises by document length, so a long document does not outrank a
  short focused one merely by containing more words.

The idf form here is `log(1 + (N - df + 0.5)/(df + 0.5))`, which stays positive
even for a term present in every document. The classic textbook form goes
negative past df = N/2, which means a very common query term actively subtracts
from a document's score. That is hard to defend to anyone reading a results
page, so this project uses the always-positive variant.

Both parameters are exposed on the constructor, which is what makes the tests
possible: a test can pin `k1` and `b` and compare against a closed-form value.

## 3. Why the eval harness is the point

Anybody can produce a ranking. The thing that separates a ranking from an
engineering change is a number that moves in a direction you predicted.

Three metrics because they disagree in useful ways:

- **P@k** is intuitive and misleading. It punishes a deep index, because it
  counts every unjudged result as a miss.
- **MRR** answers "did we put the right thing first", which is what most search
  queries are actually asking.
- **NDCG@k** is the one to gate on: it respects ordering and grades, so moving a
  highly relevant document from 3 to 1 improves the score while moving a
  marginally relevant one does not.

`--min-ndcg` exists so the eval can fail a build. An eval that only prints a
table is read once.

## 4. What breaks first at scale

In order of when it bites:

1. **The index stops fitting in memory.** Postings move to disk, memory-mapped,
   with skip lists so a query can jump past long posting lists instead of
   decoding them.
2. **Rebuilds stop being cheap enough.** Incremental segments, merged on a
   schedule, plus a generation counter so caches invalidate atomically instead
   of expiring by wall clock.
3. **One machine stops being enough.** Shard by document, scatter the query,
   gather the top k from each shard. Now the slowest shard sets the latency of
   the query, so the work moves to tail latency: replicate each shard, hedge
   requests, and keep global term statistics consistent or scores stop being
   comparable across shards.
4. **Relevance judgments stop keeping up.** Sample the query log, judge the
   head, and accept that the long tail is measured by online experiments
   instead. Interleaving two rankings in one result page is cheaper than a
   traffic split and answers the same question.
5. **Keyword matching stops being enough.** Add dense retrieval and fuse the
   two lists with reciprocal rank fusion, which needs no score calibration
   because it only reads rank positions. Then measure whether the fusion
   actually wins on this corpus before shipping it.

## 5. What is deliberately missing

Phrase queries, positions, wildcards, facets, and a query parser. Each is a
week of work and none of them changes the part of the system this project is
about: scoring, ranking and measuring. The absence is a scope decision, not an
oversight.
