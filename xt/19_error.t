# -*- mode: cperl -*-
use strict;
use Test::More;

use AWS::CLIWrapper;

my $aws = AWS::CLIWrapper->new;
my $res;
my $err;

### unknown operation
$res = $aws->ec2('unknown-operation');
$err = $AWS::CLIWrapper::Error;
ok(!$res, 'unknown operation');

  is($err->{Code},    'Unknown',                     'err Code');
like($err->{Message}, qr/operation: Invalid choice/i, 'err Message');

### invalid option
$res = $aws->ec2('describe-instances', { invalid_option => 'blah' });
$err = $AWS::CLIWrapper::Error;
ok(!$res, 'invalid option');

  is($err->{Code},    'Unknown',                    'err Code');
like($err->{Message}, qr/(Unknown options:|Something is wrong)/,         'err Message');

### invalid option value
$res = $aws->ec2('describe-instances', { instance_ids => ['blah'] });
$err = $AWS::CLIWrapper::Error;
ok(!$res, 'invalid option value');

  is($err->{Code},    'Unknown', 'err Code');
like($err->{Message}, qr/(Invalid id:|Unknown)/, 'err Message');

### required option
$res = $aws->ec2('run-instances');
$err = $AWS::CLIWrapper::Error;
ok(!$res, 'required option');

  is($err->{Code},    'Unknown',       'err Code');
like($err->{Message}, qr/is required/, 'err Message');


###
done_testing;
