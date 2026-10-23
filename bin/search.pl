#!/usr/bin/env perl

# Query the index.
#
#   perl -Ilib bin/search.pl --query "how does bm25 rank documents" --k 5
#   perl -Ilib bin/search.pl --query "vector search" --mode and --explain
#   perl -Ilib bin/search.pl --query "cache invalidation" --json
#
# Modes: or (default, any term matches) and and (every term must appear).
# --explain prints which query terms matched each document, which is the fastest
# way to debug a ranking you did not expect.

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use JSON::PP;
use Time::HiRes qw(time);
use RelevanceLab::Index;
use RelevanceLab::Searcher;

my %opt = (index => 'index/corpus.json', k => 10, mode => 'or');
GetOptions(
    'index=s' => \$opt{index},
    'query|q=s' => \$opt{query},
    'k=i'     => \$opt{k},
    'mode=s'  => \$opt{mode},
    'explain' => \$opt{explain},
    'json'    => \$opt{json},
) or die "bad options\n";

die "usage: search.pl --query \"...\" [--index path] [--k N] [--mode or|and] [--explain] [--json]\n"
    unless defined $opt{query} && length $opt{query};

my $index    = RelevanceLab::Index->load($opt{index});
my $searcher = RelevanceLab::Searcher->new(index => $index);

my $t0      = time;
my $results = $searcher->search($opt{query}, k => $opt{k}, mode => $opt{mode});
my $elapsed = (time - $t0) * 1000;

if ($opt{json}) {
    print JSON::PP->new->canonical->pretty->encode({
        query   => $opt{query},
        mode    => $opt{mode},
        took_ms => sprintf('%.3f', $elapsed),
        results => $results,
    });
    exit 0;
}

printf "query: %s  (mode=%s, %d hits, %.2f ms)\n\n",
    $opt{query}, $opt{mode}, scalar @$results, $elapsed;

if (!@$results) {
    print "  no matches\n";
    exit 0;
}

my $rank = 0;
for my $r (@$results) {
    $rank++;
    printf "  %2d. %-28s %6.3f  %s\n", $rank, $r->{id}, $r->{score}, $r->{title};
    printf "      matched: %s\n", join(', ', @{ $r->{matched} }) if $opt{explain};
}
