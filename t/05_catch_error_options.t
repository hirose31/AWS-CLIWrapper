use 5.008001;
use strict;
use warnings;
no warnings 'uninitialized';

use Test::More;
use AWS::CLIWrapper;

my %default_args = (
  awscli_path => 't/bin/mock-aws',
  nofork => 1,
);

my $tests = eval join "\n", <DATA> or die "$@";

for my $test_name (keys %$tests) {
  next if @ARGV and not grep { $_ eq $test_name } @ARGV;

  my $test = $tests->{$test_name};
  my ($args, $env, $method, $want) = @$test{qw(args env method want)};

  $env = {} unless $env;

  local @ENV{keys %$env} = values %$env;

  my $aws = AWS::CLIWrapper->new(%default_args, %{$args || {}});
  my $have = $aws->$method;

  if ('ARRAY' eq ref $want) {
    cmp_ok $have, $_->[0], $_->[1], "$test_name " . (join ' ', @$_) for @$want;
  }
  else {
    is $have, $want, $test_name;
  }
}


done_testing;

__DATA__
# line 41
{
  'mock-aws version' => {
    method => 'awscli_version',
    want => '2.42.4242',
  },
  'default-catch_error_pattern' => {
    method => 'catch_error_pattern',
    want => undef,
  },
  'default-catch_error_retries' => {
    method => 'catch_error_retries',
    want => 3,
  },
  'default-catch_error_min_delay' => {
    method => 'catch_error_min_delay',
    want => 3,
  },
  'default-catch_error_max_delay' => {
    method => 'catch_error_max_delay',
    want => 10,
  },
  'default-catch_error_delay' => {
    method => 'catch_error_delay',
    want => [['>=', 3], ['<=', 10]],
  },
  'env-catch_error_pattern' => {
    env => {
      AWS_CLIWRAPPER_CATCH_ERROR_PATTERN => 'foo',
    },
    method => 'catch_error_pattern',
    want => 'foo',
  },
  'env-catch_error_retries' => {
    env => {
      AWS_CLIWRAPPER_CATCH_ERROR_RETRIES => 10,
    },
    method => 'catch_error_retries',
    want => 10,
  },
  'env-catch_error_retries-invalid' => {
    env => {
      AWS_CLIWRAPPER_CATCH_ERROR_RETRIES => -10,
    },
    method => 'catch_error_retries',
    want => 3,
  },
  'env-catch_error_min_delay' => {
    env => {
      AWS_CLIWRAPPER_CATCH_ERROR_MIN_DELAY => 15,
    },
    method => 'catch_error_min_delay',
    want => 15,
  },
  'env-catch_error_min_delay-invalid' => {
    env => {
      AWS_CLIWRAPPER_CATCH_ERROR_MIN_DELAY => -15,
    },
    method => 'catch_error_min_delay',
    want => 3,
  },
  'env-catch_error_max_delay' => {
    env => {
      AWS_CLIWRAPPER_CATCH_ERROR_MAX_DELAY => 30,
    },
    method => 'catch_error_max_delay',
    want => 30,
  },
  'env-catch_error_max_delay-invalid' => {
    env => {
      AWS_CLIWRAPPER_CATCH_ERROR_MAX_DELAY => -30,
    },
    method => 'catch_error_max_delay',
    want => 10,
  },
  'env-catch_error_max_delay-gt-min_delay' => {
    env => {
      AWS_CLIWRAPPER_CATCH_ERROR_MIN_DELAY => 30,
      AWS_CLIWRAPPER_CATCH_ERROR_MAX_DELAY => 15,
    },
    method => 'catch_error_max_delay',
    want => 30,
  },
  'args-catch_error_pattern' => {
    args => {
      catch_error_pattern => 'bar',
    },
    method => 'catch_error_pattern',
    want => 'bar',
  },
  'env-over-args-catch_error_pattern' => {
    args => {
      catch_error_pattern => 'qux',
    },
    env => {
      AWS_CLIWRAPPER_CATCH_ERROR_PATTERN => 'baz',
    },
    method => 'catch_error_pattern',
    want => 'baz',
  },
  'args-catch_error_retries' => {
    args => {
      catch_error_retries => 10,
    },
    method => 'catch_error_retries',
    want => 10,
  },
  'env-over-args-catch_error_retries' => {
    env => {
      AWS_CLIWRAPPER_CATCH_ERROR_RETRIES => 20,
    },
    args => {
      catch_error_retries => 10,
    },
    method => 'catch_error_retries',
    want => 20,
  },
  'args-catch_error_min_delay' => {
    args => {
      catch_error_min_delay => 20,
    },
    method => 'catch_error_min_delay',
    want => 20,
  },
  'env-over-args-catch_error_min_delay' => {
    env => {
      AWS_CLIWRAPPER_CATCH_ERROR_MIN_DELAY => 40,
    },
    args => {
      catch_error_min_delay => 20,
    },
    method => 'catch_error_min_delay',
    want => 40,
  },
  'args-catch_error_max_delay' => {
    args => {
      catch_error_max_delay => 60,
    },
    method => 'catch_error_max_delay',
    want => 60,
  },
  'env-over-args-catch_error_max_delay' => {
    env => {
      AWS_CLIWRAPPER_CATCH_ERROR_MAX_DELAY => 120,
    },
    args => {
      catch_error_max_delay => 60,
    },
    method => 'catch_error_max_delay',
    want => 120,
  },
  'min-max-catch_error_delay' => {
    args => {
      catch_error_min_delay => 30,
      catch_error_max_delay => 30,
    },
    method => 'catch_error_delay',
    want => 30,
  },
  'zero-catch_error_delay' => {
    args => {
      catch_error_min_delay => 0,
      catch_error_max_delay => 0,
    },
    method => 'catch_error_delay',
    want => 0,
  },
}