#!/usr/bin/env perl

# Run the offline eval set and report P@k, MRR and NDCG@k.
#
#   perl -Ilib bin/evaluate.pl --queries eval/queries.json --k 5
#   perl -Ilib bin/evaluate.pl --min-ndcg 0.80   # CI gate: exit 1 on regression
#
# The --min-ndcg flag is what turns this from a report into a test: a ranking
# change that drops the aggregate below the floor fails the build instead of
# being noticed three weeks later in a dashboard.

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use JSON::PP;
use RelevanceLab::Index;
use RelevanceLab::Searcher;
use RelevanceLab::Eval;

my %opt = (index => 'index/corpus.json', queries => 'eval/queries.json', k => 5, mode => 'or');
GetOptions(
    'index=s'    => \$opt{index},
    'queries=s'  => \$opt{queries},
    'k=i'        => \$opt{k},
    'mode=s'     => \$opt{mode},
    'min-ndcg=f' => \$opt{min_ndcg},
    'verbose|v'  => \$opt{verbose},
) or die "bad options\n";

die "no such query file: $opt{queries}\n" unless -e $opt{queries};

open my $fh, '<:encoding(UTF-8)', $opt{queries} or die "cannot read $opt{queries}: $!\n";
my $raw = do { local $/; <$fh> };
close $fh;

# judgments arrive as { "doc-id" => grade }; JSON object keys are strings, which
# is exactly how the results ids are stored, so no coercion is needed.
my $qset = JSON::PP->new->decode($raw)->{queries};
die "$opt{queries} has no queries array\n" unless ref $qset eq 'ARRAY';

my $index    = RelevanceLab::Index->load($opt{index});
my $searcher = RelevanceLab::Searcher->new(index => $index);

my $report = RelevanceLab::Eval->run(
    searcher => $searcher,
    queries  => $qset,
    k        => $opt{k},
    mode     => $opt{mode},
);

printf "eval: %d queries, k=%d, mode=%s\n\n", $report->{n}, $opt{k}, $opt{mode};
printf "  %-46s %5s %5s %5s\n", 'query', 'P@k', 'RR', 'NDCG';
printf "  %s\n", '-' x 64;
for my $row (@{ $report->{rows} }) {
    printf "  %-46s %5.2f %5.2f %5.2f\n", substr($row->{query}, 0, 46),
        $row->{p}, $row->{rr}, $row->{ndcg};
}
printf "  %s\n", '-' x 64;
printf "  %-46s %5.2f %5.2f %5.2f\n", 'MEAN', $report->{p}, $report->{mrr}, $report->{ndcg};

if (defined $opt{min_ndcg}) {
    if ($report->{ndcg} + 1e-9 < $opt{min_ndcg}) {
        printf "\nFAIL: NDCG %.3f below floor %.3f\n", $report->{ndcg}, $opt{min_ndcg};
        exit 1;
    }
    printf "\nOK: NDCG %.3f >= floor %.3f\n", $report->{ndcg}, $opt{min_ndcg};
}

exit 0;
