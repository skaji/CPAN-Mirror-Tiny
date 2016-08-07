use strict;
use warnings;
use Test::More;
use HTTP::Tiny;
use CPAN::Mirror::Tiny;
use File::Temp 'tempdir';
plan skip_all => "This is author's test" if $ENV{USER} ne "skaji";

my $base = tempdir CLEANUP => 1;
my $cpan = CPAN::Mirror::Tiny->new(base => $base);
$cpan->inject('git@github.com:skaji/cpm.git@0.115',  { author => "SKAJI"});

ok -f "$base/authors/id/S/SK/SKAJI/App-cpm-0.115-244c125.tar.gz";

done_testing;
