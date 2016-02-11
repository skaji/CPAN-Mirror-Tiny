requires 'perl', '5.008001';

requires 'CPAN::Meta';
requires 'Capture::Tiny';
requires 'File::Which';
requires 'File::pushd';
requires 'HTTP::Tinyish';
requires 'Parse::LocalDistribution';

recommends 'Plack';

on develop => sub {
    requires 'Test::More', '0.98';
};
