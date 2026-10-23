# relevance-lab

A small, dependency-free search engine in Perl 5: inverted index, BM25 ranking,
and an offline relevance eval harness. Built to be read in one sitting and to be
defensible line by line.

961 lines of Perl across five modules, four CLI entry points and six test files.
No CPAN. Core perl only, so it runs on any stock install.

## Why this exists

Ranking is the part of search that is easy to get roughly right and hard to get
provably better. This project is the smallest complete loop around that problem:
index a corpus, rank it, grade the results, and gate the next change on a number
instead of on a feeling.

It also runs on the same primitives a Perl backend uses every day: hashes as
inverted lists, regular expressions for tokenisation, and a test suite that
fails loudly when behaviour moves.

## Quick start

```bash
make test                 # 80 assertions, should be green
make index                # build index/corpus.json from corpus/
make search q="tail latency sharding"
make eval                 # P@5, MRR and NDCG@5 against eval/queries.json
```

Or without make:

```bash
perl -Ilib bin/index-docs.pl --corpus corpus --out index/corpus.json
perl -Ilib bin/search.pl --query "how does bm25 rank documents" --k 5 --explain
perl -Ilib bin/evaluate.pl --queries eval/queries.json --k 5 --min-ndcg 0.90
```

Sample output:

```
$ perl -Ilib bin/search.pl --query "tail latency sharding" --k 3

query: tail latency sharding  (mode=or, 3 hits, 0.15 ms)

   1. sharding                      7.232  Sharding search
   2. online-experiments            1.765  Online experiments
   3. query-cache                   1.728  Query result caching
```

## Measured results

Corpus: 18 documents, 576 unique terms, 60.1 terms per document, 45 KB index.

| Metric | Value | How it was measured |
|---|---|---|
| Tests | **80 passing**, 6 files | `prove -l t/` |
| NDCG@5 | **0.947** | 12 graded queries, `bin/evaluate.pl` |
| MRR@5 | **0.96** | first relevant result is usually rank 1 |
| P@5 | **0.62** | dragged down by unjudged results, see limitations |
| Query latency | **28 us median**, 146 us mean, 1.5 ms p95 | `bin/bench.pl`, 1200 queries |
| Index build | 0.18 to 0.32 s | three runs, cold |
| Index load | 117 ms | one-off per worker, JSON::PP is pure Perl |

The latency spread is real and worth stating plainly: the median is 28 us
because a query touches a handful of posting lists, while the p95 is 1.5 ms
because Perl reallocates during hash growth. An implementation that pooled its
allocations would flatten that tail. The algorithm is not the bottleneck.

## How it works

```
corpus/*.md
    |
    v
Tokenizer ──> Index (postings, df, avgdl) ──> index/corpus.json
                  |
                  v
              BM25 scores  <──  Searcher (candidates, ranking, explain)
                  |
                  v
              Eval (P@k, MRR, NDCG@k)  ──>  exit 1 if below floor
```

- **`RelevanceLab::Tokenizer`** lowercases, splits on non-alphanumerics, drops
  stopwords and one-character tokens, and applies a four-line stemmer for
  plurals. Index and query share the same function on purpose.
- **`RelevanceLab::Index`** builds postings as `{ term => { docpos => tf } }`,
  tracks document frequency and average document length, and persists to JSON.
  Documents are added streaming so the corpus never has to be held twice.
- **`RelevanceLab::BM25`** implements Okapi BM25: positive-idf term weighting,
  saturating term frequency (`k1`), and length normalisation (`b`).
- **`RelevanceLab::Searcher`** generates candidates from the postings (never
  scans the collection), scores them, and supports `or` and `and` modes plus
  per-result matched-term output for debugging.
- **`RelevanceLab::Eval`** scores a query set with graded judgments and returns
  per-query rows plus the means. `bin/evaluate.pl --min-ndcg` turns the report
  into a CI gate.

## Limitations

Stated rather than hidden, because every one of these is a decision:

- **No `-ing` stemming.** `ranking` and `rank` never match. This is visible in
  the eval set: query 1 scores NDCG 0.64 and ranks a related document first,
  because the relevant document only contains `ranking`. A real stemmer would
  fix it and would also merge words that should stay apart; on a 12-query set,
  tuning until it passes would be overfitting, so it is left documented.
- **Pooled judgments.** Grades only cover documents that were judged. A result
  nobody thought to grade scores zero, which is why P@5 reads low (0.62) while
  MRR is high (0.96). Production eval sets have the same bias.
- **In-memory, full rebuild.** Correct and simple, wrong for a collection that
  changes hourly.
- **JSON::PP.** Core and therefore dependency-free, but pure Perl, which is
  where the 117 ms load comes from.
- **No phrase or proximity search.** Positions are not stored.

## What I would do next

1. Store token positions so phrase queries work, then keep stopwords out of
   scoring while keeping them matchable.
2. Replace JSON with a binary postings format and mmap it, which removes the
   load cost and makes the index shareable between workers.
3. Add incremental updates with a generation counter so a reindex invalidates
   caches atomically.
4. Add a second retrieval pass (embeddings) and fuse with reciprocal rank
   fusion, then measure whether the fusion beats BM25 alone on this set.

See `docs/design.md` for the scaling story.
