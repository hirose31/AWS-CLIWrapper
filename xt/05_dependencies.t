# -*- mode: cperl; -*-

use Test::Dependencies
     exclude => [qw(Test::Dependencies Test::Base Test::Perl::Critic
                        AWS::CLIWrapper)],
     style   => 'light';
if ($ENV{RELEASE_TESTING}) {
    ok_dependencies();
} else {
    my $tb = Test::Dependencies->builder;
    $tb->skip_all('Authors tests');
}
