#!/usr/bin/env perl

# Build an index from a directory of text/markdown files.
#
#   perl -Ilib bin/index-docs.pl --corpus corpus --out index/corpus.json
#
# Reads every *.md in --corpus, uses the first "# heading" as the title (falling
# back to the filename), and streams each file into the index so memory stays
# proportional to the index rather than to the raw corpus.

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use File::Basename qw(basename);
use RelevanceLab::Index;

my ($corpus, $out, $verbose) = ('corpus', 'index/corpus.json', 0);
GetOptions(
    'corpus=s' => \$corpus,
    'out=s'    => \$out,
    'verbose|v' => \$verbose,
) or die "bad options\n";

die "no such corpus directory: $corpus\n" unless -d $corpus;

my $index = RelevanceLab::Index->new;
my @files = sort glob("$corpus/*.md");
die "no *.md files in $corpus\n" unless @files;

for my $path (@files) {
    open my $fh, '<:encoding(UTF-8)', $path or die "cannot read $path: $!\n";
    my $text = do { local $/; <$fh> };
    close $fh;

    # Title is the first markdown heading, else the filename stem.
    my ($title) = $text =~ /^\#\s+(.+)$/m;
    $title = basename($path, '.md') unless defined $title;
    chomp $title;

    my $id = basename($path, '.md');
    $index->add_document(id => $id, title => $title, text => $text);
    printf "  indexed %-28s %4d chars\n", $id, length($text) if $verbose;
}

$index->finalize;

# Make sure the output directory exists rather than making the caller mkdir.
if ($out =~ m{^(.*)/[^/]+$}) {
    my $dir = $1;
    mkdir $dir unless -d $dir;
}

$index->save($out);

printf "indexed %d docs, %d unique terms, avg %.1f terms/doc\n",
    $index->n_docs, $index->n_terms, $index->avgdl;
printf "wrote %s (%d bytes)\n", $out, -s $out;
