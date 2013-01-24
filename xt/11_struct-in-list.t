# -*- mode: cperl -*-
use strict;
use Test::More;

use AWS::CLIWrapper;

my $aws = AWS::CLIWrapper->new;
my $res;

$res = $aws->ec2('describe-instances', {
    'filters' => [{ name => 'tag:Name', values => ["w*"] }],
   });
ok($res, 'structure in list');

done_testing;
