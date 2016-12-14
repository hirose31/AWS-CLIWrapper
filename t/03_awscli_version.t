use strict;
use Test::More;

use AWS::CLIWrapper;

my $cli_wrapper = AWS::CLIWrapper->new;
ok($cli_wrapper->awscli_version >= 0);
if ($cli_wrapper->awscli_version > 0) {
    ok($cli_wrapper->awscli_version > 0.001);
}

done_testing;
