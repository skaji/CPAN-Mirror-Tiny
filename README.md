[![Actions Status](https://github.com/skaji/CPAN-Mirror-Tiny/actions/workflows/test/badge.svg)](https://github.com/skaji/CPAN-Mirror-Tiny/actions)

# NAME

CPAN::Mirror::Tiny - create partial CPAN mirror (a.k.a. DarkPAN)

# SYNOPSIS

    use CPAN::Mirror::Tiny;

    my $cpan = CPAN::Mirror::Tiny->new(base => "./darkpan");

    $cpan->inject("https://cpan.metacpan.org/authors/id/S/SK/SKAJI/App-cpm-0.112.tar.gz");
    $cpan->inject("https://github.com/skaji/Carl.git");
    $cpan->write_index(compress => 1);

    # $ find darkpan -type f
    # darkpan/authors/id/S/SK/SKAJI/App-cpm-0.112.tar.gz
    # darkpan/authors/id/V/VE/VENDOR/Carl-0.01-ff194fe.tar.gz
    # darkpan/modules/02packages.details.txt.gz

# DESCRIPTION

CPAN::Mirror::Tiny helps you create partial CPAN mirror (also known as DarkPAN).

There is also a command line interface [cpan-mirror-tiny](https://metacpan.org/pod/cpan-mirror-tiny) for CPAN::Mirror::Tiny.

# WHY NEW?

Yes, we already have great CPAN modules which create CPAN mirror.

[CPAN::Mini](https://metacpan.org/pod/CPAN%3A%3AMini), [OrePAN2](https://metacpan.org/pod/OrePAN2), [WorePAN](https://metacpan.org/pod/WorePAN) ...

I want to use such modules in CPAN clients.
Actually I used OrePAN2 in [Carl](https://github.com/skaji/Carl),
which can install modules in github.com or any servers.

Then minimal dependency and no dependency on XS modules is critical.
Unfortunately existing CPAN mirror modules depend on XS modules.

This is why I made CPAN::Mirror::Tiny.

# METHODS

## new

    my $cpan = CPAN::Mirror::Tiny->new(%option)

Constructor. ` %option ` may be:

- base

    Base directory for cpan mirror. If `$ENV{PERL_CPAN_MIRROR_TINY_BASE}` is set, it will be used.
    This is required.

- tempdir

    Temp directory. Default `File::Temp::tempdir(CLEANUP => 1)`.

## inject

    # automatically guess $source
    $cpan->inject($source, \%option)

    # or explicitly call inject_* method
    $cpan->inject_local('/path/to//Your-Module-0.01.tar.gz'', {author => 'YOU'});
    $cpan->inject_local_file('/path/to//Your-Module-0.01.tar.gz'', {author => 'YOU'});
    $cpan->inject_local_directory('/path/to/cpan/dir', {author => 'YOU'});

    $cpan->inject_http('http://example.com/Hoge-0.01.tar.gz', {author => 'YOU'});

    $cpan->inject_git('git://github.com/skaji/Carl.git', {author => 'SKAJI'});

    $cpan->inject_cpan('Plack', {version => '1.0039'});

Inject ` $source ` to our cpan mirror directory. ` $source ` is one of

- local tar.gz path / directory

        $cpan->inject('/path/to/Module.tar.gz', { author => "SKAJI" });
        $cpan->inject('/path/to/dir',           { author => "SKAJI" });

- http url of tar.gz

        $cpan->inject('http://example.com/Module.tar.gz', { author => "DUMMY" });

- git url (with optional ref)

        $cpan->inject('git://github.com/skaji/Carl.git', { author => "SKAJI", ref => '0.114' });

- cpan module

        $cpan->inject('cpan:Plack', {version => '1.0039'});

As seeing from the above examples, you can specify `author` in `\%option`.
If you omit `author`, default `VENDOR` is used.

**CAUTION**: Currently, the distribution name for git repository is something like
`S/SK/SKAJI/Carl-0.01-9188c0e.tar.gz`,
where `0.01` is the version and `9188c0e` is `git rev-parse --short HEAD`.

## index

    my $index_string = $cpan->index

Get the index (a.k.a. 02packages.details.txt) of our cpan mirror.

## write\_index

    $cpan->write_index( compress => bool )

Write the index to ` $base/modules/02packages.details.txt `
or ` base/modules/02packages.details.txt.gz `.

# TIPS

## How can I install modules in my DarkPAN with cpanm / cpm?

[cpanm](https://metacpan.org/pod/cpanm) is an awesome CPAN client. If you want to install modules
in your DarkPAN with cpanm, there are 2 ways.

First way:

    cpanm --cascade-search \
      --mirror-index /path/to/darkpan/modules/02packages.details.txt \
      --mirror /path/to/darkpan \
      --mirror http://www.cpan.org \
      Your::Module

Second way:

    cpanm --mirror-only \
      --mirror /path/to/darkpan \
      --mirror http://www.cpan.org \
      Your::Module

If you use [cpm](https://metacpan.org/pod/cpm), then:

    cpm install -r 02packages,file:///path/to/drakpan -r metadb Your::Module

# COPYRIGHT AND LICENSE

Copyright 2016 Shoichi Kaji <skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
