use strict;
use warnings;
use Test::More;
use HTTP::Tiny;
use CPAN::Mirror::Tiny;
use HTTP::Tinyish;
use File::Temp 'tempdir';

my $base = tempdir CLEANUP => 1;
my $cpan = CPAN::Mirror::Tiny->new(base => $base);
$cpan->inject("cpan:Process::Pipeline");
$cpan->inject('cpan:App::cpm@0.294');
$cpan->inject_cpan('App::FatPacker::Simple', {version => '0.06'});
$cpan->write_index;

like $cpan->index, qr{^Process::Pipeline\s+[\d.]+\s+S/SK/SKAJI/Process-Pipeline-}sm;
like $cpan->index, qr{^App::cpm::Job\s+0.294\s+S/SK/SKAJI/App-cpm-0.294.tar.gz$}sm;
like $cpan->index, qr{^App::FatPacker::Simple\s+0.06\s+S/SK/SKAJI/App-FatPacker-Simple-0.06.tar.gz$}sm;
note $cpan->index;

done_testing;
