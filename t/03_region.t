use strict;
use warnings;

use Test::More;

use AWS::CLIWrapper;

my $cli = AWS::CLIWrapper->new(
  region => 'us-west-1',
);

is $cli->region, 'us-west-1', "region ok";

done_testing;
