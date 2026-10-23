package RelevanceLab::Tokenizer;

# Turns raw text into index terms.
# The whole design goal here is: no CPAN, no surprises. Every rule below is
# deliberately small so that an interviewer can read it in two minutes and so
# that results are reproducible on any box with core perl.

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(tokenize normalize);

# Stopwords are dropped at index time AND at query time, so the two sides of
# retrieval always agree. If you changed that here you would have to override
# it in the Searcher too -- asymmetry between indexing and query terms is the
# number one cause of "why does this never match anything" bugs.
my %STOPWORD = map { $_ => 1 } qw(
    a about above after again against all also an and any are as at be because
    been before being below between both but by can could did do does doing down
    during each few for from further had has have here how i if in into is it its
    just more most no nor not of off on once only or other our out over own same
    should so some such than that the their them then there these they this
    through to too under until up very was we were what when where which while
    who why will with would you your
);

# A real porter stemmer is ~300 lines of rules. This is 4 lines and gets the
# plural cases that actually matter for English search:
#   queries -> query, documents -> document, policies -> policy
# Tradeoff: it over-stems some words (analysis -> analysi) and misses others
# (ranking vs ranked). Documented rather than hidden; see README.
sub normalize {
    my ($word) = @_;
    $word = lc $word;
    $word =~ s/ies$/y/ if length($word) > 4;
    $word =~ s/s$//  if length($word) > 3 && $word !~ /ss$/;
    return $word;
}

sub tokenize {
    my ($text, %opt) = @_;
    return () unless defined $text;

    # \p{L}\p{N} style unicode handling is a bigger commitment than this project
    # needs; ASCII alnum covers the corpus and keeps the regex obvious.
    my @raw = lc($text) =~ /([a-z0-9]+)/g;

    my @terms;
    for my $w (@raw) {
        next if length($w) < 2;                            # "a", "x"
        next if !$opt{keep_stopwords} && $STOPWORD{$w};
        push @terms, normalize($w);
    }
    return @terms;
}

1;
