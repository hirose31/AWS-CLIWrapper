use inc::Module::Install;


name       'AWS-CLIWrapper';
all_from   'lib/AWS/CLIWrapper.pm';
license    'perl';

requires_external_bin 'aws';

test_requires 'Test::More' => 0.88;

tests_recursive;
author_tests 'xt';

auto_set_repository;
use_test_base;
WriteAll;

