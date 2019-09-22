#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;

use Data::Dumper;
use YAML::PP;
use File::Path qw/ make_path /;
use Getopt::Long;
use FindBin '$Bin';

GetOptions(
    'help|h' => \my $help,
);

if ($help) {
    usage();
    exit;
}

my ($task, $library) = @ARGV;

my $yp = YAML::PP->new( schema => [qw/ JSON Merge /] );
my ($libs) = $yp->load_file("$Bin/../list.yaml");

my $libraries = $libs->{libraries};
my $runtimes = $libs->{runtimes};

if ($task eq 'build') {
    if ($library) {
        my $lib = $libraries->{ $library }
            or die "Library $library not found";
        build($library);
    }
}
elsif ($task eq 'test') {
    if ($library and $libraries->{ $library }) {
        test($library);
    }
    elsif ($library and $runtimes->{ $library }) {
        my $runtime = $library;
        for my $library (sort keys %$libraries) {
            my $lib = $libraries->{ $library };
            next unless $lib->{runtime} eq $runtime;
            test($library);
        }
    }
    else {
        for my $library (sort keys %$libraries) {
            test($library);
        }
    }
}
elsif ($task eq 'fetch-sources') {
    if ($library) {
        source($library);
    }
    else {
        for my $library (sort keys %$libraries) {
            source($library);
        }
    }
}

sub build {
    my ($library) = @_;
    say "Building $library";
    source($library);
    my $lib = $libraries->{ $library }
        or die "Library $library not found";
    my $buildscript = $lib->{'build-script'}
        or die "No build-script for $library";
    my $source = $lib->{'source'}
        or die "No source for $library";
    my ($filename) = $source =~ m{.*/(.*)\z};
    my $version = $lib->{'version'}
        or die "No version for $library";
    my $runtime = $lib->{'runtime'}
        or die "No runtime for $library";
    my $build_image = "builder-" . ($lib->{'build-image'} || $runtime);

    my $dir = "$Bin/../docker/$runtime";
    mkdir "$dir/build";

    my $cmd = sprintf
        'docker run -it --rm --user %s -v%s/build:/build'
        . ' -v%s/utils:/buildutils -v%s/sources:/sources'
        . ' --env=VERSION --env=SOURCE yamlrun/%s /buildutils/%s',
        $<, $dir, $dir, $dir, $build_image, $buildscript;

    warn __PACKAGE__.':'.__LINE__.": $cmd\n";
    {
        local $ENV{SOURCE} = "/sources/$filename";
        local $ENV{VERSION} = $version;
        chdir "$Bin/../docker/$runtime";
        system $cmd;
    }
}

sub test {
    my ($library) = @_;
    say "====================\nTesting $library";
    my $lib = $libraries->{ $library }
        or die "Library $library not found";
    my $runtime = $lib->{'runtime'}
        or die "No runtime for $library";
    my $tests = $lib->{tests} || [];
    for my $type (@$tests) {
        say "Testing $type";
        my $output;
        my $input;
        if ($type eq 'event') {
            $input = 'input.yaml';
            $output = 'output.event';
        }
        elsif ($type eq 'json') {
            $input = 'input.yaml';
            $output = 'output.json';
        }
        my $cmd = sprintf
          'docker run -i --rm --user %s yamlrun/runtime-%s /yaml/%s-%s <tests/%s >tests/%s.%s',
            $<, $runtime, $library, $type, $input, $library, $type;
        warn __PACKAGE__.':'.__LINE__.": $cmd\n";
        system $cmd;
        if ($type eq 'json') {
            system "jq <tests/$library.$type >tests/$library.$type.jq && mv tests/$library.$type.jq tests/$library.$type";
        }
        system "diff tests/$output tests/$library.$type";
        my $rc = $?;
        unlink "tests/$library.$type";
        if ($rc) {
            say "Test failed";
            exit 1;
        }
        else {
            say "Test passed";
        }
    }
}

sub source {
    my ($library) = @_;
    say $library;
    my $lib = $libraries->{ $library }
        or die "Library $library not found";
    my $runtime = $lib->{runtime}
        or die "No runtime for $library";
    my $source = $lib->{source}
        or die "No source for $library";
    my ($filename) = $source =~ m{.*/(.*)\z};
    my $srcdir = "$Bin/../docker/$runtime/sources";
    make_path $srcdir;
    chdir $srcdir;
    if (-e $filename) {
        say "$filename exists, skip";
    }
    else {
        my $cmd = "wget --no-verbose --timestamping $source";
        say $cmd;
        system $cmd;
    }
}

sub usage {
    say <<"EOM";
Usage:
    $0 build
    $0 build c-libyaml
    $0 test
    $0 test c-libyaml
    $0 test static
    $0 fetch-sources
    $0 fetch-sources c-libyaml
EOM
}
