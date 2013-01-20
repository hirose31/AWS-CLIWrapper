package AWS::CLIWrapper;

use strict;
use warnings;

our $VERSION = '0.01';

use JSON;
use IPC::Cmd;
use Log::Minimal;

our $Error = { Message => '', Code => '' };

sub new {
    my($class, %param) = @_;

    my @opt = ();
    for my $k (qw(region profile endpoint_url)) {
        if (my $v = delete $param{$k}) {
            push @opt, param2opt($k, $v);
        }
    }

    my $self = bless {
        opt  => \@opt,
        json => JSON->new,
    }, $class;

    return $self;
}

sub param2opt {
    my($k, $v) = @_;

    my @v;

    $k =~ s/_/-/g;
    $k = '--'.$k;

    my $type = ref $v;
    if (! $type) {
        push @v, $v;
    } elsif ($type eq 'ARRAY') {
        push @v, @$v;
    } elsif ($type eq 'HASH') {
        push @v, encode_json($v);
    } else {
        push @v, $v;
    }

    return($k, @v);
}

sub json { $_[0]->{json} }

sub _execute {
    my($self, $service, $operation, $param) = @_;
    my @cmd = ('aws', @{$self->{opt}}, $service, $operation);

    while (my($k, $v) = each %$param) {
        push @cmd, param2opt($k, $v);
    }

    my($ok, $err, $buf, $stdout_buf, $stderr_buf) = IPC::Cmd::run(
        command => \@cmd,
        timeout => 8,
       );

    if ($ok) {
        my $json = join "", @$stdout_buf;
        my($ret) = $self->json->decode_prefix($json);
        warn sprintf("%s.%s[%s]: %s\n",
                     $service, $operation, 'OK', $json,
                    ) if $ENV{AWSCLI_DEBUG};

        return $ret;
    } else {
        my $stdout_str = join "", @$stdout_buf;
        if ($stdout_str && $stdout_str =~ /^{/) {
            my $json = $stdout_str;
            warn sprintf("%s.%s[%s]: %s\n",
                         $service, $operation, 'NG', $json,
                        ) if $ENV{AWSCLI_DEBUG};
            my($ret) = $self->json->decode_prefix($json);
            $Error = $ret->{Response}{Errors}{Error};
        } else {
            my $msg = join("", @$buf).": ".$err;
            warn sprintf("%s.%s[%s]: %s\n",
                         $service, $operation, 'NG', $msg,
                        ) if $ENV{AWSCLI_DEBUG};
            $Error = { Message => $msg, Code => 'Unknown' };
       }
        return;
    }
}

# aws help | perl -ne 'if (/Available services/../^$/) { s/^\s+\*\s+// or next; chomp; printf "sub %-18s { shift->_execute('"'"'%s'"'"', \@_) }\n", $_, $_}'
sub autoscaling        { shift->_execute('autoscaling', @_) }
sub cloudformation     { shift->_execute('cloudformation', @_) }
sub cloudwatch         { shift->_execute('cloudwatch', @_) }
sub directconnect      { shift->_execute('directconnect', @_) }
sub ec2                { shift->_execute('ec2', @_) }
sub elasticbeanstalk   { shift->_execute('elasticbeanstalk', @_) }
sub elb                { shift->_execute('elb', @_) }
sub emr                { shift->_execute('emr', @_) }
sub iam                { shift->_execute('iam', @_) }
sub rds                { shift->_execute('rds', @_) }
sub ses                { shift->_execute('ses', @_) }
sub sns                { shift->_execute('sns', @_) }
sub sqs                { shift->_execute('sqs', @_) }
sub sts                { shift->_execute('sts', @_) }

1;

__END__

=encoding utf-8

=head1 NAME

AWS::CLIWrapper - fixme

=head1 SYNOPSIS

    use AWS::CLIWrapper;
    fixme

=head1 DESCRIPTION

AWS::CLIWrapper is fixme

=head1 METHODS

=over 4

=item B<method_name>($message:Str)

fixme

=back

=head1 ENVIRONMENT

=over 4

=item HOME

Used to determine the user's home directory.

=back

=head1 FILES

=over 4

=item F</path/to/config.ph>

設定ファイル。

=back

=head1 AUTHOR

HIROSE Masaaki E<lt>hirose31 _at_ gmail.comE<gt>

=head1 REPOSITORY

L<https://github.com/hirose31/aws-cliwrapper>

  git clone git://github.com/hirose31/aws-cliwrapper.git

patches and collaborators are welcome.

=head1 SEE ALSO

L<Module::Hoge|Module::Hoge>,
ls(1), cd(1)

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# for Emacsen
# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# indent-tabs-mode: nil
# coding: utf-8
# End:

# vi: set ts=4 sw=4 sts=0 :
