package AWS::CLIWrapper;

use 5.008001;
use strict;
use warnings;

our $VERSION = '1.12';

use version;
use JSON 2;
use IPC::Cmd;
use String::ShellQuote;

our $Error = { Message => '', Code => '' };

our $true  = do { bless \(my $dummy = 1), "AWS::CLIWrapper::Boolean" };
our $false = do { bless \(my $dummy = 0), "AWS::CLIWrapper::Boolean" };

my $AWSCLI_VERSION = undef;

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
        awscli_path => $param{awscli_path} // 'aws',
    }, $class;

    return $self;
}

sub awscli_path {
    my ($self) = @_;
    return $self->{awscli_path};
}

sub awscli_version {
    my ($self) = @_;
    unless (defined $AWSCLI_VERSION) {
        $AWSCLI_VERSION = do {
            my $awscli_path = $self->awscli_path;
            my $vs = qx($awscli_path --version 2>&1) || '';
            my $v;
            if ($vs =~ m{/([0-9.]+)\s}) {
                $v = $1;
            } else {
                $v = 0;
            }
            version->parse($v);
        };
    }
    return $AWSCLI_VERSION;
}

sub param2opt {
    my($k, $v) = @_;

    my @v;

    $k =~ s/_/-/g;
    $k = '--'.$k;

    my $type = ref $v;
    if (! $type) {
        if ($k eq '--output-file') {
            # aws s3api get-object takes a single arg for output file path
            return $v;
        } else {
            push @v, $v;
        }
    } elsif ($type eq 'ARRAY') {
        push @v, map { ref($_) ? encode_json(_compat_kv($_)) : $_ } @$v;
    } elsif ($type eq 'HASH') {
        push @v, encode_json(_compat_kv($v));
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

# >= 0.14.0 : Key, Values, Value, Name
# <  0.14.0 : key, values, value, name
sub _compat_kv_uc {
    my $v = shift;
    my $type = ref $v;

    if ($type && $type eq 'HASH') {
        for my $hk (keys %$v) {
            if ($hk =~ /^(?:key|name|values|value)$/) {
                $v->{ucfirst($hk)} = delete $v->{$hk};
            }
        }
    }

    return $v;
}
# sub _compat_kv_lc {
#     my $v = shift;
#     my $type = ref $v;

#     if ($type && $type eq 'HASH') {
#         for my $hk (keys %$v) {
#             if ($hk =~ /^(?:Key|Name|Values|Values)$/) {
#                 $v->{lc($hk)} = delete $v->{$hk};
#             }
#         }
#     }

#     return $v;
# }
# Drop support < 0.14.0 for preventing execute aws command in loading this module
*_compat_kv = *_compat_kv_uc;

sub json { $_[0]->{json} }

sub _execute {
    my $self    = shift;
    my $service = shift;
    my $operation = shift;
    my @cmd = ($self->awscli_path, @{$self->{opt}}, $service, $operation);
    if ($service eq 'ec2' && $operation eq 'wait') {
        push(@cmd, shift @_);
    }
    if (ref($_[0]) eq 'ARRAY') {
        # for s3 sync FROM TO
        push @cmd, @{ shift @_ };
    }
    my($param, %opt) = @_;

    if ($service eq 'ec2' && $operation eq 'run-instances') {
        # compat: ec2 run-instances
        # >= 0.14.0 : --count N or --count MIN:MAX
        # <  0.14.0 : --min-count N and --max-count N
        if ($self->awscli_version >= 0.14.0) {
            my($min,$max) = (1,1);
            for my $hk (keys %$param) {
                if ($hk eq 'min_count') {
                    $min = delete $param->{min_count};
                } elsif ($hk eq 'max_count') {
                    $max = delete $param->{max_count};
                }
            }
            $param->{count} = "${min}:${max}" unless $param->{count}
        } else {
            my($min,$max);
            for my $hk (keys %$param) {
                if ($hk eq 'count') {
                    ($min,$max) = split /:/, delete($param->{count});
                    $max ||= $min;
                    last;
                }
            }
            $param->{min_count} = $min unless $param->{min_count};
            $param->{max_count} = $max unless $param->{max_count};
        }
    } elsif ($service eq 's3' && $self->awscli_version >= 0.15.0) {
        if ($operation !~ /^(?:cp|ls|mb|mv|rb|rm|sync|website)$/) {
            return $self->s3api($operation, @_);
        }
    } elsif ($service eq 's3api' && $self->awscli_version < 0.15.0) {
        return $self->s3($operation, @_);
    }

    while (my($k, $v) = each %$param) {
        my @o = param2opt($k, $v);
        if ($service eq 's3' && $k =~ /^(?:include|exclude)$/) {
            my $optk = shift @o;
            @o = map { $optk => $_ } @o;
        }
        push @cmd, @o;
    }
    @cmd = map { shell_quote($_) } @cmd;
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
            if ($ENV{AWSCLI_DEBUG}) {
                warn $@;
                warn qq|stdout: "$ret->{stdout}"|;
                warn qq|err_msg: "$ret->{err_msg}"|;
            }
            return $json || 'success';
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

# aws help | col -b | perl -ne 'if (/^AVAILABLE/.../^[A-Z]/) {  s/^\s+o\s+// or next; chomp; next if $_ eq 'help'; my $sn = $_; $sn =~ s/-/_/g; printf "sub %-18s { shift->_execute('"'"'%s'"'"', \@_) }\n", $sn, $_ }'
# aws help | col -b | perl -ne 'if (/^AVAILABLE/.../^[A-Z]/) {  s/^\s+o\s+// or next; chomp; next if $_ eq 'help'; my $sn = $_; $sn =~ s/-/_/g; printf "=item B<%s>(\$operation:Str, \$param:HashRef, %%opt:Hash)\n\n", $sn}'
# =item B<s3>($operation:Str, $path:ArrayRef, $param:HashRef, %opt:Hash)
sub acm                { shift->_execute('acm', @_) }
sub apigateway         { shift->_execute('apigateway', @_) }
sub application_autoscaling { shift->_execute('application-autoscaling', @_) }
sub autoscaling        { shift->_execute('autoscaling', @_) }
sub budgets            { shift->_execute('budgets', @_) }
sub cloudformation     { shift->_execute('cloudformation', @_) }
sub cloudfront         { shift->_execute('cloudfront', @_) }
sub cloudhsm           { shift->_execute('cloudhsm', @_) }
sub cloudsearch        { shift->_execute('cloudsearch', @_) }
sub cloudsearchdomain  { shift->_execute('cloudsearchdomain', @_) }
sub cloudtrail         { shift->_execute('cloudtrail', @_) }
sub cloudwatch         { shift->_execute('cloudwatch', @_) }
sub codecommit         { shift->_execute('codecommit', @_) }
sub codepipeline       { shift->_execute('codepipeline', @_) }
sub cognito_identity   { shift->_execute('cognito-identity', @_) }
sub cognito_idp        { shift->_execute('cognito-idp', @_) }
sub cognito_sync       { shift->_execute('cognito-sync', @_) }
sub configservice      { shift->_execute('configservice', @_) }
sub configure          { shift->_execute('configure', @_) }
sub datapipeline       { shift->_execute('datapipeline', @_) }
sub deploy             { shift->_execute('deploy', @_) }
sub devicefarm         { shift->_execute('devicefarm', @_) }
sub directconnect      { shift->_execute('directconnect', @_) }
sub discovery          { shift->_execute('discovery', @_) }
sub dms                { shift->_execute('dms', @_) }
sub ds                 { shift->_execute('ds', @_) }
sub dynamodb           { shift->_execute('dynamodb', @_) }
sub dynamodbstreams    { shift->_execute('dynamodbstreams', @_) }
sub ec2                { shift->_execute('ec2', @_) }
sub ecr                { shift->_execute('ecr', @_) }
sub ecs                { shift->_execute('ecs', @_) }
sub efs                { shift->_execute('efs', @_) }
sub elasticache        { shift->_execute('elasticache', @_) }
sub elasticbeanstalk   { shift->_execute('elasticbeanstalk', @_) }
sub elastictranscoder  { shift->_execute('elastictranscoder', @_) }
sub elb                { shift->_execute('elb', @_) }
sub elbv2              { shift->_execute('elbv2', @_) }
sub emr                { shift->_execute('emr', @_) }
sub es                 { shift->_execute('es', @_) }
sub events             { shift->_execute('events', @_) }
sub firehose           { shift->_execute('firehose', @_) }
sub gamelift           { shift->_execute('gamelift', @_) }
sub glacier            { shift->_execute('glacier', @_) }
sub iam                { shift->_execute('iam', @_) }
sub importexport       { shift->_execute('importexport', @_) }
sub inspector          { shift->_execute('inspector', @_) }
sub iot                { shift->_execute('iot', @_) }
sub iot_data           { shift->_execute('iot-data', @_) }
sub kinesis            { shift->_execute('kinesis', @_) }
sub kinesisanalytics   { shift->_execute('kinesisanalytics', @_) }
sub kms                { shift->_execute('kms', @_) }
sub lambda             { shift->_execute('lambda', @_) }
sub lightsail          { shift->_execute('lightsail', @_) }
sub logs               { shift->_execute('logs', @_) }
sub machinelearning    { shift->_execute('machinelearning', @_) }
sub marketplacecommerceanalytics { shift->_execute('marketplacecommerceanalytics', @_) }
sub meteringmarketplace { shift->_execute('meteringmarketplace', @_) }
sub opsworks           { shift->_execute('opsworks', @_) }
sub polly              { shift->_execute('polly', @_) }
sub rds                { shift->_execute('rds', @_) }
sub redshift           { shift->_execute('redshift', @_) }
sub rekognition        { shift->_execute('rekognition', @_) }
sub route53            { shift->_execute('route53', @_) }
sub route53domains     { shift->_execute('route53domains', @_) }
sub s3                 { shift->_execute('s3', @_) }
sub s3api              { shift->_execute('s3api', @_) }
sub sdb                { shift->_execute('sdb', @_) }
sub servicecatalog     { shift->_execute('servicecatalog', @_) }
sub ses                { shift->_execute('ses', @_) }
sub sms                { shift->_execute('sms', @_) }
sub snowball           { shift->_execute('snowball', @_) }
sub sns                { shift->_execute('sns', @_) }
sub sqs                { shift->_execute('sqs', @_) }
sub ssm                { shift->_execute('ssm', @_) }
sub storagegateway     { shift->_execute('storagegateway', @_) }
sub sts                { shift->_execute('sts', @_) }
sub support            { shift->_execute('support', @_) }
sub swf                { shift->_execute('swf', @_) }
sub waf                { shift->_execute('waf', @_) }
sub workspaces         { shift->_execute('workspaces', @_) }

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

AWS::CLIWrapper is wrapper module for aws-cli (recommend: awscli >= 1.0.0, requires: >= 0.40.0).

AWS::CLIWrapper is a just wrapper module, so you can do everything what you can do with aws-cli.

See note below about making sure AWS credentials are accessible (especially under crond)

=head1 METHODS

=over 4

=item B<new>($param:HashRef)

Constructor of AWS::CLIWrapper. Acceptable param are:

    region       region_name:Str
    profile      profile_name:Str
    endpoint_url endpoint_url:Str

=item B<acm>($operation:Str, $param:HashRef, %opt:Hash)

=item B<apigateway>($operation:Str, $param:HashRef, %opt:Hash)

=item B<application_autoscaling>($operation:Str, $param:HashRef, %opt:Hash)

=item B<autoscaling>($operation:Str, $param:HashRef, %opt:Hash)

=item B<budgets>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudformation>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudfront>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudhsm>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudsearch>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudsearchdomain>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudtrail>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudwatch>($operation:Str, $param:HashRef, %opt:Hash)

=item B<codecommit>($operation:Str, $param:HashRef, %opt:Hash)

=item B<codepipeline>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cognito_identity>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cognito_idp>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cognito_sync>($operation:Str, $param:HashRef, %opt:Hash)

=item B<configservice>($operation:Str, $param:HashRef, %opt:Hash)

=item B<configure>($operation:Str, $param:HashRef, %opt:Hash)

=item B<datapipeline>($operation:Str, $param:HashRef, %opt:Hash)

=item B<deploy>($operation:Str, $param:HashRef, %opt:Hash)

=item B<devicefarm>($operation:Str, $param:HashRef, %opt:Hash)

=item B<directconnect>($operation:Str, $param:HashRef, %opt:Hash)

=item B<discovery>($operation:Str, $param:HashRef, %opt:Hash)

=item B<dms>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ds>($operation:Str, $param:HashRef, %opt:Hash)

=item B<dynamodb>($operation:Str, $param:HashRef, %opt:Hash)

=item B<dynamodbstreams>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ec2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ecr>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ecs>($operation:Str, $param:HashRef, %opt:Hash)

=item B<efs>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elasticache>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elasticbeanstalk>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elastictranscoder>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elb>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elbv2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<emr>($operation:Str, $param:HashRef, %opt:Hash)

=item B<es>($operation:Str, $param:HashRef, %opt:Hash)

=item B<events>($operation:Str, $param:HashRef, %opt:Hash)

=item B<firehose>($operation:Str, $param:HashRef, %opt:Hash)

=item B<gamelift>($operation:Str, $param:HashRef, %opt:Hash)

=item B<glacier>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iam>($operation:Str, $param:HashRef, %opt:Hash)

=item B<importexport>($operation:Str, $param:HashRef, %opt:Hash)

=item B<inspector>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iot>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iot_data>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kinesis>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kinesisanalytics>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kms>($operation:Str, $param:HashRef, %opt:Hash)

=item B<lambda>($operation:Str, $param:HashRef, %opt:Hash)

=item B<lightsail>($operation:Str, $param:HashRef, %opt:Hash)

=item B<logs>($operation:Str, $param:HashRef, %opt:Hash)

=item B<machinelearning>($operation:Str, $param:HashRef, %opt:Hash)

=item B<marketplacecommerceanalytics>($operation:Str, $param:HashRef, %opt:Hash)

=item B<meteringmarketplace>($operation:Str, $param:HashRef, %opt:Hash)

=item B<opsworks>($operation:Str, $param:HashRef, %opt:Hash)

=item B<polly>($operation:Str, $param:HashRef, %opt:Hash)

=item B<rds>($operation:Str, $param:HashRef, %opt:Hash)

=item B<redshift>($operation:Str, $param:HashRef, %opt:Hash)

=item B<rekognition>($operation:Str, $param:HashRef, %opt:Hash)

=item B<route53>($operation:Str, $param:HashRef, %opt:Hash)

=item B<route53domains>($operation:Str, $param:HashRef, %opt:Hash)

=item B<s3>($operation:Str, $path:ArrayRef, $param:HashRef, %opt:Hash)

=item B<s3api>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sdb>($operation:Str, $param:HashRef, %opt:Hash)

=item B<servicecatalog>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ses>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sms>($operation:Str, $param:HashRef, %opt:Hash)

=item B<snowball>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sns>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sqs>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ssm>($operation:Str, $param:HashRef, %opt:Hash)

=item B<storagegateway>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sts>($operation:Str, $param:HashRef, %opt:Hash)

=item B<support>($operation:Str, $param:HashRef, %opt:Hash)

=item B<swf>($operation:Str, $param:HashRef, %opt:Hash)

=item B<waf>($operation:Str, $param:HashRef, %opt:Hash)

=item B<workspaces>($operation:Str, $param:HashRef, %opt:Hash)

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

Special case: several OPERATIONs take a single arg. For example "aws s3api get-object ... output_file". In this case, You can specify below using C<output_file> key:

    my $res = $aws->s3api('get-object', {
        bucket      => 'my-bucket',
        key         => 'blahblahblah',
        output_file => '/path/to/output/file',
    })

Special case: s3 OPERATION takes one or two arguments in addition to options. For example "aws s3 cp LocalPath s3://S3Path". Pass an extra ARRAYREF to the s3 method in this case:

    my $res = $aws->s3('cp', ['LocalPath', 's3://S3Path'], {
        exclude     => '*.bak',
    })

Special case: s3 OPERATION can take --include and --exclude option multiple times. For example "aws s3 sync --exclude 'foo' --exclude 'bar' LocalPath s3://S3Path", Pass ARRAYREF as value of C<include> or C<exclude> in this case:

    my $res = $aws->s3('sync', ['LocalPath', 's3://S3Path'], {
        exclude     => ['foo', 'bar'],
    })

Third arg "opt" is optional. Available key/values are below:

  timeout => Int
    Maximum time the "aws" command is allowed to run before aborting.
    default is 30 seconds.

  nofork => Int (>0)
    Call IPC::Cmd::run vs. IPC::Cmd::run_forked (mostly useful if/when in perl debugger).  Note: 'timeout', if used with 'nofork', will merely cause an alarm and return.  ie. 'run' will NOT kill the awscli command like 'run_forked' will.

=back

=head1 ENVIRONMENT

=over 4

=item HOME: used by default by /usr/bin/aws utility to find it's credentials (if none are specified)

Special note: cron on Linux will often have a different HOME "/" instead of "/root" - set $ENV{'HOME'}
to use the default credentials or specify $ENV{'AWS_CONFIG_FILE'} directly.

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
