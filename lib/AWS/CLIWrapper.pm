package AWS::CLIWrapper;

use strict;
use warnings;

our $VERSION = '0.07';

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
        if ($k eq '--output-file') {
            # aws s3 get-object takes a single arg for output file path
            return $v;
        } else {
            push @v, $v;
        }
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

    @v = map { qq{'$_'} } @v;
    return ($k, @v);
}

sub json { $_[0]->{json} }

sub _execute {
    my($self, $service, $operation, $param, %opt) = @_;
    my @cmd = ('aws', @{$self->{opt}}, $service, $operation);

    while (my($k, $v) = each %$param) {
        push @cmd, param2opt($k, $v);
    }
    warn "cmd: ".join(' ', @cmd) if $ENV{AWSCLI_DEBUG};

    my $ret;
    if (exists $opt{'nofork'} && $opt{'nofork'}) {
        # better for perl debugger
        my($ok, $err, $buf, $stdout_buf, $stderr_buf) = IPC::Cmd::run(
            command => join(' ', @cmd),
            timeout => $opt{timeout} || 30,
        );
        $ret->{stdout} = join "", @$stdout_buf;
        $ret->{err_msg} = (defined $err ? "$err\n" : "") . join "", @$stderr_buf;
        if ($ok) {
            $ret->{exit_code} = 0;
            $ret->{timeout} = 0;
        } else {
            $ret->{exit_code} = 2;
            $ret->{timeout} = 1 if defined $err && $err =~ /^IPC::Cmd::TimeOut:/;
        }
        print "";
    } else {
        $ret = IPC::Cmd::run_forked(join(' ', @cmd), {
            timeout => $opt{timeout} || 30,
        });
    }

    if ($ret->{exit_code} == 0 && $ret->{timeout} == 0) {
        my $json = $ret->{stdout};
        warn sprintf("%s.%s[%s]: %s\n",
                     $service, $operation, 'OK', $json,
                    ) if $ENV{AWSCLI_DEBUG};
        local $@;
        my($ret) = eval {
            # aws s3 returns null HTTP body, so failed to parse as JSON
            $self->json->decode_prefix($json);
        };
        if ($@) {
            warn $@ if $ENV{AWSCLI_DEBUG};
            return $json;
        }
        return $ret;
    } else {
        my $stdout_str = $ret->{stdout};
        if ($stdout_str && $stdout_str =~ /^{/) {
            my $json = $stdout_str;
            warn sprintf("%s.%s[%s]: %s\n",
                         $service, $operation, 'NG', $json,
                        ) if $ENV{AWSCLI_DEBUG};
            my($ret) = $self->json->decode_prefix($json);
            if (exists $ret->{Errors} && ref($ret->{Errors}) eq 'ARRAY') {
                $Error = $ret->{Errors}[0];
            } elsif (exists $ret->{Response}{Errors}{Error}) {
                # old structure (maybe botocore < 0.7.0)
                $Error = $ret->{Response}{Errors}{Error};
            } else {
                $Error = { Message => 'Unknown', Code => 'Unknown' };
            }
        } else {
            my $msg = $ret->{err_msg};
            warn sprintf("%s.%s[%s]: %s\n",
                         $service, $operation, 'NG', $msg,
                        ) if $ENV{AWSCLI_DEBUG};
            $Error = { Message => $msg, Code => 'Unknown' };
       }
        return;
    }
}

# aws help | col -b | perl -ne 'if (/^AVAILABLE/.../^[A-Z]/) {  s/^\s+o\s+// or next; chomp; printf "sub %-18s { shift->_execute('"'"'%s'"'"', \@_) }\n", $_, $_ }'
# aws help | col -b | perl -ne 'if (/^AVAILABLE/.../^[A-Z]/) {  s/^\s+o\s+// or next; chomp; printf "=item B<%s>(\$operation:Str, \$param:HashRef)\n\n", $_}'
sub autoscaling        { shift->_execute('autoscaling', @_) }
sub cloudformation     { shift->_execute('cloudformation', @_) }
sub cloudsearch        { shift->_execute('cloudsearch', @_) }
sub cloudwatch         { shift->_execute('cloudwatch', @_) }
sub datapipeline       { shift->_execute('datapipeline', @_) }
sub directconnect      { shift->_execute('directconnect', @_) }
sub ec2                { shift->_execute('ec2', @_) }
sub elasticache        { shift->_execute('elasticache', @_) }
sub elasticbeanstalk   { shift->_execute('elasticbeanstalk', @_) }
sub elastictranscoder  { shift->_execute('elastictranscoder', @_) }
sub elb                { shift->_execute('elb', @_) }
sub emr                { shift->_execute('emr', @_) }
sub iam                { shift->_execute('iam', @_) }
sub importexport       { shift->_execute('importexport', @_) }
sub opsworks           { shift->_execute('opsworks', @_) }
sub rds                { shift->_execute('rds', @_) }
sub redshift           { shift->_execute('redshift', @_) }
sub route53            { shift->_execute('route53', @_) }
sub s3                 { shift->_execute('s3', @_) }
sub ses                { shift->_execute('ses', @_) }
sub sns                { shift->_execute('sns', @_) }
sub sqs                { shift->_execute('sqs', @_) }
sub storagegateway     { shift->_execute('storagegateway', @_) }
sub sts                { shift->_execute('sts', @_) }
sub support            { shift->_execute('support', @_) }
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
    
    my $res = $aws->ec2(
        'describe-instances' => {
            instance_ids => ['i-XXXXX', 'i-YYYYY'],
        },
        timeout => 18, # optional. default is 30 seconds
    );
    
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

=item B<autoscaling>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudformation>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudsearch>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudwatch>($operation:Str, $param:HashRef, %opt:Hash)

=item B<datapipeline>($operation:Str, $param:HashRef, %opt:Hash)

=item B<directconnect>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ec2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elasticache>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elasticbeanstalk>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elastictranscoder>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elb>($operation:Str, $param:HashRef, %opt:Hash)

=item B<emr>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iam>($operation:Str, $param:HashRef, %opt:Hash)

=item B<importexport>($operation:Str, $param:HashRef, %opt:Hash)

=item B<opsworks>($operation:Str, $param:HashRef, %opt:Hash)

=item B<rds>($operation:Str, $param:HashRef, %opt:Hash)

=item B<redshift>($operation:Str, $param:HashRef, %opt:Hash)

=item B<route53>($operation:Str, $param:HashRef, %opt:Hash)

=item B<s3>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ses>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sns>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sqs>($operation:Str, $param:HashRef, %opt:Hash)

=item B<storagegateway>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sts>($operation:Str, $param:HashRef, %opt:Hash)

=item B<support>($operation:Str, $param:HashRef, %opt:Hash)

=item B<swf>($operation:Str, $param:HashRef, %opt:Hash)

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

Special case: several OPERATIONs take a single arg. For example "aws s3 get-object ... output_file". In this case, You can specify below using C<output_file> key:

    my $res = $aws->s3('get-object', {
        bucket      => 'my-bucket',
        key         => 'blahblahblah',
        output_file => '/path/to/output/file',
    })

Third arg "opt" is optional. Available key/values are below:

  timeout => Int
    Maximum time the "aws" command is allowed to run before aborting.
    default is 30 seconds.

  nofork => Int (>0)
    Call IPC::Cmd::run vs. IPC::Cmd::run_forked (mostly useful if/when in perl debugger)

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
