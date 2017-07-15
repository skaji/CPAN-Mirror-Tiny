package CPAN::Mirror::Tiny::Archive;
use strict;
use warnings;

use File::Which 'which';
use constant BAD_TAR => ($^O eq 'solaris' || $^O eq 'hpux');
use constant WIN32 => $^O eq 'MSWin32';

use File::pushd ();
use File::Basename ();

if (WIN32) {
    require Win32::ShellQuote;
    *shell_quote = \&Win32::ShellQuote::quote_native;
} else {
    require String::ShellQuote;
    *shell_quote = \&String::ShellQuote::shell_quote_best_effort;
}
sub safe_string {
    join ' ', map { ref $_ ? shell_quote(@$_) : $_ } @_;
}
sub safe_system {
    if (!WIN32 && @_ == 1 && ref $_[0]) {
        system { $_[0][0] } @{$_[0]};
    } else {
        my $cmd = safe_string @_;
        system $cmd;
    }
}
sub safe_capture {
    my $cmd = safe_string @_;
    `$cmd`;
}


sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->_init;
    $self;
}

sub untar { shift->{_backends}{untar}->(@_) }
sub unzip { shift->{_backends}{unzip}->(@_) }

sub _init {
    my $self = shift;
    my $tar = which('tar');
    my $tar_ver;
    my $maybe_bad_tar = sub { WIN32 || BAD_TAR
        || (($tar_ver = safe_capture([$tar, "--version"], "2>/dev/null")) =~ /GNU.*1\.13/i) };

    if ($tar && !$maybe_bad_tar->()) {
        chomp $tar_ver;
        # https://github.com/miyagawa/cpanminus/pull/508
        my @nowarn = $tar_ver =~ /GNU\D+(\d+\.\d+)/ && $1 >= 1.23
            ? qw(--warning=no-unknown-keyword) : ();
        $self->{_backends}{untar} = sub {
            my($self, $tarfile) = @_;

            my $xf = ($self->{verbose} ? 'v' : '')."xf";
            my $ar = $tarfile =~ /bz2$/ ? 'j' : 'z';

            my($root, @others) = safe_capture([$tar, @nowarn, "-${ar}tf", $tarfile])
                or return undef;

            FILE: {
                chomp $root;
                $root =~ s!^\./!!;
                $root =~ s{^(.+?)/.*$}{$1};

                if (!length($root)) {
                    # archive had ./ as the first entry, so try again
                    $root = shift(@others);
                    redo FILE if $root;
                }
            }

            safe_system([$tar, @nowarn, "-$ar$xf", $tarfile]);
            return $root if -d $root;
            return undef;
        };
    } elsif (    $tar
             and my $gzip = which('gzip')
             and my $bzip2 = which('bzip2')) {
        $self->{_backends}{untar} = sub {
            my($self, $tarfile) = @_;

            my $x  = "x" . ($self->{verbose} ? 'v' : '') . "f";
            my $ar = $tarfile =~ /bz2$/ ? $bzip2 : $gzip;

            my($root, @others) = safe_capture([$ar, "-dc", $tarfile], "|", [$tar, "tf", "-"])
                or return undef;

            FILE: {
                chomp $root;
                $root =~ s!^\./!!;
                $root =~ s{^(.+?)/.*$}{$1};

                if (!length($root)) {
                    # archive had ./ as the first entry, so try again
                    $root = shift(@others);
                    redo FILE if $root;
                }
            }

            safe_system([$ar, "-dc", $tarfile], "|", [$tar, $x, "-"]);
            return $root if -d $root;
            return undef;
        };
    } elsif (eval { require Archive::Tar }) { # uses too much memory!
        $self->{_backends}{untar} = sub {
            my $self = shift;
            my $t = Archive::Tar->new($_[0]);
            my($root, @others) = $t->list_files;
            FILE: {
                $root =~ s!^\./!!;
                $root =~ s{^(.+?)/.*$}{$1};

                if (!length($root)) {
                    # archive had ./ as the first entry, so try again
                    $root = shift(@others);
                    redo FILE if $root;
                }
            }
            $t->extract;
            return -d $root ? $root : undef;
        };
    } else {
        $self->{_backends}{untar} = sub {
            die "Failed to extract $_[1] - You need to have tar or Archive::Tar installed.\n";
        };
    }

    if (my $unzip = which('unzip')) {
        $self->{_backends}{unzip} = sub {
            my($self, $zipfile) = @_;

            my @opt = $self->{verbose} ? () : qw(-q);
            my(undef, $root, @others) = safe_capture([$unzip, "-t", $zipfile])
                or return undef;

            chomp $root;
            $root =~ s{^\s+testing:\s+([^/]+)/.*?\s+OK$}{$1};

            safe_system([$unzip, @opt, $zipfile]);
            return $root if -d $root;

            return undef;
        }
    } else {
        $self->{_backends}{unzip} = sub {
            eval { require Archive::Zip }
                or  die "Failed to extract $_[1] - You need to have unzip or Archive::Zip installed.\n";
            my($self, $file) = @_;
            my $zip = Archive::Zip->new();
            my $status;
            $status = $zip->read($file);
            return if $status != Archive::Zip::AZ_OK();
            my @members = $zip->members();
            for my $member ( @members ) {
                my $af = $member->fileName();
                next if ($af =~ m!^(/|\.\./)!);
                $status = $member->extractToFileNamed( $af );
                return if $status != Archive::Zip::AZ_OK();
            }

            my ($root) = $zip->membersMatching( qr<^[^/]+/$> );
            $root &&= $root->fileName;
            return -d $root ? $root : undef;
        };
    }
}

1;

__END__

=head1 NAME

CPAN::Mirror::Tiny::Archive - untar/unzip archives

=head1 LICENSE

Most of code is copied from L<App::cpanminus>. Its license is:

  Copyright 2010- Tatsuhiko Miyagawa

  This software is licensed under the same terms as Perl.

=cut
