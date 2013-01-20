# -*- mode: cperl; -*-
use Test::Dependencies
    exclude => [qw(Test::Dependencies Test::Base Test::Perl::Critic
                   AWS::CLIWrapper)],
    style   => 'light';
ok_dependencies();
