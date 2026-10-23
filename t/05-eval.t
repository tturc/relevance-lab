use strict;
use warnings;
use Test::More;
use lib 'lib';
use RelevanceLab::Eval;

# Results are plain hashrefs with an id, same shape the Searcher returns.
sub docs { return [ map { { id => $_ } } @_ ] }

my $j = { a => 2, b => 1 };

# --- precision@k ----------------------------------------------------------
is(RelevanceLab::Eval::precision_at_k(docs(qw(a x y)), $j, 3), 1/3,
   'one relevant of three');
is(RelevanceLab::Eval::precision_at_k(docs(qw(a b)), $j, 2), 1,
   'both relevant');
is(RelevanceLab::Eval::precision_at_k(docs(qw(x y z)), $j, 3), 0,
   'none relevant');
is(RelevanceLab::Eval::precision_at_k([], $j, 3), 0, 'empty result set');

# --- reciprocal rank ------------------------------------------------------
is(RelevanceLab::Eval::reciprocal_rank(docs(qw(a x)), $j, 2), 1,
   'first position relevant -> 1.0');
is(RelevanceLab::Eval::reciprocal_rank(docs(qw(x a)), $j, 2), 0.5,
   'second position relevant -> 0.5');
is(RelevanceLab::Eval::reciprocal_rank(docs(qw(x y)), $j, 2), 0,
   'no relevant in top k -> 0');
is(RelevanceLab::Eval::reciprocal_rank([], $j, 2), 0, 'empty result set');

# --- DCG / NDCG -----------------------------------------------------------
# DCG for grades (2,0) with gain 2^g-1: 3/log2(2) + 0 = 3
cmp_ok(RelevanceLab::Eval::dcg([2, 0]), '==', 3, 'dcg of 2,0 is 3');
# (1,1): 1/log2(2) + 1/log2(3) = 1 + log(2)/log(3) = 1.6309...
cmp_ok(abs(RelevanceLab::Eval::dcg([1, 1]) - (1 + log(2)/log(3))), '<', 1e-12,
       'dcg discounts later positions');

is(RelevanceLab::Eval::ndcg_at_k(docs(qw(a b)), $j, 2), 1,
   'ideal ordering scores 1.0');
my $reversed = RelevanceLab::Eval::ndcg_at_k(docs(qw(b a)), $j, 2);
cmp_ok($reversed, '<', 1, 'reversed ordering scores below 1');
cmp_ok($reversed, '>', 0, 'reversed ordering still positive');
is(RelevanceLab::Eval::ndcg_at_k([], $j, 2), 0, 'empty result set -> 0');
is(RelevanceLab::Eval::ndcg_at_k(docs(qw(a b)), {}, 2), 0, 'no judgments -> 0');

# NDCG must respect grades: the highly relevant doc first beats it second.
my $graded_first  = RelevanceLab::Eval::ndcg_at_k(docs(qw(a b)), $j, 2);
my $graded_second = RelevanceLab::Eval::ndcg_at_k(docs(qw(b a)), $j, 2);
cmp_ok($graded_first, '>', $graded_second, 'grade 2 first beats grade 1 first');

done_testing();
