# -*- mode: cperl -*-
use strict;
use Test::More;

use AWS::CLIWrapper;

my $aws = AWS::CLIWrapper->new;
my $res;

# >= 0.14.0 : Key, Values, Name
# <  0.14.0 : key, values, name, also accept Key, Values, Name
subtest 'Uppercase key, values, name' => sub {
    $res = $aws->ec2('describe-instances', {
        filters => [{ name => 'tag:Name', values => ["AC-TEST-*"] }],
    });
    ok($res);
};

# >= 0.14.0 : --count N or --count MIN:MAX
# <  0.14.0 : --min-count N and --max-count N
subtest 'ec2 run-instances: --min-count, --max-count VS --count' => sub {
    # >= 0.14.0 : fail case
    $res = $aws->ec2('run-instances', {
        image_id  => '1',
        min_count => 1,
        max_count => 1,
    });

    ok(!$res); # should fail
    unlike($AWS::CLIWrapper::Error->{Message}, qr/Unknown options:/);

    # <  0.14.0 : fail case
    $res = $aws->ec2('run-instances', {
        image_id => '1',
        count    => 1,
    });

    ok(!$res); # should fail
    unlike($AWS::CLIWrapper::Error->{Message}, qr/--(?:min|max)-count is required/);
};

# >= 0.15.0 : s3 and s3api (formerly s3)
# <  0.15.0 : s3 only
subtest 's3 and s3api' => sub {
    # >= 0.15.0
    $res = $aws->s3api('list-buckets');
    ok($res, 's3api list-buckets');

    $res = $aws->s3('list-buckets');
    ok($res, 's3 list-buckets');

    $res = $aws->s3('ls');
    if (AWS::CLIWrapper->awscli_version >= 0.15.0) {
        ok($res, 's3 ls >= 0.15.0');
    } else {
        like($AWS::CLIWrapper::Error->{Message}, qr/invalid choice: 'ls'/, 's3 ls < 0.15.0');
    }
};

done_testing;
