requires 'IPC::Cmd';
requires 'JSON', '2';
requires 'perl', '5.005';
requires 'version';

on configure => sub {
    requires 'ExtUtils::MakeMaker', '6.30';
    requires 'perl', '5.008001';
};

on test => sub {
    requires 'Test::More';
};

on develop => sub {
    requires 'Test::Dependencies';
    requires 'Test::Perl::Critic';
};
