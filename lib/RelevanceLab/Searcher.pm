package RelevanceLab::Searcher;

# Query entry point: query string in, ranked documents out.
#
# Retrieval model is candidate generation then scoring, which is the same shape
# a production search stack uses (it just has more candidates and a cheaper
# first pass). Keeping those two steps separate is what makes the AND mode and
# the explain output possible.

use strict;
use warnings;
use RelevanceLab::BM25;
use RelevanceLab::Tokenizer qw(tokenize);

sub new {
    my ($class, %opt) = @_;
    die "new() requires an index\n" unless $opt{index};
    return bless {
        index => $opt{index},
        bm25  => $opt{bm25} || RelevanceLab::BM25->new,
    }, $class;
}

sub search {
    my ($self, $query, %opt) = @_;
    my $k     = $opt{k}    // 10;
    my $mode  = $opt{mode} // 'or';
    my $index = $self->{index};

    # Dedupe query terms but keep first-seen order: "ranking ranking quality"
    # should be scored once and displayed predictably.
    my %seen;
    my @terms = grep { !$seen{$_}++ } tokenize($query);
    return [] unless @terms;

    # Candidate generation: only documents that contain at least one query term
    # can score above zero, so never iterate the whole collection.
    my %hits;
    for my $term (@terms) {
        my $postings = $index->{postings}{$term} or next;
        $hits{$_}++ for keys %$postings;
    }

    if ($mode eq 'and') {
        my $want = scalar @terms;
        %hits = map { $_ => 1 } grep { $hits{$_} == $want } keys %hits;
    }

    my @scored;
    for my $docpos (keys %hits) {
        my $score = $self->{bm25}->score(\@terms, $index, $docpos);
        next unless $score > 0;
        my $doc = $index->doc_at($docpos);
        push @scored, {
            id      => $doc->{id},
            title   => $doc->{title},
            len     => $doc->{len},
            score   => $score,
            matched => [ grep { $index->{postings}{$_}{$docpos} } @terms ],
        };
    }

    # Sort by score, then by id descending as a deterministic tiebreak. Stable
    # ordering matters: an eval harness that flips on ties cannot detect drift.
    @scored = sort {
        $b->{score} <=> $a->{score} || $a->{id} cmp $b->{id}
    } @scored;

    splice(@scored, $k) if @scored > $k;
    return \@scored;
}

1;
