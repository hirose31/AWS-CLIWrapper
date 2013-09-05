use strict;
use Test::More;

use AWS::CLIWrapper;

ok(AWS::CLIWrapper->awscli_version >= 0);
if (AWS::CLIWrapper->awscli_version > 0) {
    ok(AWS::CLIWrapper->awscli_version > 0.1);
}

done_testing;
