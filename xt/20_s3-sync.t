# -*- mode: cperl -*-
use strict;
use Test::More;

use File::Temp qw(tempdir);
use AWS::CLIWrapper;

my $aws = AWS::CLIWrapper->new;
my $res;

my $tmpdir = tempdir( CLEANUP => 1 );

$res = $aws->s3('sync', ['s3://aws-cliwrapper-test' => $tmpdir],
                {
                    'delete' => $AWS::CLIWrapper::true,
                });
ok($res, 's3 sync s3 to local');

my @downloaded = glob "$tmpdir/*";
my $nd = scalar @downloaded;
ok($nd > 0, "downloaded $nd");

done_testing;
