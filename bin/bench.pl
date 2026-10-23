#!/usr/bin/env perl

# Latency microbenchmark.
#
#   perl -Ilib bin/bench.pl --iterations 200
#
# Reports in-process query latency, which is the number that matters for a
# ranking decision. It deliberately excludes process start and index decode,
# because those are one-off costs per worker, not per query. For the CLI number
# that includes both, time the command itself.

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use Time::HiRes qw(time);
use JSON::PP;
use RelevanceLab::Index;
use RelevanceLab::Searcher;

my %opt = (index => 'index/corpus.json', queries => 'eval/queries.json', iterations => 100);
GetOptions(
    'index=s'      => \$opt{index},
    'queries=s'    => \$opt{queries},
    'iterations=i' => \$opt{iterations},
) or die "bad options\n";

my $t_load = time;
my $index  = RelevanceLab::Index->load($opt{index});
my $searcher = RelevanceLab::Searcher->new(index => $index);
my $load_ms = (time - $t_load) * 1000;

open my $fh, '<:encoding(UTF-8)', $opt{queries} or die "cannot read $opt{queries}: $!\n";
my $raw = do { local $/; <$fh> };
close $fh;
my @queries = map { $_->{query} } @{ JSON::PP->new->decode($raw)->{queries} };

# Warm the caches before timing so the first query does not pay for hash growth.
$searcher->search($_) for @queries;

my @samples;
for my $n (1 .. $opt{iterations}) {
    for my $q (@queries) {
        my $t0 = time;
        $searcher->search($q, k => 5);
        push @samples, (time - $t0) * 1e6;    # microseconds
    }
}

my @sorted = sort { $a <=> $b } @samples;
my $n      = scalar @sorted;
my $sum    = 0;
$sum += $_ for @sorted;
my $p95 = $sorted[ int(0.95 * $n) ];
my $p50 = $sorted[ int(0.50 * $n) ];

printf "docs indexed:      %d\n", $index->n_docs;
printf "index load:        %.2f ms (one-off per worker)\n", $load_ms;
printf "queries timed:     %d (%d x %d distinct)\n", $n, $opt{iterations}, scalar @queries;
printf "mean query:        %.1f us\n", $sum / $n;
printf "median query:      %.1f us\n", $p50;
printf "p95 query:         %.1f us\n", $p95;
