# -*- mode: cperl -*-
use strict;
use Test::More;

use AWS::CLIWrapper;

my $aws = AWS::CLIWrapper->new;
my $res;

subtest 'Uppercase key, values, name' => sub {
    # >= 0.14.0 : Key, Values, Name
    # <= 0.13.2 : key, values, name, also accept Key, Values, Name
    $res = $aws->ec2('describe-instances', {
        filters => [{ name => 'tag:Name', values => ["AC-TEST-*"] }],
    });
    ok($res);
};

done_testing;
