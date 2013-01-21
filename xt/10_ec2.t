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
INSTANCE: for my $rs ( @{ $res->{reservationSet} }) {
    for my $is (@{ $rs->{instancesSet} }) {
        push @instance_ids, $is->{instanceId};
        last INSTANCE if scalar(@instance_ids) >= $test_instance_count;
    }
}

$res = $aws->ec2('describe-instances', { instance_ids => \@instance_ids });
my $got_instance_count = 0;
for my $rs ( @{ $res->{reservationSet} }) {
    for my $is (@{ $rs->{instancesSet} }) {
        $got_instance_count++ if $is->{instanceId};
    }
}
is($got_instance_count, $test_instance_count, 'describe-instances by instance_ids');

done_testing;
