use strict;
use warnings;
use Test::More;
use HTTP::Tiny;
use CPAN::Mirror::Tiny;
use IPC::Run3 ();
use HTTP::Tinyish;
use File::Temp 'tempdir';
delete $ENV{PERL_CPAN_MIRROR_TINY_BASE};

my $temp = tempdir CLEANUP => 1;
IPC::Run3::run3 [qw(git clone --quiet -b 0.04 git://github.com/skaji/Process-Pipeline), "$temp/dir"],
    undef, undef, \undef;
die if $? != 0;
my $res = HTTP::Tinyish->new->mirror("https://cpan.metacpan.org/authors/id/S/SK/SKAJI/Mojo-SlackRTM-0.02.tar.gz" => "$temp/hoge.tar.gz");
$res->{success} or die;

my $base = tempdir CLEANUP => 1;
my $cpan = CPAN::Mirror::Tiny->new(base => $base);
$cpan->inject("$temp/dir");
$cpan->inject("$temp/hoge.tar.gz");

ok -d "$temp/dir";
ok -f "$temp/hoge.tar.gz";
ok -f "$base/authors/id/V/VE/VENDOR/Mojo-SlackRTM-0.02.tar.gz";
ok -f "$base/authors/id/V/VE/VENDOR/Process-Pipeline-0.04.tar.gz";

done_testing;
