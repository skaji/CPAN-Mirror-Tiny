use strict;
use warnings;
use Test::More;
use HTTP::Tiny;
use CPAN::Mirror::Tiny;
use File::Temp 'tempdir';
delete $ENV{PERL_CPAN_MIRROR_TINY_BASE};

my $base = tempdir CLEANUP => 1;
my $cpan = CPAN::Mirror::Tiny->new(base => $base);
$cpan->inject('https://github.com/skaji/Process-Pipeline.git@0.03',  { author => "SKAJI"});

ok -f "$base/authors/id/S/SK/SKAJI/Process-Pipeline-0.03-831eed0.tar.gz";

done_testing;
