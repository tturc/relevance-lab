package RelevanceLab::Index;

# In-memory inverted index with JSON persistence.
#
# Shape:
#   docs     => [ { id, title, len }, ... ]      # array position = internal docid
#   postings => { term => { docpos => tf } }     # forward-index inverted
#   df       => { term => number_of_docs_containing_term }
#
# Why arrays-and-hashes instead of a database: at this corpus size an in-memory
# hash IS the fastest index. The interesting engineering is the ranking, not the
# storage. The JSON layer exists so the index can be built once in CI and reused.

use strict;
use warnings;
use JSON::PP;
use RelevanceLab::Tokenizer qw(tokenize);

sub new {
    my ($class) = @_;
    return bless {
        docs      => [],
        postings  => {},
        df        => {},
        total_len => 0,
        built_at  => undef,
    }, $class;
}

# Add one document. Called streaming so a caller can index files without
# holding the whole corpus in memory twice.
sub add_document {
    my ($self, %doc) = @_;
    die "add_document needs an id\n" unless defined $doc{id};

    my %tf;
    $tf{$_}++ for tokenize($doc{text});

    my $len = 0;
    $len += $_ for values %tf;
    my $docpos = scalar @{ $self->{docs} };
    push @{ $self->{docs} }, {
        id    => "$doc{id}",
        title => defined $doc{title} ? "$doc{title}" : "",
        len   => $len,
    };

    # Skip empty documents in the postings but keep them in docs, so doc ids
    # never shift and search results stay explainable.
    for my $term (keys %tf) {
        $self->{postings}{$term}{$docpos} = $tf{$term};
        $self->{df}{$term}++;
    }
    $self->{total_len} += $len;
    return $self;
}

sub finalize {
    my ($self) = @_;
    my $n = scalar @{ $self->{docs} };
    # avgdl feeds BM25's length normalisation: long docs are not better by
    # virtue of being long.
    $self->{avgdl} = $n ? $self->{total_len} / $n : 0;
    $self->{built_at} = time;
    return $self;
}

sub n_docs    { scalar @{ $_[0]{docs} } }
sub n_terms   { scalar keys %{ $_[0]{postings} } }
sub avgdl     { $_[0]{avgdl} // 0 }
sub doc_at    { $_[0]{docs}[ $_[1] ] }
sub postings  { $_[0]{postings} }
sub df_of     { $_[0]{df}{ $_[1] } // 0 }

sub save {
    my ($self, $path) = @_;
    $self->finalize unless defined $self->{avgdl};
    my $json = JSON::PP->new->canonical->pretty->encode({
        version   => 1,
        avgdl     => $self->{avgdl},
        total_len => $self->{total_len},
        built_at  => $self->{built_at},
        docs      => $self->{docs},
        df        => $self->{df},
        postings  => $self->{postings},
    });
    open my $fh, '>:raw', $path or die "cannot write $path: $!\n";
    print {$fh} $json;
    close $fh or die "cannot close $path: $!\n";
    return $path;
}

sub load {
    my ($class, $path) = @_;
    open my $fh, '<:raw', $path or die "cannot read $path: $!\n";
    local $/;
    my $raw = <$fh>;
    close $fh;
    my $data = JSON::PP->new->decode($raw);
    die "$path is not a v1 index\n" unless ($data->{version} // 0) == 1;

    # JSON keys are strings; docpos keys come back as "0","1",... which is fine
    # because Perl auto-vivifies numeric strings into numeric hash keys.
    return bless {
        docs      => $data->{docs},
        postings  => $data->{postings},
        df        => $data->{df},
        avgdl     => $data->{avgdl},
        total_len => $data->{total_len},
        built_at  => $data->{built_at},
    }, $class;
}

1;
