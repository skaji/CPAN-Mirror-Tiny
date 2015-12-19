package CPAN::Mirror::Tiny;
use 5.008001;
use strict;
use warnings;

our $VERSION = '0.01';

use CPAN::Meta;
use CPAN::Mirror::Tiny::Archive;
use Capture::Tiny ();
use Cwd ();
use File::Basename ();
use File::Copy ();
use File::Path ();
use File::Spec;
use File::Temp ();
use File::pushd ();
use HTTP::Tinyish;
use Parse::LocalDistribution;

sub new {
    my $class = shift;
    my $base  = shift or die "Missing base directory argument";
    File::Path::mkpath($base) unless -d $base;
    $base = Cwd::abs_path($base);
    my $archive = CPAN::Mirror::Tiny::Archive->new;
    my $http = HTTP::Tinyish->new;
    my $workdir = File::Temp::tempdir(CLEANUP => 1);
    bless {
        base => $base,
        archive => $archive,
        http => $http,
        workdir => $workdir,
    }, $class;
}

sub archive { shift->{archive} }
sub http { shift->{http} }

sub extract {
    my ($self, $path) = @_;
    if ($path =~ /\.zip$/) {
        $self->archive->unzip($path);
    } else {
        $self->archive->untar($path);
    }
}

sub base {
    my $self = shift;
    my $base = $self->{base};
    if (@_) {
        File::Spec->catdir($base, @_);
    } else {
        $base;
    }
}

sub workdir {
    my $self = shift;
    return $self->{workdir} unless @_;
    File::Spec->catdir($self->{workdir}, @_);
}

sub tempdir {
    my $self = shift;
    my $workdir = $self->workdir;
    File::Temp::tempdir(CLEANUP => 0, DIR => $workdir);
}

sub _author_dir {
    my ($self, $author) = @_;
    my ($a2, $a1) = $author =~ /^((.).)/;
    $self->base("authors/id/$a1/$a2/$author");
}

sub _locate_tarball {
    my ($self, $file, $author) = @_;
    my $dir = $self->_author_dir($author);
    File::Path::mkpath($dir) unless -d $dir;
    my $basename = File::Basename::basename($file);
    my $dest = File::Spec->catfile($dir, $basename);
    File::Copy::move($file, $dest);
    return -f $dest ? $dest : undef;
}

sub _system {
    my ($self, @command) = @_;
    my ($merged, $exit) = Capture::Tiny::capture_merged(sub { system @command });
    return (!$exit, $merged || "");
}

sub inject {
    my ($self, $url, $option) = @_;
    if ($url =~ /(?:^git:|\.git$)/) {
        $self->inject_git($url, $option);
    } else {
        $self->inject_http($url, $option);
    }
}

sub inject_http {
    my ($self, $url, $option) = @_;
    my $author = ($option ||= {})->{author} || "VENDOR";
    if ($url !~ /(?:\.tgz|\.tar\.gz|\.tar\.bz2|\.zip)$/) {
        die "URL must be tarball or zipball\n";
    }
    my $basename = File::Basename::basename($url);
    my $file = $self->workdir($basename);
    my $res = $self->http->mirror($url => $file);
    if ($res->{success}) {
        return $self->_locate_tarball($file, $author);
    } else {
        die "Couldn't get $url: $res->{status} $res->{reason}";
    }
}

sub inject_git {
    my ($self, $url, $option) = @_;
    my $author = ($option ||= {})->{author} || "VENDOR";
    my $ref    = ($option ||= {})->{ref};
    my $tempdir = $self->tempdir;
    my ($ok, $error) = $self->_system("git", "clone", $url, $tempdir);
    die "Couldn't git clone $url: $error" unless $ok;
    my $guard = File::pushd::pushd($tempdir);
    if ($ref) {
        my ($ok, $error) = $self->_system("git", "checkout", $ref);
        die "Couldn't git checkout $ref: $error" unless $ok;
    }
    my $metafile = "META.json";
    die "Couldn't find $metafile in $url" unless -f $metafile;
    my $meta = CPAN::Meta->load_file($metafile);
    chomp(my $rev = `git rev-parse --short HEAD`);
    my $distvname = sprintf "%s-%s", $meta->name, $rev;
    ($ok, $error) = $self->_system(
        "git archive --format=tar --prefix=$distvname/ HEAD | gzip > $distvname.tar.gz"
    );
    if ($ok && -f "$distvname.tar.gz") {
        return $self->_locate_tarball("$distvname.tar.gz", $author);
    } else {
        die "Couldn't archive $url: $error";
    }
}

sub extract_provides {
    my ($self, $path) = @_;
    unless (File::Spec->file_name_is_absolute($path)) {
        $path = Cwd::abs_path($path);
    }
    my $gurad = File::pushd::pushd($self->tempdir);
    my $dir = $self->extract($path) or return;
    my $parser = Parse::LocalDistribution->new({ALLOW_DEV_VERSION => 1});
    my $hash = $parser->parse($dir) || +{};
    [map +{ package => $_, version => $hash->{$_}{version} }, sort keys %$hash];
}

sub index {
    my $self = shift;
    my $base = $self->base("authors/id");
    return unless -d $base;
    my @collect;
    my $wanted = sub {
        return unless /(?:\.tgz|\.tar\.gz|\.tar\.bz2|\.zip)$/;
        my $path = $_;
        my $provides = $self->extract_provides($path);
        for my $provide (@$provides) {
            push @collect, {
                path => File::Spec->abs2rel($path, $base),
                package => $provide->{package},
                version => $provide->{version},
            };
        }
    };
    File::Find::find({wanted => $wanted, no_chdir => 1}, $base);
    my @line;
    for my $p (sort { $a->{package} cmp $b->{package} } @collect) {
        push @line, sprintf "%-36s %-8s %s\n", $p->{package}, $p->{version}, $p->{path};
    }
    join '', @line;
}

sub write_index {
    my ($self, %option) = @_;
    my $file = $self->base("modules", "02packages.details.txt");
    my $dir  = File::Basename::dirname($file);
    File::Path::mkpath($dir) unless -d $dir;
    open my $fh, ">", "$file.tmp" or die "Couldn't open $file: $!";
    printf {$fh} "Written-By: %s %s\n\n", ref $self, $self->VERSION;
    print {$fh} $self->index;
    close $fh;
    if ($option{compress}) {
        my ($ok, $error) = $self->_system("gzip --stdout --no-name $file.tmp > $file.gz");
        if ($ok) {
            unlink "$file.tmp";
            return "$file.gz";
        } else {
            unlink $_ for "$file.tmp", "$file.gz";
            return;
        }
    } else {
        rename "$file.tmp", $file or die "Couldn't rename $file.tmp to $file: $!";
        return $file;
    }
}


1;
__END__

=encoding utf-8

=head1 NAME

CPAN::Mirror::Tiny - create partial CPAN mirror (aka DarkPAN)

=head1 SYNOPSIS

  use CPAN::Mirror::Tiny;

  my $cpan = CPAN::Mirror::Tiny->new("./repository");

  $cpan->inject("https://cpan.metacpan.org/authors/id/S/SK/SKAJI/App-cpm-0.112.tar.gz");
  $cpan->inject("https://github.com/shoichikaji/Carl.git");
  $cpan->write_index(compress => 1);

  # $ find repository -type f
  # repository/authors/id/V/VE/VENDOR/App-cpm-0.112.tar.gz
  # repository/authors/id/V/VE/VENDOR/Carl-ff194fe.tar.gz
  # repository/modules/02packages.details.txt.gz

=head1 DESCRIPTION

CPAN::Mirror::Tiny helps you create partial CPAN mirror (also known as DarkPAN).

=head1 WHY NEW?

Yes, we already have great CPAN modules which create CPAN mirror.

L<CPAN::Mini>, L<OrePAN2>, L<WorePAN> ...

I want to use such modules in CPAN clients.
Actually I used OrePAN2 in L<Carl|https://github.com/shoichikaji/Carl>,
which can install modules in github.com or any servers.

Then minimal dependency and no dependency on XS modules is critical.
Unfortunately existing CPAN mirorr modules depend on XS modules.

That is why I made CPAN::Mirror::Tiny.

=head1 COPYRIGHT AND LICENSE

Copyright 2015 Shoichi Kaji <skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
