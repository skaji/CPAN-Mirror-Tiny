[![Build Status](https://travis-ci.org/shoichikaji/CPAN-Mirror-Tiny.svg?branch=master)](https://travis-ci.org/shoichikaji/CPAN-Mirror-Tiny)

# NAME

CPAN::Mirror::Tiny - create partial CPAN mirror (aka DarkPAN)

# SYNOPSIS

    use CPAN::Mirror::Tiny;

    my $cpan = CPAN::Mirror::Tiny->new("./repository");

    $cpan->inject("https://cpan.metacpan.org/authors/id/S/SK/SKAJI/App-cpm-0.112.tar.gz");
    $cpan->inject("https://github.com/shoichikaji/Carl.git");
    $cpan->write_index(compress => 1);

    # $ find repository -type f
    # repository/authors/id/V/VE/VENDOR/App-cpm-0.112.tar.gz
    # repository/authors/id/V/VE/VENDOR/Carl-ff194fe.tar.gz
    # repository/modules/02packages.details.txt.gz

# DESCRIPTION

CPAN::Mirror::Tiny helps you create partial CPAN mirror (also known as DarkPAN).

# WHY NEW?

Yes, we already have great CPAN modules which create CPAN mirror.

[CPAN::Mini](https://metacpan.org/pod/CPAN::Mini), [OrePAN2](https://metacpan.org/pod/OrePAN2), [WorePAN](https://metacpan.org/pod/WorePAN) ...

I want to use such modules in CPAN clients.
Actually I used OrePAN2 in [Carl](https://github.com/shoichikaji/Carl),
which can install modules in github.com or any servers.

Then minimal dependency and no dependency on XS modules is critical.
Unfortunately existing CPAN mirorr modules depend on XS modules.

That is why I made CPAN::Mirror::Tiny.

# COPYRIGHT AND LICENSE

Copyright 2015 Shoichi Kaji &lt;skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
