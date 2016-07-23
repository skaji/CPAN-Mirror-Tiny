package CPAN::Mirror::Tiny;
use 5.008001;
use strict;
use warnings;

our $VERSION = '0.03';

use CPAN::Meta;
use CPAN::Mirror::Tiny::Archive;
use CPAN::Mirror::Tiny::Tempdir;
use Capture::Tiny ();
use Cwd ();
use File::Basename ();
use File::Copy ();
use File::Path ();
use File::Spec;
use File::Temp ();
use HTTP::Tinyish;
use Parse::LocalDistribution;
use Digest::MD5 ();
use JSON ();

sub new {
    my ($class, %option) = @_;
    my $base  = $option{base} or die "Missing base directory argument";
    my $tempdir = $option{tempdir} || File::Temp::tempdir(CLEANUP => 1);
    File::Path::mkpath($base) unless -d $base;
    $base = Cwd::abs_path($base);
    my $archive = CPAN::Mirror::Tiny::Archive->new;
    my $http = HTTP::Tinyish->new;
    bless {
        base => $base,
        archive => $archive,
        http => $http,
        tempdir => $tempdir,
    }, $class;
}

sub archive { shift->{archive} }
sub http { shift->{http} }

sub extract {
    my ($self, $path) = @_;
    my $method = $path =~ /\.zip$/ ? "unzip" : "untar";
    $self->archive->$method($path);
}

sub base {
    my $self = shift;
    return $self->{base} unless @_;
    File::Spec->catdir($self->{base}, @_);
}

sub tempdir { CPAN::Mirror::Tiny::Tempdir->new(shift->{tempdir}) }
sub pushd_tempdir { CPAN::Mirror::Tiny::Tempdir->pushd(shift->{tempdir}) }

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
    if ($url =~ /(?:^git:|\.git(?:@(.+))?$)/) {
        $self->inject_git($url, { %{$option || +{}}, $1 ? (ref => $1) :() });
    } elsif ($url =~ /^https?:/) {
        $self->inject_http($url, $option);
    } else {
        $url =~ s{^file://}{};
        $self->inject_local($url, $option);
    }
}

sub inject_local {
    my ($self, $file, $option) = @_;
    die "'$file' is not a file" unless -f $file;
    die "'$file' must be tarball or zipball" if $file !~ /(?:\.tgz|\.tar\.gz|\.tar\.bz2|\.zip)$/;
    my $author = ($option ||= {})->{author} || "VENDOR";
    my $tempdir = $self->tempdir;
    my $copy = File::Spec->catfile($tempdir, File::Basename::basename($file));
    File::Copy::copy($file, $copy) or die "Failed to copy $file: $!";
    $self->_locate_tarball($copy, $author);
}

sub inject_http {
    my ($self, $url, $option) = @_;
    if ($url !~ /(?:\.tgz|\.tar\.gz|\.tar\.bz2|\.zip)$/) {
        die "URL must be tarball or zipball\n";
    }
    my $basename = File::Basename::basename($url);
    my $tempdir = $self->tempdir;
    my $file = "$tempdir/$basename";
    my $res = $self->http->mirror($url => $file);
    if ($res->{success}) {
        my $author = ($option ||= {})->{author} || "VENDOR";
        return $self->_locate_tarball($file, $author);
    } else {
        die "Couldn't get $url: $res->{status} $res->{reason}";
    }
}

sub inject_git {
    my ($self, $url, $option) = @_;
    my $ref = ($option ||= {})->{ref};
    my $guard = $self->pushd_tempdir;
    my ($ok, $error) = $self->_system("git", "clone", $url, ".");
    die "Couldn't git clone $url: $error" unless $ok;
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
        return $self->inject_local("$distvname.tar.gz", $option);
    } else {
        die "Couldn't archive $url: $error";
    }
}

my $JSON = JSON->new->canonical(1)->utf8(1);

sub _cached {
    my ($self, $path, $sub) = @_;
    my $cache_dir = $self->base("modules", ".cache");
    File::Path::mkpath($cache_dir) unless -d $cache_dir;
    my $cache_file = File::Spec->catfile($cache_dir, Digest::MD5::md5_hex($path) . ".json");

    my $mtime = (stat $path)[9];
    if (-f $cache_file) {
        my $content = do { open my $fh, "<", $cache_file or die; local $/; <$fh> };
        my $cache = $JSON->decode($content);
        if ($cache->{mtime} == $mtime) {
            return $cache->{payload};
        } else {
            unlink $cache_file;
        }
    }
    my $result = $sub->();
    if ($result) {
        open my $fh, ">", $cache_file or die;
        my $content = {mtime => $mtime, path => $path, payload => $result};
        print {$fh} $JSON->encode($content), "\n";
        close $fh;
    }
    $result;
}

sub extract_provides {
    my ($self, $path) = @_;
    $path = Cwd::abs_path($path);
    $self->_cached($path, sub { $self->_extract_provides($path) });
}

sub _extract_provides {
    my ($self, $path) = @_;
    my $gurad = $self->pushd_tempdir;
    my $dir = $self->extract($path) or return;
    my $parser = Parse::LocalDistribution->new({ALLOW_DEV_VERSION => 1});
    my $hash = $parser->parse($dir) || +{};
    [map +{ package => $_, version => $hash->{$_}{version} }, sort keys %$hash];
}

# TODO cache
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
    for my $p (sort { lc $a->{package} cmp lc $b->{package} } @collect) {
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
        my ($ok, $error) = $self->_system("gzip --stdout --no-name $file.tmp > $file.gz.tmp");
        if ($ok) {
            rename "$file.gz.tmp", "$file.gz"
                or die "Couldn't rename $file.gz.tmp to $file.gz: $!";
            unlink "$file.tmp";
            return "$file.gz";
        } else {
            unlink $_ for "$file.tmp", "$file.gz.tmp";
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

=for stopwords DarkPAN OrePAN2 tempdir commitish

=head1 NAME

CPAN::Mirror::Tiny - create partial CPAN mirror (a.k.a. DarkPAN)

=head1 SYNOPSIS

  use CPAN::Mirror::Tiny;

  my $cpan = CPAN::Mirror::Tiny->new(base => "./repository");

  $cpan->inject("https://cpan.metacpan.org/authors/id/S/SK/SKAJI/App-cpm-0.112.tar.gz");
  $cpan->inject("https://github.com/skaji/Carl.git");
  $cpan->write_index(compress => 1);

  # $ find repository -type f
  # repository/authors/id/V/VE/VENDOR/App-cpm-0.112.tar.gz
  # repository/authors/id/V/VE/VENDOR/Carl-ff194fe.tar.gz
  # repository/modules/02packages.details.txt.gz

=head1 DESCRIPTION

CPAN::Mirror::Tiny helps you create partial CPAN mirror (also known as DarkPAN).

=head2 WHY NEW?

Yes, we already have great CPAN modules which create CPAN mirror.

L<CPAN::Mini>, L<OrePAN2>, L<WorePAN> ...

I want to use such modules in CPAN clients.
Actually I used OrePAN2 in L<Carl|https://github.com/skaji/Carl>,
which can install modules in github.com or any servers.

Then minimal dependency and no dependency on XS modules is critical.
Unfortunately existing CPAN mirror modules depend on XS modules.

This is why I made CPAN::Mirror::Tiny.

=head2 METHODS

=head3 C<< my $cpan = CPAN::Mirror::Tiny->new(%option) >>

Constructor. C< %option > may be:

=over 4

=item * base

Base directory for cpan mirror. This is required.

=item * tempdir

Temp directory. Default C<< File::Temp::tempdir(CLEANUP => 1) >>.

=back

=head3 C<< $cpan->inject($source, \%option) >>

Inject C< $source > to our cpan mirror directory. C< $source > is one of

=over 4

=item * local tar.gz path

  $cpan->inject('/path/to/Module.tar.gz', { author => "SKAJI" });

=item * http url of tar.gz

  $cpan->inject('http://example.com/Module.tar.gz', { author => "DUMMY" });

=item * git url (with optional commitish)

  $cpan->inject('git://github.com/skaji/Carl.git@0.114', { author => "SKAJI" });

=back

As seeing from the above examples, you can specify C<author> in C<\%option>.
If you omit C<author>, default C<VENDOR> is used.

=head3 C<< my $index_string = $cpan->index >>

Get the index (a.k.a. 02packages.details.txt) of our cpan mirror.

=head3 C<< $cpan->write_index( compress => bool ) >>

Write the index to C< $base/modules/02packages.details.txt >
or C< base/modules/02packages.details.txt.gz >.

=head1 COPYRIGHT AND LICENSE

Copyright 2016 Shoichi Kaji <skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
