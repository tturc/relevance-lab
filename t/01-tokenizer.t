use strict;
use warnings;
use Test::More;
use lib 'lib';
use RelevanceLab::Tokenizer qw(tokenize normalize);

# Basic contract: lowercase, split on non-alphanumerics, drop noise.
is_deeply([ tokenize("The Quick, brown FOX!") ], [qw(quick brown fox)], 'lowercases and splits');

# Stopwords are dropped by default so index and query agree.
is_deeply([ tokenize("the state of the index") ], [qw(state index)], 'stopwords removed');
is_deeply([ tokenize("the state of the index", keep_stopwords => 1) ],
          [qw(the state of the index)], 'stopwords can be kept');

# Single characters are noise ("a", "x") but not numbers or real short words.
is_deeply([ tokenize("a x go 42") ], [qw(go 42)], 'single chars dropped, 2-char kept');

# The four-line stemmer: only the plural cases that matter for English search.
is(normalize('queries'),   'query',    'ies -> y');
is(normalize('documents'), 'document', 'trailing s stripped');
is(normalize('policies'),  'policy',   'ies -> y again');
is(normalize('class'),     'class',    'ss is not stripped');
is(normalize('is'),        'is',       'two-letter word untouched');

# Documented limitation, asserted so a future "fix" has to think about it:
# -ing is NOT stemmed, so ranking and rank never meet.
is_deeply([ tokenize("ranking rank") ], [qw(ranking rank)], 'no -ing stemming (known limitation)');

# Punctuation-only and undef input must not explode.
is_deeply([ tokenize("") ], [], 'empty string');
is_deeply([ tokenize(undef) ], [], 'undef');

done_testing();
