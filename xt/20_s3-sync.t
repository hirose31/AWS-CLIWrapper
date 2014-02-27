# -*- mode: cperl -*-
use strict;
use Test::More;

use File::Temp qw(tempdir);
use File::Glob qw(:glob); # for globbing pattern contains whitespace
use AWS::CLIWrapper;

my $aws = AWS::CLIWrapper->new;
my $cleanup = 0;

{
    my $tmpdir = tempdir( CLEANUP => $cleanup );
    test_sync("normal",
              's3://aws-cliwrapper-test' => $tmpdir);
}

{
    my $tmpdir = tempdir( CLEANUP => $cleanup );
    test_sync("source file contains space",
              's3://aws-cliwrapper-test/file-space' => $tmpdir);
}
{
    my $tmpdir = tempdir("s3-sync-sfs XXXXXX",
                         CLEANUP => $cleanup,
                         TMPDIR  => 1,
                     );
    test_sync("source file contains space and dest dir contains space",
              's3://aws-cliwrapper-test/file-space' => $tmpdir);
}

{
    my $tmpdir = tempdir( CLEANUP => $cleanup );
    test_sync("source dir contains space",
              's3://aws-cliwrapper-test/dir space' => $tmpdir);
}
{
    my $tmpdir = tempdir("s3-sync-sds XXXXXX",
                         CLEANUP => $cleanup,
                         TMPDIR  => 1,
                     );
    test_sync("source dir contains space and dest dir contains space",
              's3://aws-cliwrapper-test/dir space' => $tmpdir);
}

{
    my $tmpdir = tempdir("XXXXXXXX",
                         CLEANUP => $cleanup,
                         TMPDIR  => 1,
                     );
    test_sync("source dir contains single quote",
              "s3://aws-cliwrapper-test/dir'single" => $tmpdir);
}
{
    my $tmpdir = tempdir("s3-sync-dfq'XXXXXX",
                          CLEANUP => $cleanup,
                          TMPDIR  => 1,
                      );
    test_sync("both source and dest dirs contains single quote",
              "s3://aws-cliwrapper-test/dir'single" => $tmpdir);
}

{
    my $tmpdir = tempdir('XXXXXXXX',
                          CLEANUP => $cleanup,
                          TMPDIR  => 1,
                      );
    test_sync("source dir contains double quote",
              's3://aws-cliwrapper-test/dir"double' => $tmpdir);
}
{
    my $tmpdir = tempdir('s3-sync-dfdq"XXXXXX',
                          CLEANUP => $cleanup,
                          TMPDIR  => 1,
                      );
    test_sync("both source and dest dirs contains double quote",
              's3://aws-cliwrapper-test/dir"double' => $tmpdir);
}

done_testing;

sub test_sync {
    my($desc, $src, $dst) = @_;

    my $res = $aws->s3('sync', [$src => $dst],
                       {
                           'delete' => $AWS::CLIWrapper::true,
                       });
    ok($res, "$desc: $src => $dst");

    my @downloaded = bsd_glob("$dst/*");
    my $nd = scalar @downloaded;
    ok($nd > 0, "downloaded $nd");
}

