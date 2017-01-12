use strict;
use warnings;

use Test::More;

use AWS::CLIWrapper;

subtest 'default' => sub {
  my $cli = AWS::CLIWrapper->new;
  is $cli->awscli_path, 'aws';
};

subtest 'specify explicit awscli path' => sub {
  my $cli = AWS::CLIWrapper->new(awscli_path => '/usr/local/bin/aws');
  is $cli->awscli_path, '/usr/local/bin/aws';
};

done_testing;
