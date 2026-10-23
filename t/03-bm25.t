use strict;
use warnings;
use Test::More;
use lib 'lib';
use RelevanceLab::Index;
use RelevanceLab::BM25;

# --- one-document collection, exact hand-checkable score --------------------
# With one doc: N=1, df=1 -> idf = log(1 + 0.5/1.5) = log(4/3)
# dl == avgdl so the length term collapses to 1, giving
#   score = idf * (tf * (k1+1)) / (tf + k1)
#         = log(4/3) * (1 * 2.2) / (1 + 1.2) = log(4/3)
my $idx = RelevanceLab::Index->new;
$idx->add_document(id => 'only', text => 'term');
$idx->finalize;
my $bm25 = RelevanceLab::BM25->new(k1 => 1.2, b => 0.75);
cmp_ok($bm25->score(['term'], $idx, 0), '>=', 0, 'score is non-negative');
cmp_ok(abs($bm25->score(['term'], $idx, 0) - log(4/3)), '<', 1e-12,
       'exact BM25 score matches the closed form log(4/3)');

# --- idf behaviour ---------------------------------------------------------
# Same collection, one term in every doc and one in a single doc: the rare term
# must carry more weight. This is the property the whole formula rests on.
my $idx2 = RelevanceLab::Index->new;
$idx2->add_document(id => 'd1', text => 'common rare');
$idx2->add_document(id => 'd2', text => 'common');
$idx2->add_document(id => 'd3', text => 'common');
$idx2->finalize;
my $rare_idf   = $bm25->idf($idx2->df_of('rare'), $idx2->n_docs);
my $common_idf = $bm25->idf($idx2->df_of('common'), $idx2->n_docs);
cmp_ok($rare_idf, '>', $common_idf, 'rare term has higher idf than common term');
cmp_ok($rare_idf, '>', 0, 'idf stays positive for a rare term');
cmp_ok($common_idf, '>', 0, 'idf stays positive even for a term in every doc');

# --- term frequency saturation --------------------------------------------
# Ten occurrences must not score ten times one occurrence.
my $idx3 = RelevanceLab::Index->new;
$idx3->add_document(id => 'low',  text => 'word');
$idx3->add_document(id => 'high', text => 'word ' x 10);
$idx3->add_document(id => 'pad',  text => 'unrelated filler tokens here');
$idx3->finalize;
my $low  = $bm25->score(['word'], $idx3, 0);
my $high = $bm25->score(['word'], $idx3, 1);
cmp_ok($high, '>', $low, 'more occurrences still helps');
cmp_ok($high, '<', $low * 10, 'but sub-linearly: tf saturates');

# --- length normalisation -------------------------------------------------
# A long doc repeating a term must not beat a short focused doc automatically.
my $idx4 = RelevanceLab::Index->new;
$idx4->add_document(id => 'focused', text => 'word');
$idx4->add_document(id => 'padded',  text => 'word ' . ('filler ' x 30));
$idx4->finalize;
cmp_ok($bm25->score(['word'], $idx4, 0), '>', $bm25->score(['word'], $idx4, 1),
       'b=0.75 prefers the short focused document');

# --- missing term ---------------------------------------------------------
is($bm25->score(['absent'], $idx2, 0), 0, 'absent term scores zero');

done_testing();
