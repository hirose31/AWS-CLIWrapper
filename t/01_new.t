use strict;
use Test::More;

require AWS::CLIWrapper;
note("new");
my $obj = new_ok("AWS::CLIWrapper");

# diag explain $obj

done_testing;
