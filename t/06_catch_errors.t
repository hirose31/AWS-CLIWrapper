use 5.008001;
use strict;
use warnings;
no warnings 'uninitialized';

use Test::More;
use File::Temp 'tempfile';

use AWS::CLIWrapper;

my %default_wrapper_args = (
  awscli_path => 't/bin/mock-aws',
  nofork => 1,
);

my $tests = eval join "\n", <DATA> or die "$@";

for my $test_name (keys %$tests) {
  next if @ARGV and not grep { $_ eq $test_name } @ARGV;

  my $test = $tests->{$test_name};
  my ($wrapper_args, $env, $command, $subcommand, $cmd_args)
    = @$test{qw(wrapper_args env command subcommand cmd_args)};
  
  $env = {} unless $env;

  my ($tmp_fh, $tmp_name) = tempfile;
  print $tmp_fh $test->{retries} || 1;
  close $tmp_fh;

  local $ENV{AWS_CLIWRAPPER_TEST_ERROR_COUNTER_FILE} = $tmp_name;
  local $ENV{AWS_CLIWRAPPER_TEST_DIE_WITH_ERROR} = $test->{error_to_die_with}
    if $test->{error_to_die_with};
  
  local @ENV{keys %$env} = values %$env;
  
  $AWS::CLIWrapper::Error = { Message => '', Code => '' };

  my $aws = AWS::CLIWrapper->new(%default_wrapper_args, %{$wrapper_args || {}});
  my $res = eval { $aws->$command($subcommand, @{$cmd_args || []}) };

  if ($test->{retries} > 0) {
    open my $fh, "<", $tmp_name;
    my $counter = <$fh>;
    close $fh;

    is $counter, 0, "$test_name retry counter exhausted";
  }

  like "$@", $test->{exception}, "$test_name exception";
  like $AWS::CLIWrapper::Error->{Message}, $test->{error_msg_re},
    "$test_name error message";

  is_deeply $res, $test->{want}, "$test_name result";
}

done_testing;

__DATA__
# line 60
{
  'no-error' => {
    command => 'ecs',
    subcommand => 'list-clusters',
    error_to_die_with => undef,
    error_msg_re => qr{^$},
    exception => qr{^$},
    want => {
      clusterArns => [
        "arn:aws:ecs:us-foo-1:123456789:cluster/foo",
        "arn:aws:ecs:us-foo-1:123456789:cluster/bar",
        "arn:aws:ecs:us-foo-1:123456789:cluster/baz"
      ],
    }
  },
  'no-croak' => {
    command => 'ecs',
    subcommand => 'list-clusters',
    error_to_die_with => 'uh-oh',
    error_msg_re => qr{uh-oh},
    exception => qr{^$},
    want => undef,
  },
  'with-croak' => {
    wrapper_args => { croak_on_error => 1 },
    command => 'ecs',
    subcommand => 'list-clusters',
    error_to_die_with => 'foobaroo!',
    error_msg_re => qr{foobaroo},
    exception => qr{foobaroo},
    want => undef,
  },
  'catch-no-croak' => {
    env => {
      AWS_CLIWRAPPER_CATCH_ERROR_PATTERN => 'FUBAR',
      AWS_CLIWRAPPER_CATCH_ERROR_MIN_DELAY => 0,
      AWS_CLIWRAPPER_CATCH_ERROR_MAX_DELAY => 0,
    },
    command => 'ecs',
    subcommand => 'list-clusters',
    error_to_die_with => 'FUBAR',
    retries => 2,
    error_msg_re => qr{^$},
    exception => qr{^$},
    want => {
      clusterArns => [
        "arn:aws:ecs:us-foo-1:123456789:cluster/foo",
        "arn:aws:ecs:us-foo-1:123456789:cluster/bar",
        "arn:aws:ecs:us-foo-1:123456789:cluster/baz"
      ],
    }
  },
  'catch-with-croak' => {
    env => {
      AWS_CLIWRAPPER_CATCH_ERROR_PATTERN => 'throbbe',
      AWS_CLIWRAPPER_CATCH_ERROR_MIN_DELAY => 0,
      AWS_CLIWRAPPER_CATCH_ERROR_MAX_DELAY => 0,
    },
    command => 'ecs',
    subcommand => 'list-clusters',
    error_to_die_with => 'zong throbbe fung',
    retries => 3,
    error_msg_re => qr{^$},
    exception => qr{^$},
    want => {
      clusterArns => [
        "arn:aws:ecs:us-foo-1:123456789:cluster/foo",
        "arn:aws:ecs:us-foo-1:123456789:cluster/bar",
        "arn:aws:ecs:us-foo-1:123456789:cluster/baz"
      ],
    }
  },
}