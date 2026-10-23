use strict;
use warnings;
use Test::More;
use lib 'lib';
use File::Temp qw(tempdir);
use RelevanceLab::Index;

my $idx = RelevanceLab::Index->new;
$idx->add_document(id => 'a', title => 'A', text => 'alpha beta beta gamma');
$idx->add_document(id => 'b', title => 'B', text => 'beta delta');
$idx->finalize;

is($idx->n_docs, 2, 'doc count');
is($idx->df_of('beta'), 2, 'df counts docs not occurrences');
is($idx->df_of('alpha'), 1, 'df for a single-doc term');
is($idx->df_of('nope'), 0, 'missing term has df 0');

# doc a has 4 terms, doc b has 2 -> avgdl 3
cmp_ok($idx->avgdl, '==', 3, 'avgdl is mean length');
is($idx->doc_at(0)->{len}, 4, 'length is post-tokenisation term count');
is($idx->doc_at(1)->{len}, 2, 'short doc length');

# Term frequency, not just presence.
is($idx->{postings}{beta}{0}, 2, 'tf stored for repeated term');
is($idx->{postings}{beta}{1}, 1, 'tf stored per doc');
ok(!exists $idx->{postings}{beta}{2}, 'no posting for a doc without the term');

# Empty documents keep their slot so doc ids never shift.
my $idx2 = RelevanceLab::Index->new;
$idx2->add_document(id => 'empty', text => '');
$idx2->add_document(id => 'real',  text => 'word');
$idx2->finalize;
is($idx2->n_docs, 2, 'empty doc still counted');
is($idx2->doc_at(1)->{id}, 'real', 'slot preserved after empty doc');

# Round-trip: a saved index must reload identical, or the CLI and eval disagree.
my $dir  = tempdir(CLEANUP => 1);
my $path = "$dir/idx.json";
$idx->save($path);
my $loaded = RelevanceLab::Index->load($path);
is($loaded->n_docs, $idx->n_docs, 'reload: doc count');
is($loaded->n_terms, $idx->n_terms, 'reload: term count');
is_deeply($loaded->{postings}{beta}, $idx->{postings}{beta}, 'reload: postings identical');
cmp_ok($loaded->avgdl, '==', $idx->avgdl, 'reload: avgdl identical');
is($loaded->doc_at(0)->{id}, 'a', 'reload: ids preserved');

done_testing();
