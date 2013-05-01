package AWS::CLIWrapper;

use strict;
use warnings;

our $VERSION = '0.05';

use JSON;
use IPC::Cmd;

our $Error = { Message => '', Code => '' };

our $true  = do { bless \(my $dummy = 1), "AWS::CLIWrapper::Boolean" };
our $false = do { bless \(my $dummy = 0), "AWS::CLIWrapper::Boolean" };

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
        push @v, map { ref($_) ? encode_json($_) : $_ } @$v;
    } elsif ($type eq 'HASH') {
        push @v, encode_json($v);
    } elsif ($type eq 'AWS::CLIWrapper::Boolean') {
        if ($$v == 1) {
            return ($k);
        } else {
            return ();
        }
    } else {
        push @v, $v;
    }

    return ($k, @v);
}

sub json { $_[0]->{json} }

sub _execute {
    my($self, $service, $operation, $param) = @_;
    my @cmd = ('aws', @{$self->{opt}}, $service, $operation);

    while (my($k, $v) = each %$param) {
        push @cmd, param2opt($k, $v);
    }
    warn "cmd: ".join(' ', @cmd) if $ENV{AWSCLI_DEBUG};

    my($ok, $err, $buf, $stdout_buf, $stderr_buf) = IPC::Cmd::run(
        command => \@cmd,
        timeout => 30,
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
            if (exists $ret->{Errors}{Error}) {
                $Error = $ret->{Errors}{Error}
            } elsif (exists $ret->{Response}{Errors}{Error}) {
                # old structure (maybe botocore < 0.7.0)
                $Error = $ret->{Response}{Errors}{Error};
            } else {
                $Error = { Message => 'Unknown', Code => 'Unknown' };
            }
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

# aws help | col -b | perl -ne 'if (/^AVAILABLE/.../^[A-Z]/) {  s/^\s+\?\s+// or next; chomp; printf "sub %-18s { shift->_execute('"'"'%s'"'"', \@_) }\n", $_, $_ }'
# aws help | col -b | perl -ne 'if (/^AVAILABLE/.../^[A-Z]/) {  s/^\s+\?\s+// or next; chomp; printf "=item B<%s>(\$operation:Str, \$param:HashRef)\n\n", $_}'
sub autoscaling        { shift->_execute('autoscaling', @_) }
sub cloudformation     { shift->_execute('cloudformation', @_) }
sub cloudwatch         { shift->_execute('cloudwatch', @_) }
sub datapipeline       { shift->_execute('datapipeline', @_) }
sub directconnect      { shift->_execute('directconnect', @_) }
sub ec2                { shift->_execute('ec2', @_) }
sub elasticbeanstalk   { shift->_execute('elasticbeanstalk', @_) }
sub elastictranscoder  { shift->_execute('elastictranscoder', @_) }
sub elb                { shift->_execute('elb', @_) }
sub emr                { shift->_execute('emr', @_) }
sub iam                { shift->_execute('iam', @_) }
sub importexport       { shift->_execute('importexport', @_) }
sub opsworks           { shift->_execute('opsworks', @_) }
sub rds                { shift->_execute('rds', @_) }
sub redshift           { shift->_execute('redshift', @_) }
sub s3                 { shift->_execute('s3', @_) }
sub ses                { shift->_execute('ses', @_) }
sub sns                { shift->_execute('sns', @_) }
sub sqs                { shift->_execute('sqs', @_) }
sub storagegateway     { shift->_execute('storagegateway', @_) }
sub sts                { shift->_execute('sts', @_) }
sub swf                { shift->_execute('swf', @_) }

1;

__END__

=encoding utf-8

=head1 NAME

AWS::CLIWrapper - Wrapper module for aws-cli

=head1 SYNOPSIS

    use AWS::CLIWrapper;
    
    my $aws = AWS::CLIWrapper->new(
        region => 'us-west-1',
       );
    
    my $res = $aws->ec2('describe-instances', {
        instance_ids => ['i-XXXXX', 'i-YYYYY'],
       });
    
    if ($res) {
        for my $rs ( @{ $res->{Reservations} }) {
            for my $is (@{ $rs->{Instances} }) {
                print $is->{InstanceId},"\n";
            }
        }
    } else {
        warn $AWS::CLIWrapper::Error->{Code};
        warn $AWS::CLIWrapper::Error->{Message};
    }

=head1 DESCRIPTION

AWS::CLIWrapper is wrapper module for aws-cli (recommend: awscli >= 0.7.0, botocore >= 0.7.0).

AWS::CLIWrapper is a just wrapper module, so you can do everything what you can do with aws-cli.

=head1 METHODS

=over 4

=item B<new>($param:HashRef)

Constructor of AWS::CLIWrapper. Acceptable param are:

    region       region_name:Str
    profile      profile_name:Str
    endpoint_url endpoint_url:Str

=item B<autoscaling>($operation:Str, $param:HashRef)

=item B<cloudformation>($operation:Str, $param:HashRef)

=item B<cloudwatch>($operation:Str, $param:HashRef)

=item B<datapipeline>($operation:Str, $param:HashRef)

=item B<directconnect>($operation:Str, $param:HashRef)

=item B<ec2>($operation:Str, $param:HashRef)

=item B<elasticbeanstalk>($operation:Str, $param:HashRef)

=item B<elastictranscoder>($operation:Str, $param:HashRef)

=item B<elb>($operation:Str, $param:HashRef)

=item B<emr>($operation:Str, $param:HashRef)

=item B<iam>($operation:Str, $param:HashRef)

=item B<importexport>($operation:Str, $param:HashRef)

=item B<opsworks>($operation:Str, $param:HashRef)

=item B<rds>($operation:Str, $param:HashRef)

=item B<redshift>($operation:Str, $param:HashRef)

=item B<s3>($operation:Str, $param:HashRef)

=item B<ses>($operation:Str, $param:HashRef)

=item B<sns>($operation:Str, $param:HashRef)

=item B<sqs>($operation:Str, $param:HashRef)

=item B<storagegateway>($operation:Str, $param:HashRef)

=item B<sts>($operation:Str, $param:HashRef)

=item B<swf>($operation:Str, $param:HashRef)

AWS::CLIWrapper provides methods same as services of aws-cli. Please refer to `aws help`.

First arg "operation" is same as operation of aws-cli. Please refer to `aws SERVICE help`.

Second arg "param" is same as command line option of aws-cli.
Please refer to `aws SERVICE OPERATION help`.

Key of param is string that trimmed leading "--" and replaced "-" to "_" for command line option (--instance-ids -> instance_ids).
Value of param is SCALAR or ARRAYREF or HASHREF.

You can specify C<(boolean)> parameter by C<$AWS::CLIWrapper::true> or C<$AWS::CLIWrapper::false>.

    my $res = $aws->ec2('assign-private-ip-addresses', {
        network_interface_id => $eni_id,
        private_ip_addresses => [ $private_ip_1, $private_ip_2 ],
        allow_reassignment   => $AWS::CLIWrapper::true,
       })

=back

=head1 ENVIRONMENT

=over 4

=item AWS_CONFIG_FILE

=item AWS_ACCESS_KEY_ID

=item AWS_SECRET_ACCESS_KEY

=item AWS_DEFAULT_REGION

See documents of aws-cli.

=back

=head1 AUTHOR

HIROSE Masaaki E<lt>hirose31 _at_ gmail.comE<gt>

=head1 REPOSITORY

L<https://github.com/hirose31/AWS-CLIWrapper>

  git clone git://github.com/hirose31/AWS-CLIWrapper.git

patches and collaborators are welcome.

=head1 SEE ALSO

L<http://aws.amazon.com/cli/>,
L<https://github.com/aws/aws-cli>,
L<http://docs.aws.amazon.com/AWSEC2/latest/APIReference/Welcome.html>,
L<https://github.com/boto/botocore>,

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

# vi: set ts=4 sw=4 sts=0 et ft=perl fenc=utf-8 ff=unix :
