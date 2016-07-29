[![Build Status](https://travis-ci.org/skaji/CPAN-Mirror-Tiny.svg?branch=master)](https://travis-ci.org/skaji/CPAN-Mirror-Tiny)

# NAME

CPAN::Mirror::Tiny - create partial CPAN mirror (a.k.a. DarkPAN)

# SYNOPSIS

    use CPAN::Mirror::Tiny;

    my $cpan = CPAN::Mirror::Tiny->new(base => "./repository");

    $cpan->inject("https://cpan.metacpan.org/authors/id/S/SK/SKAJI/App-cpm-0.112.tar.gz");
    $cpan->inject("https://github.com/skaji/Carl.git");
    $cpan->write_index(compress => 1);

    # $ find repository -type f
    # repository/authors/id/V/VE/VENDOR/App-cpm-0.112.tar.gz
    # repository/authors/id/V/VE/VENDOR/Carl-0.01-ff194fe.tar.gz
    # repository/modules/02packages.details.txt.gz

# DESCRIPTION

CPAN::Mirror::Tiny helps you create partial CPAN mirror (also known as DarkPAN).

# WHY NEW?

Yes, we already have great CPAN modules which create CPAN mirror.

[CPAN::Mini](https://metacpan.org/pod/CPAN::Mini), [OrePAN2](https://metacpan.org/pod/OrePAN2), [WorePAN](https://metacpan.org/pod/WorePAN) ...

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

    Base directory for cpan mirror. This is required.

- tempdir

    Temp directory. Default `File::Temp::tempdir(CLEANUP => 1)`.

## inject

    $cpan->inject($source, \%option)

Inject ` $source ` to our cpan mirror directory. ` $source ` is one of

- local tar.gz path

        $cpan->inject('/path/to/Module.tar.gz', { author => "SKAJI" });

- http url of tar.gz

        $cpan->inject('http://example.com/Module.tar.gz', { author => "DUMMY" });

- git url (with optional ref)

        $cpan->inject('git://github.com/skaji/Carl.git', { author => "SKAJI", ref => '0.114' });

As seeing from the above examples, you can specify `author` in `\%option`.
If you omit `author`, default `VENDOR` is used.

**CAUTION**: Currently, the distribution name for git repository is somthing like
`S/SK/SKAJI/Carl-0.01-9188c0e.tar.gz`,
where `0.01` is the version and `9188c0e` is `git rev-parse --short HEAD`.
However this naming convention is likely to change. Do not depend on this!

## index

    my $index_string = $cpan->index

Get the index (a.k.a. 02packages.details.txt) of our cpan mirror.

## write\_index

    $cpan->write_index( compress => bool )

Write the index to ` $base/modules/02packages.details.txt `
or ` base/modules/02packages.details.txt.gz `.

# TIPS

## How can I install modules in my DarkPAN with cpanm?

[cpanm](https://metacpan.org/pod/cpanm) is an awesome CPAN clients. If you want to install modules
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

I hope that cpanm delegates the process of not only resolving modules
but also fetching modules to [CPAN::Common::Index](https://metacpan.org/pod/CPAN::Common::Index)-like objects entirely.
Then we can hack cpanm easily.

I believe that cpanm 2.0 also known as [Menlo](https://metacpan.org/pod/Menlo) comes with such features!

# COPYRIGHT AND LICENSE

Copyright 2016 Shoichi Kaji <skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
