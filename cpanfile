requires 'perl', '5.008001';

requires 'CPAN::Meta';
requires 'Capture::Tiny';
requires 'File::Copy::Recursive';
requires 'File::Which';
requires 'File::pushd';
requires 'HTTP::Tinyish';
requires 'JSON';
requires 'Parse::LocalDistribution';
requires 'Parse::PMFile';
requires 'Pod::Usage', '1.33';
requires 'String::ShellQuote';
requires 'Win32::ShellQuote';
requires 'Plack::App::Directory';
requires 'Plack::Builder';
requires 'Plack::Request';
requires 'Plack::Runner';

recommends 'Plack';

on develop => sub {
    requires 'Test2::Harness';
};
