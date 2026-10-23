package RelevanceLab::BM25;

# Okapi BM25 -- the ranking function underneath Elasticsearch, Lucene, and most
# search stacks that predate dense retrieval. Worth knowing cold: it is three
# intuitions in one formula and interviewers love it.
#
#   score(D, Q) = SUM over q in Q of  idf(q) * (tf * (k1+1)) / (tf + k1*(1 - b + b*dl/avgdl))
#
#   1. idf   -- a term in few documents is more informative than a common one.
#   2. tf    -- more occurrences help, but with diminishing returns (k1 controls
#               where saturation kicks in; tf cannot grow without bound).
#   3. dl    -- length normalisation (b=1 normalises fully, b=0 not at all), so
#               a 400-word doc does not outrank a 40-word doc just by volume.

use strict;
use warnings;

sub new {
    my ($class, %opt) = @_;
    return bless {
        k1 => exists $opt{k1} ? $opt{k1} : 1.2,   # saturation point for term frequency
        b  => exists $opt{b}  ? $opt{b}  : 0.75,  # how hard to punish long documents
    }, $class;
}

# The +1 inside the log keeps idf strictly positive. The classic textbook form
# goes negative for terms appearing in more than half the collection, which
# makes rare-term and common-term docs fight each other in ways that are hard to
# explain to a product owner.
sub idf {
    my ($self, $df, $n_docs) = @_;
    return 0 unless $n_docs > 0;
    return log(1 + ($n_docs - $df + 0.5) / ($df + 0.5));
}

# Score one document against a set of query terms.
#   $postings -- { docpos => tf } for one term
sub score {
    my ($self, $query_terms, $index, $docpos) = @_;
    my $avgdl = $index->avgdl;
    my $doc   = $index->doc_at($docpos);
    my $dl    = $doc ? $doc->{len} : 0;
    my $n     = $index->n_docs;

    my $score = 0;
    for my $term (@$query_terms) {
        my $tf = $index->{postings}{$term}{$docpos} // 0;
        next unless $tf;
        my $idf = $self->idf($index->df_of($term), $n);
        my $denom = $tf + $self->{k1} * (1 - $self->{b} + $self->{b} * ($avgdl ? $dl / $avgdl : 0));
        $score += $idf * (($tf * ($self->{k1} + 1)) / $denom);
    }
    return $score;
}

1;
