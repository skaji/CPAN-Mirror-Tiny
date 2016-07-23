use strict;
use warnings;
use Test::More;
use HTTP::Tiny;
use CPAN::Mirror::Tiny;
use File::Temp 'tempdir';

my $base = tempdir CLEANUP => 1;
my $cpan = CPAN::Mirror::Tiny->new(base => $base);
$cpan->inject("https://cpan.metacpan.org/authors/id/S/SK/SKAJI/App-cpm-0.112.tar.gz");
$cpan->inject('https://github.com/skaji/Carl.git', {ref => "9188c0e4", author => "SKAJI"});
{
    my $url = "http://cpan.metacpan.org/authors/id/S/SK/SKAJI/CPAN-Mirror-Tiny-0.02.tar.gz";
    my $tarball = tempdir(CLEANUP => 1) . "/CPAN-Mirror-Tiny-0.02.tar.gz";
    my $res = HTTP::Tiny->new->mirror($url, $tarball);
    die unless $res->{success};
    $cpan->inject($tarball);
    ok -f $tarball; # make sure we keep original tarball
}
$cpan->write_index(compress => 1);
$cpan->write_index;

for my $file (qw(
    authors/id/V/VE/VENDOR/App-cpm-0.112.tar.gz
    authors/id/V/VE/VENDOR/CPAN-Mirror-Tiny-0.02.tar.gz
    authors/id/S/SK/SKAJI/Carl-9188c0e.tar.gz
    modules/02packages.details.txt.gz
    modules/02packages.details.txt
)) {
    ok -f "$base/$file";
}

my $index = do {
    open my $fh, "<", "$base/modules/02packages.details.txt";
    local $/; <$fh>;
};

note $index;

like $index, qr{^App::cpm\s+0.112\s+V/VE/VENDOR/App-cpm-0.112.tar.gz$}sm;
like $index, qr{^CPAN::Mirror::Tiny::Server\s+undef\s+V/VE/VENDOR/CPAN-Mirror-Tiny-0.02.tar.gz$}sm;
like $index, qr{^Carl\s+0.01\s+S/SK/SKAJI/Carl-9188c0e.tar.gz$}sm;

done_testing;
