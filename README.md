[![Build Status](https://travis-ci.org/skaji/CPAN-Mirror-Tiny.svg?branch=master)](https://travis-ci.org/skaji/CPAN-Mirror-Tiny)

# NAME

CPAN::Mirror::Tiny - create partial CPAN mirror (a.k.a. DarkPAN)

# SYNOPSIS

    use CPAN::Mirror::Tiny;

    my $cpan = CPAN::Mirror::Tiny->new(base => "./repository");

    $cpan->inject("https://cpan.metacpan.org/authors/id/S/SK/SKAJI/App-cpm-0.112.tar.gz");
    $cpan->inject("https://github.com/shoichikaji/Carl.git");
    $cpan->write_index(compress => 1);

    # $ find repository -type f
    # repository/authors/id/V/VE/VENDOR/App-cpm-0.112.tar.gz
    # repository/authors/id/V/VE/VENDOR/Carl-ff194fe.tar.gz
    # repository/modules/02packages.details.txt.gz

# DESCRIPTION

CPAN::Mirror::Tiny helps you create partial CPAN mirror (also known as DarkPAN).

## WHY NEW?

Yes, we already have great CPAN modules which create CPAN mirror.

[CPAN::Mini](https://metacpan.org/pod/CPAN::Mini), [OrePAN2](https://metacpan.org/pod/OrePAN2), [WorePAN](https://metacpan.org/pod/WorePAN) ...

I want to use such modules in CPAN clients.
Actually I used OrePAN2 in [Carl](https://github.com/shoichikaji/Carl),
which can install modules in github.com or any servers.

Then minimal dependency and no dependency on XS modules is critical.
Unfortunately existing CPAN mirror modules depend on XS modules.

This is why I made CPAN::Mirror::Tiny.

## METHODS

### `my $cpan = CPAN::Mirror::Tiny->new(%option)`

Constructor. ` %option ` may be:

- base

    Base directory for cpan mirror. This is required.

- tempdir

    Temp directory. Default `File::Temp::tempdir(CLEANUP => 1)`.

### `$cpan->inject($source, \%option)`

Inject ` $source ` to our cpan mirror directory. ` $source ` is one of

- local tar.gz path

        $cpan->inject('/path/to/Module.tar.gz', { author => "SKAJI" });

- http url of tar.gz

        $cpan->inject('http://example.com/Module.tar.gz', { author => "DUMMY" });

- git url (with optional commitish)

        $cpan->inject('git://github.com/skaji/Carl.git@0.114', { author => "SKAJI" });

As above examples shows, you can specify `author` in `\%option`.
If you omit `author`, default `VENDOR` is used.

### \* `my $index_string = $cpan->index`

Get the index (a.k.a. 02packages.details.txt) of our cpan mirror.

### \* `$cpan->write_index( compress => bool )`

Write the index to ` $base/modules/02packages.details.txt `
or ` base/modules/02packages.details.txt.gz `.

# COPYRIGHT AND LICENSE

Copyright 2016 Shoichi Kaji &lt;skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
