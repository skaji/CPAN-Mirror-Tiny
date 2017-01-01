use strict;
use warnings;
use Test::More;
use HTTP::Tiny;
use CPAN::Mirror::Tiny;
use File::Temp 'tempdir';
delete $ENV{PERL_CPAN_MIRROR_TINY_BASE};

my $base = tempdir CLEANUP => 1;
my $cpan = CPAN::Mirror::Tiny->new(base => $base);
$cpan->inject("https://cpan.metacpan.org/authors/id/S/SK/SKAJI/Distribution-Metadata-0.03.tar.gz");
$cpan->inject("https://cpan.metacpan.org/authors/id/S/SK/SKAJI/Distribution-Metadata-0.04.tar.gz");

my $dist3 = "$base/authors/id/S/SK/SKAJI/Distribution-Metadata-0.03.tar.gz";
my $dist4 = "$base/authors/id/S/SK/SKAJI/Distribution-Metadata-0.04.tar.gz";
my $now = time;

subtest test1 => sub {
    utime $now - 5, $now - 5, $dist3;
    utime $now - 0, $now - 0, $dist4;
    my $index = $cpan->index;
    note $index;
    like $index, qr/Distribution::Metadata\s+0.04.*0.04/;
    like $index, qr/Distribution::Metadata::Factory\s+undef.*0.04/;
    unlike $index, qr/Distribution::Metadata\s+0.03/;
};
subtest test2 => sub {
    utime $now - 5, $now - 5, $dist4;
    utime $now - 0, $now - 0, $dist3;
    my $index = $cpan->index;
    note $index;
    like $index, qr/Distribution::Metadata\s+0.04.*0.04/;
    like $index, qr/Distribution::Metadata::Factory\s+undef.*0.03/;
    unlike $index, qr/Distribution::Metadata\s+0.03/;
};

done_testing;
