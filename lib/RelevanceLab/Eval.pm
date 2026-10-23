package RelevanceLab::Eval;

# Offline relevance metrics. This module is the point of the project: a ranking
# change is only a change if it moves a number you trust.
#
# Judgments are graded 0 = not relevant, 1 = relevant, 2 = highly relevant.
# Graded rather than binary because "the right doc, second" and "a wrong doc"
# should not score the same.
#
#   P@k     -- share of the top k results that are relevant at all
#   MRR     -- 1 / rank of the first relevant result (0 if none in top k)
#   NDCG@k  -- gain discounted by log2(rank), normalised against the ideal order
#
# NDCG is the primary metric: it is the only one of the three that cares about
# ordering AND about how relevant each hit is.

use strict;
use warnings;
use List::Util qw(sum);

# gain for a grade: 0, 1, 3 for grades 0, 1, 2 -- exponential so that the top
# grade is worth clearly more than two middling hits.
sub _gain { my ($g) = @_; return (2 ** $g) - 1 }

sub precision_at_k {
    my ($results, $judgments, $k) = @_;
    $k ||= scalar @$results;
    my @top = @$results[ 0 .. ($k < @$results ? $k - 1 : $#$results) ];
    return 0 unless @top;
    my $relevant = grep { ($judgments->{ $_->{id} } // 0) > 0 } @top;
    return $relevant / scalar @top;
}

sub reciprocal_rank {
    my ($results, $judgments, $k) = @_;
    $k ||= scalar @$results;
    for my $i (0 .. ($k < @$results ? $k - 1 : $#$results)) {
        return 0 if $i > $#$results;
        return 1 / ($i + 1) if ($judgments->{ $results->[$i]{id} } // 0) > 0;
    }
    return 0;
}

sub dcg {
    my ($grades) = @_;
    my $dcg = 0;
    my $i   = 1;
    for my $g (@$grades) {
        # log2(i+1) written as log(i+1)/log(2); multiplying by log(2) is the
        # same thing and keeps the expression flat.
        $dcg += _gain($g) * log(2) / log($i + 1);
        $i++;
    }
    return $dcg;
}

sub ndcg_at_k {
    my ($results, $judgments, $k) = @_;
    $k ||= scalar @$results;
    my @top = @$results[ 0 .. ($k < @$results ? $k - 1 : $#$results) ];
    return 0 unless @top;
    my @actual = map { $judgments->{ $_->{id} } // 0 } @top;
    my @ideal  = sort { $b <=> $a } map { $judgments->{$_} // 0 } keys %$judgments;
    @ideal = @ideal[ 0 .. $#top ] if @ideal > @top;
    my $idcg = dcg(\@ideal);
    return 0 unless $idcg > 0;
    return dcg(\@actual) / $idcg;
}

# Evaluate a whole query set: run the searcher, score every query, average.
# Returns per-query rows plus the means, so a caller can print a table and a CI
# job can assert on the aggregate.
sub run {
    my ($class, %arg) = @_;
    my $searcher = $arg{searcher};
    my $qset     = $arg{queries};      # [ { query, judgments => { id => grade } } ]
    my $k        = $arg{k} || 5;
    my $mode     = $arg{mode} || 'or';
    die "run() needs a searcher and queries\n" unless $searcher && $qset;

    my @rows;
    for my $q (@$qset) {
        my $results = $searcher->search($q->{query}, k => $k, mode => $mode);
        push @rows, {
            query  => $q->{query},
            p      => precision_at_k($results, $q->{judgments}, $k),
            rr     => reciprocal_rank($results, $q->{judgments}, $k),
            ndcg   => ndcg_at_k($results, $q->{judgments}, $k),
            top_id => $results->[0] ? $results->[0]{id} : undef,
        };
    }

    my $n = @rows || 1;
    return {
        rows   => \@rows,
        p      => sum(map { $_->{p} } @rows) / $n,
        mrr    => sum(map { $_->{rr} } @rows) / $n,
        ndcg   => sum(map { $_->{ndcg} } @rows) / $n,
        n      => scalar @rows,
    };
}

1;
