package CPAN::Mirror::Tiny;
use 5.008001;
use strict;
use warnings;

our $VERSION = '0.05';

use CPAN::Meta;
use CPAN::Mirror::Tiny::Archive;
use CPAN::Mirror::Tiny::Tempdir;
use Capture::Tiny ();
use Cwd ();
use File::Basename ();
use File::Copy ();
use File::Path ();
use File::Spec;
use File::Spec::Unix;
use File::Temp ();
use HTTP::Tinyish;
use Parse::LocalDistribution;
use Parse::PMFile;
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
        $self->inject_git($url, $option);
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
    if ($url =~ /(.*)\@(.*)$/) {
        # take care of git@github.com:skaji/repo@tag, http://user:pass@example.com/foo@tag
        my $remove = $2;
        $ref ||= $remove;
        $url =~ s/\@$remove$//;
    }

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
    my $distvname = sprintf "%s-%s-%s", $meta->name, $meta->version, $rev;
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
        if ($cache->{mtime} == $mtime and (ref $cache->{payload} eq 'HASH')) {
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
    $parser->parse($dir) || +{};
}

sub index {
    my $self = shift;
    my $base = $self->base("authors/id");
    return unless -d $base;
    my %packages;
    my $wanted = sub {
        return unless -f;
        return unless /(?:\.tgz|\.tar\.gz|\.tar\.bz2|\.zip)$/;
        my $path = $_;
        my $mtime = (stat $path)[9];
        my $provides = $self->extract_provides($path);
        my $relative = File::Spec::Unix->abs2rel($path, $base);
        $self->_update_packages(\%packages, $provides, $relative, $mtime);
    };
    File::Find::find({wanted => $wanted, no_chdir => 1}, $base);

    my @line;
    for my $package (sort { lc $a cmp lc $b } keys %packages) {
        my $path    = $packages{$package}[1];
        my $version = $packages{$package}[0];
        $version = 'undef' unless defined $version;
        push @line, sprintf "%-36s %-8s %s\n", $package, $version, $path;
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

# Copy from WorePAN: https://github.com/charsbar/worepan/blob/master/lib/WorePAN.pm
# Copyright (C) 2012 by Kenichi Ishigaki.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
sub _update_packages {
  my ($self, $packages, $info, $path, $mtime) = @_;

  for my $module (sort keys %$info) {
    next unless exists $info->{$module}{version};
    my $new_version = $info->{$module}{version};
    if (!$packages->{$module}) { # shortcut
      $packages->{$module} = [$new_version, $path, $mtime];
      next;
    }
    my $ok = 0;
    my $cur_version = $packages->{$module}[0];
    if (Parse::PMFile->_vgt($new_version, $cur_version)) {
      $ok++;
    }
    elsif (Parse::PMFile->_vgt($cur_version, $new_version)) {
      # lower VERSION number
    }
    else {
      if (
        $new_version eq 'undef' or $new_version == 0 or
        Parse::PMFile->_vcmp($new_version, $cur_version) == 0
      ) {
        if ($mtime >= $packages->{$module}[2]) {
          $ok++; # dist is newer
        }
      }
    }
    if ($ok) {
      $packages->{$module} = [$new_version, $path, $mtime];
    }
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
  # repository/authors/id/V/VE/VENDOR/Carl-0.01-ff194fe.tar.gz
  # repository/modules/02packages.details.txt.gz

=head1 DESCRIPTION

CPAN::Mirror::Tiny helps you create partial CPAN mirror (also known as DarkPAN).

=head1 WHY NEW?

Yes, we already have great CPAN modules which create CPAN mirror.

L<CPAN::Mini>, L<OrePAN2>, L<WorePAN> ...

I want to use such modules in CPAN clients.
Actually I used OrePAN2 in L<Carl|https://github.com/skaji/Carl>,
which can install modules in github.com or any servers.

Then minimal dependency and no dependency on XS modules is critical.
Unfortunately existing CPAN mirror modules depend on XS modules.

This is why I made CPAN::Mirror::Tiny.

=head1 METHODS

=head2 new

  my $cpan = CPAN::Mirror::Tiny->new(%option)

Constructor. C< %option > may be:

=over 4

=item * base

Base directory for cpan mirror. This is required.

=item * tempdir

Temp directory. Default C<< File::Temp::tempdir(CLEANUP => 1) >>.

=back

=head2 inject

  $cpan->inject($source, \%option)

Inject C< $source > to our cpan mirror directory. C< $source > is one of

=over 4

=item * local tar.gz path

  $cpan->inject('/path/to/Module.tar.gz', { author => "SKAJI" });

=item * http url of tar.gz

  $cpan->inject('http://example.com/Module.tar.gz', { author => "DUMMY" });

=item * git url (with optional ref)

  $cpan->inject('git://github.com/skaji/Carl.git', { author => "SKAJI", ref => '0.114' });

=back

As seeing from the above examples, you can specify C<author> in C<\%option>.
If you omit C<author>, default C<VENDOR> is used.

B<CAUTION>: Currently, the distribution name for git repository is somthing like
C<S/SK/SKAJI/Carl-0.01-9188c0e.tar.gz>,
where C<0.01> is the version and C<9188c0e> is C<git rev-parse --short HEAD>.
However this naming convention is likely to change. Do not depend on this!

=head2 index

  my $index_string = $cpan->index

Get the index (a.k.a. 02packages.details.txt) of our cpan mirror.

=head2 write_index

  $cpan->write_index( compress => bool )

Write the index to C< $base/modules/02packages.details.txt >
or C< base/modules/02packages.details.txt.gz >.

=head1 TIPS

=head2 How can I install modules in my DarkPAN with cpanm?

L<cpanm> is an awesome CPAN clients. If you want to install modules
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
but also fetching modules to L<CPAN::Common::Index>-like objects entirely.
Then we can hack cpanm easily.

I believe that cpanm 2.0 also known as L<Menlo> comes with such features!

=head1 COPYRIGHT AND LICENSE

Copyright 2016 Shoichi Kaji <skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
