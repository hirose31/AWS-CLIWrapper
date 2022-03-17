# -*- mode: cperl -*-
use strict;
use Test::More;

use AWS::CLIWrapper;

my $AMI_ID = 'ami-0cc905e12087478be'; # Ubuntu 18.04

my $aws = AWS::CLIWrapper->new;
my $res;
my $err;

$res = $aws->ec2('run-instances', {
    count              => 1,
    image_id           => $AMI_ID,
    instance_type      => 't2.micro',
    key_name           => 'hirose31-aws-tokyo',
    network_interfaces => [
        {
            DeviceIndex              => 0,
            SubnetId                 => 'subnet-00c69dad8729ad024',
            PrivateIpAddress         => "10.0.0.240",
            Groups                   => [ 'sg-0ec4572b2c015784c' ],
            AssociatePublicIpAddress => JSON::true, # not $AWS::CLIWrapper::true,
        },
    ],
})
    or die sprintf("Code : %s\nMessage: %s",
                    $AWS::CLIWrapper::Error->{Code},
                    $AWS::CLIWrapper::Error->{Message},
                );
ok($res, 'run-instances');
my $instance_id = $res->{Instances}[0]{InstanceId};
ok($instance_id, 'getting instance id');

$res = $aws->ec2('terminate-instances', {
    instance_ids => [$instance_id],
})
    or die sprintf("Code : %s\nMessage: %s",
                    $AWS::CLIWrapper::Error->{Code},
                    $AWS::CLIWrapper::Error->{Message},
                );
ok($res, 'terminate-instances');

done_testing;
