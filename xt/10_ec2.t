# -*- mode: cperl -*-
use strict;
use Test::More;

use AWS::CLIWrapper;

my $aws = AWS::CLIWrapper->new;
my $res;

$res = $aws->ec2('describe-instances');
ok($res, 'describe-instances all');

my $test_instance_count = 3;
my @instance_ids;
INSTANCE: for my $rs ( @{ $res->{Reservations} }) {
    for my $is (@{ $rs->{Instances} }) {
        push @instance_ids, $is->{InstanceId};
        last INSTANCE if scalar(@instance_ids) >= $test_instance_count;
    }
}

$res = $aws->ec2('describe-instances', { instance_ids => \@instance_ids });
my $got_instance_count = 0;
for my $rs ( @{ $res->{Reservations} }) {
    for my $is (@{ $rs->{Instances} }) {
        $got_instance_count++ if $is->{InstanceId};
    }
}
is($got_instance_count, $test_instance_count, 'describe-instances by instance_ids');

done_testing;
