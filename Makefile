# Everything here runs on core perl. No cpanm, no cpanfile, no network.
# That is a deliberate constraint: a reviewer should be able to clone and run.

PERL ?= perl
PROVE ?= prove
PROVE_FLAGS ?= -l

.PHONY: all index search eval test bench clean

all: index test eval

index:
	$(PERL) -Ilib bin/index-docs.pl --corpus corpus --out index/corpus.json

search:
	$(PERL) -Ilib bin/search.pl --query "$(q)" --k 5 --explain

test:
	$(PROVE) $(PROVE_FLAGS) t/

# The floor is the regression gate: a ranking change that drops NDCG below it
# fails here rather than being noticed later.
eval: index
	$(PERL) -Ilib bin/evaluate.pl --queries eval/queries.json --k 5 --min-ndcg 0.90

bench: index
	$(PERL) -Ilib bin/bench.pl

clean:
	rm -f index/corpus.json
