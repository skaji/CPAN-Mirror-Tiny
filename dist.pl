use v5.42;

package Trial {
    use Moose;
    with 'Dist::Zilla::Role::FileMunger';
    sub munge_file ($self, $file) {
        return if !($ENV{DZIL_RELEASING} && $file->name eq $self->zilla->main_module->name);
        my @line;
        for my $line (split /\n/, $file->content, -1) {
            if ($line =~ /^our \$TRIAL/) {
                my $trial_line = sprintf 'our $TRIAL = %d;', $self->zilla->is_trial ? 1 : 0;
                push @line, $trial_line;
            } else {
                push @line, $line;
            }
        }
        $file->content(join "\n", @line);
    }
}

package VersionFromMainModule {
    use Moose;
    with 'Dist::Zilla::Role::VersionProvider', 'Dist::Zilla::Role::ModuleMetadata';
    sub provide_version ($self, @) {
        my $metadata = $self->module_metadata_for_file($self->zilla->main_module, collect_pod => 0);
        my $version = $metadata->version;
        "$version";
    }
}

package NextRelease {
    use Moose;
    extends 'Dist::Zilla::Plugin::NextRelease';
    sub after_release ($self, @) {} # noop
}

my @prereq = (
    [ Prereqs => 'ConfigureRequires' ] => [
        'Module::Build::Tiny' => '0.053',
    ],
    [ Prereqs => 'RuntimeRequires' ] => [
        'CPAN::Meta' => '0',
        'File::Copy::Recursive' => '0',
        'File::Which' => '0',
        'File::pushd' => '0',
        'HTTP::Tinyish' => '0',
        'IPC::Run3' => '0',
        'JSON' => '0',
        'Parse::LocalDistribution' => '0',
        'Parse::PMFile' => '0',
        'Pod::Usage' => '1.33',
        'perl' => 'v5.24',
    ],
    [ Prereqs => 'RuntimeRecommends' ] => [
        'Plack' => '0',
    ],
    [ Prereqs => 'DevelopRequires' ] => [
        'Test::More' => '0.98',
    ],
);

my @plugin = (
    'ExecDir' => [ dir => 'script' ],
    'Git::GatherDir' => [ exclude_filename => 'META.json' ],
    'CopyFilesFromBuild' => [ copy => 'META.json', copy => 'Changes' ],
    '=VersionFromMainModule' => [],
    'ReversionOnRelease' => [],
    '=NextRelease' => [ format => '%v  %{yyyy-MM-dd}d%{ (TRIAL RELEASE)}T' ],
    '=Trial' => [],
    'Git::Check' => [ allow_dirty => 'Changes', allow_dirty => 'META.json' ],
    'GithubMeta' => [ issues => 1 ],
    'ReadmeAnyFromPod' => [ type => 'markdown', filename => 'README.md', location => 'root' ],
    'MetaProvides::Package' => [ inherit_version => 0, inherit_missing => 0 ],
    'MetaJSON' => [],
    'Metadata' => [ x_static_install => 1 ],
    'Git::Contributors' => [],

    'CheckChangesHasContent' => [],
    'FakeRelease' => [],
    'CopyFilesFromRelease' => [ match => '\.pm$' ],
    'Git::Commit' => [ commit_msg => '%v%t', allow_dirty => 'Changes', allow_dirty => 'META.json', allow_dirty_match => '\.pm$' ],
    'Git::Tag' => [ tag_format => '%v%t', tag_message => '%v%t' ],
    'Git::Push' => [],
);

my @config = (
    name => 'CPAN-Mirror-Tiny',
    [ @prereq, @plugin ],
);
