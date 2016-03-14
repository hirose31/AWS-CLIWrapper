use strict;
use warnings;

use 5.008001;

use ExtUtils::MakeMaker 6.30;

my %WriteMakefileArgs = (
    "ABSTRACT_FROM" => "lib/AWS/CLIWrapper.pm",
    "AUTHOR" => "HIROSE Masaaki",
    "BUILD_REQUIRES" => {},
    "CONFIGURE_REQUIRES" => {
        "ExtUtils::MakeMaker" => "6.30"
    },
    "DISTNAME" => "AWS-CLIWrapper",
    "LICENSE" => "perl",
    "NAME" => "AWS::CLIWrapper",
    "PREREQ_PM" => {
        "IPC::Cmd"   => 0,
        "String::ShellQuote" => 0,
        "JSON::MaybeXS" => 0,
        "version"    => "0.77",
    },
    "TEST_REQUIRES" => {
        "Test::More" => 0
    },
    "VERSION_FROM" => "lib/AWS/CLIWrapper.pm",
    "MIN_PERL_VERSION" => 5.008001,
    "META_MERGE" => {
        'meta-spec' => { version => 2 },
        resources => {
            repository  => {
                type => 'git',
                web  => 'https://github.com/hirose31/AWS-CLIWrapper',
                url  => 'https://github.com/hirose31/AWS-CLIWrapper.git',
            },
        },
    },
    "test" => {
        "TESTS" => "t/*.t"
    }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
    my $tr = delete $WriteMakefileArgs{TEST_REQUIRES};
    my $br = $WriteMakefileArgs{BUILD_REQUIRES};
    for my $mod ( keys %$tr ) {
        if ( exists $br->{$mod} ) {
            $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
        } else {
            $br->{$mod} = $tr->{$mod};
        }
    }
}

unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
    my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
    my $pp = $WriteMakefileArgs{PREREQ_PM};
    for my $mod ( keys %$br ) {
        if ( exists $pp->{$mod} ) {
            $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
        } else {
            $pp->{$mod} = $br->{$mod};
        }
    }
}

delete $WriteMakefileArgs{META_MERGE}
    unless eval { ExtUtils::MakeMaker->VERSION(6.48) };

delete $WriteMakefileArgs{MIN_PERL_VERSION}
    unless eval { ExtUtils::MakeMaker->VERSION(6.48) };

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
    unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);
