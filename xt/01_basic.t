use strict;
use warnings;
use Test::More;
use CPAN::Mirror::Tiny;
use File::Temp 'tempdir';

my $base = tempdir CLEANUP => 1;
my $cpan = CPAN::Mirror::Tiny->new($base);
$cpan->inject("https://cpan.metacpan.org/authors/id/S/SK/SKAJI/App-cpm-0.112.tar.gz");
$cpan->inject('https://github.com/shoichikaji/Carl.git', {ref => "9188c0e4", author => "SKAJI"});
$cpan->write_packages_details(compress => 1);
$cpan->write_packages_details;

for my $file (qw(
    authors/id/V/VE/VENDOR/App-cpm-0.112.tar.gz
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

like $index, qr{^App::cpm\s+0.112\s+V/VE/VENDOR/App-cpm-0.112.tar.gz$}sm;
like $index, qr{^Carl\s+0.01\s+S/SK/SKAJI/Carl-9188c0e.tar.gz$}sm;

done_testing;
