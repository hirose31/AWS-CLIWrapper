use strict;
use Test::More;

use AWS::CLIWrapper;

{
  local $ENV{AWS_CLIWRAPPER_TIMEOUT} = undef;

  my $aws = AWS::CLIWrapper->new();

  is $aws->{timeout}, 30, "default timeout is 30 seconds";
}

{
  local $ENV{AWS_CLIWRAPPER_TIMEOUT} = 3600;

  my $aws = AWS::CLIWrapper->new();

  is $aws->{timeout}, 3600, "timeout set via env variable";
}

done_testing;
