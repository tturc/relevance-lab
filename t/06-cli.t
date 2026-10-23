use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);
use File::Temp qw(tempdir);

# End-to-end: the two CLI entry points have to work from a clean checkout with
# nothing but core perl. If this test fails, a reviewer cloning the repo cannot
# reproduce the numbers in the README.
my $root = "$Bin/..";
my $dir  = tempdir(CLEANUP => 1);

# Minimal corpus, including a markdown heading so the title path is exercised.
open my $fh, '>', "$dir/alpha.md" or die $!;
print {$fh} "# Alpha document\nbm25 ranking scores documents by relevance.\n";
close $fh;
open $fh, '>', "$dir/beta.md" or die $!;
print {$fh} "# Beta document\nvector embeddings similarity gardening tomatoes.\n";
close $fh;

my $quote = sub { join ' ', map { "'$_'" } @_ };

my $index_cmd = join ' ',
    $quote->($^X, "-I$root/lib", "$root/bin/index-docs.pl",
             '--corpus', $dir, '--out', "$dir/idx.json");
my $index_out = qx{$index_cmd 2>&1};
is($?, 0, 'index-docs.pl exits 0') or diag $index_out;
like($index_out, qr/indexed 2 docs/, 'reports doc count');
like($index_out, qr/wrote .*idx\.json/, 'reports output path');
ok(-s "$dir/idx.json", 'index file exists and is non-empty');

my $search_cmd = join ' ',
    $quote->($^X, "-I$root/lib", "$root/bin/search.pl",
             '--index', "$dir/idx.json", '--query', 'bm25 ranking', '--k', '3');
my $search_out = qx{$search_cmd 2>&1};
is($?, 0, 'search.pl exits 0') or diag $search_out;
like($search_out, qr/alpha/, 'top result is the relevant document');
like($search_out, qr/\d+ hits/, 'reports hit count');

# --json mode must be parseable: this is the integration surface a caller uses.
my $json_cmd = join ' ',
    $quote->($^X, "-I$root/lib", "$root/bin/search.pl",
             '--index', "$dir/idx.json", '--query', 'vector', '--json');
my $json_out = qx{$json_cmd 2>&1};
is($?, 0, 'search.pl --json exits 0') or diag $json_out;
require JSON::PP;
my $parsed = eval { JSON::PP->new->decode($json_out) };
ok($parsed, 'json output parses') or diag $@;
is($parsed->{query}, 'vector', 'json echoes the query');
is(ref $parsed->{results}, 'ARRAY', 'json results is an array');

# Eval gate: a floor the current index clears must exit 0, an impossible floor
# must exit 1. This is the CI contract.
my $qset = "$dir/q.json";
open my $qfh, '>', $qset or die $!;
print {$qfh} '{"queries":[{"query":"bm25 ranking","judgments":{"alpha":2}}]}';
close $qfh;

my $pass_cmd = join ' ', $quote->($^X, "-I$root/lib", "$root/bin/evaluate.pl",
    '--index', "$dir/idx.json", '--queries', $qset, '--k', '3', '--min-ndcg', '0.5');
my $pass_out = qx{$pass_cmd 2>&1};
is($?, 0, 'evaluate.pl passes a floor it clears') or diag $pass_out;
like($pass_out, qr/OK: NDCG/, 'prints the OK line');

my $fail_cmd = join ' ', $quote->($^X, "-I$root/lib", "$root/bin/evaluate.pl",
    '--index', "$dir/idx.json", '--queries', $qset, '--k', '3', '--min-ndcg', '1.01');
my $fail_out = qx{$fail_cmd 2>&1};
isnt($?, 0, 'evaluate.pl fails an unreachable floor') or diag $fail_out;
like($fail_out, qr/FAIL: NDCG/, 'prints the FAIL line');

done_testing();
