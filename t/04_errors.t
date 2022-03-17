use strict;
use Test::More tests => 4;

use AWS::CLIWrapper;

# Default error handling
my $aws = AWS::CLIWrapper->new;

my $res = $aws->elbv2();

is $res, undef, "default result is undefined";

# Is this a TODO?
is $AWS::CLIWrapper::Error->{Code}, "Unknown", "default error code match";

my $want_err_msg = qr!exited with code \[\d+\]
stderr:
.*

usage: aws \[options\] <command> <subcommand> \[<subcommand> ...\] \[parameters\]
To see help text, you can run:

  aws help
  aws <command> help
  aws <command> <subcommand> help
!;

like $AWS::CLIWrapper::Error->{Message}, $want_err_msg, "default error message match";

# Croaking
my $aws_croak = AWS::CLIWrapper->new(croak_on_error => 1);

eval {
    $aws_croak->elbv2();
};


like $@, $want_err_msg, "croak on error message match";
