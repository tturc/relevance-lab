use strict;
use warnings;
use Test::More;
use lib 'lib';
use RelevanceLab::Index;
use RelevanceLab::Searcher;

my $idx = RelevanceLab::Index->new;
$idx->add_document(id => 'bm25-doc',   title => 'BM25',        text => 'bm25 ranking function scores documents');
$idx->add_document(id => 'vector-doc', title => 'Vectors',     text => 'vector embeddings similarity');
$idx->add_document(id => 'mixed-doc',  title => 'Hybrid',      text => 'bm25 and vector scores merged');
$idx->add_document(id => 'noise-doc',  title => 'Unrelated',   text => 'gardening tomatoes soil');
$idx->finalize;

my $searcher = RelevanceLab::Searcher->new(index => $idx);

# OR mode: any term matches, ranked by score.
my $res = $searcher->search('bm25 vector');
is(scalar @$res, 3, 'or-mode returns every doc with either term');
is($res->[0]{id}, 'mixed-doc', 'doc matching both terms ranks first');

# AND mode: every term must be present.
my $and = $searcher->search('bm25 vector', mode => 'and');
is(scalar @$and, 1, 'and-mode keeps only docs with all terms');
is($and->[0]{id}, 'mixed-doc', 'and-mode survivor');

# A term no document contains yields an empty result, not an error.
is_deeply($searcher->search('zeppelin'), [], 'unmatched query returns empty list');
is_deeply($searcher->search(''), [], 'empty query returns empty list');
is_deeply($searcher->search('!! ??'), [], 'punctuation-only query returns empty list');

# k truncates, and scores are monotonically non-increasing.
my $top2 = $searcher->search('bm25 vector scores', k => 2);
is(scalar @$top2, 2, 'k limits result count');
cmp_ok($top2->[0]{score}, '>=', $top2->[1]{score}, 'results are ordered by score');

# Explain data: which query terms hit each document.
my $explained = $searcher->search('bm25 vector');
my ($mixed) = grep { $_->{id} eq 'mixed-doc' } @$explained;
is_deeply([ sort @{ $mixed->{matched} } ], [qw(bm25 vector)], 'matched terms reported');

# Stopwords in the query are ignored, not treated as terms.
my $stop = $searcher->search('the of and');
is_deeply($stop, [], 'stopword-only query returns nothing');

done_testing();
