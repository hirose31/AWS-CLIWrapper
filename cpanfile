# -*- mode: cperl -*-

requires 'IPC::Cmd';
requires 'JSON::MaybeXS';
requires 'String::ShellQuote';
requires 'perl', '5.005';
requires 'version';
requires 'perl', '5.008001';

on configure => sub {
    requires 'ExtUtils::MakeMaker', '6.30';
};

on test => sub {
    requires 'Test::More';
};

on develop => sub {
    requires 'Test::Dependencies';
    requires 'Test::Perl::Critic';
    requires 'Test::LocalFunctions';
    requires 'Test::UsedModules';
    requires 'File::Temp';
};
