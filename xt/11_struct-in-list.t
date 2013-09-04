# -*- mode: cperl -*-
use strict;
use Test::More;

use AWS::CLIWrapper;

my $aws = AWS::CLIWrapper->new;
my $res;

$res = $aws->ec2('describe-instances', {
    'filters' => [{ Name => 'tag:Name', Values => ["AC-TEST-*"] }],
   });
ok($res, 'structure in list');

done_testing;
