package AWS::CLIWrapper;

use 5.008001;
use strict;
use warnings;

our $VERSION = '1.24';

use version;
use JSON 2;
use IPC::Cmd;
use String::ShellQuote;
use Carp;

our $Error = { Message => '', Code => '' };

our $true  = do { bless \(my $dummy = 1), "AWS::CLIWrapper::Boolean" };
our $false = do { bless \(my $dummy = 0), "AWS::CLIWrapper::Boolean" };

my $AWSCLI_VERSION = undef;
my $DEFAULT_CATCH_ERROR_RETRIES = 3;
my $DEFAULT_CATCH_ERROR_MIN_DELAY = 3;
my $DEFAULT_CATCH_ERROR_MAX_DELAY = 10;

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
        param => \%param,
        awscli_path => $param{awscli_path} || 'aws',
        croak_on_error => !!$param{croak_on_error},
        timeout => (defined $ENV{AWS_CLIWRAPPER_TIMEOUT}) ? $ENV{AWS_CLIWRAPPER_TIMEOUT} : 30,
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

sub catch_error_pattern {
    my ($self) = @_;

    return $ENV{AWS_CLIWRAPPER_CATCH_ERROR_PATTERN}
        if defined $ENV{AWS_CLIWRAPPER_CATCH_ERROR_PATTERN};

    return $self->{param}->{catch_error_pattern}
        if defined $self->{param}->{catch_error_pattern};
    
    return;
}

sub catch_error_retries {
    my ($self) = @_;

    my $retries = defined $ENV{AWS_CLIWRAPPER_CATCH_ERROR_RETRIES}
        ? $ENV{AWS_CLIWRAPPER_CATCH_ERROR_RETRIES}
        : defined $self->{param}->{catch_error_retries}
            ? $self->{param}->{catch_error_retries}
            : $DEFAULT_CATCH_ERROR_RETRIES;

    $retries = $DEFAULT_CATCH_ERROR_RETRIES if $retries < 0;

    return $retries;
}

sub catch_error_min_delay {
    my ($self) = @_;

    my $min_delay = defined $ENV{AWS_CLIWRAPPER_CATCH_ERROR_MIN_DELAY}
        ? $ENV{AWS_CLIWRAPPER_CATCH_ERROR_MIN_DELAY}
        : defined $self->{param}->{catch_error_min_delay}
            ? $self->{param}->{catch_error_min_delay}
            : $DEFAULT_CATCH_ERROR_MIN_DELAY;
    
    $min_delay = $DEFAULT_CATCH_ERROR_MIN_DELAY if $min_delay < 0;

    return $min_delay;
}

sub catch_error_max_delay {
    my ($self) = @_;

    my $min_delay = $self->catch_error_min_delay;

    my $max_delay = defined $ENV{AWS_CLIWRAPPER_CATCH_ERROR_MAX_DELAY}
        ? $ENV{AWS_CLIWRAPPER_CATCH_ERROR_MAX_DELAY}
        : defined $self->{param}->{catch_error_max_delay}
            ? $self->{param}->{catch_error_max_delay}
            : $DEFAULT_CATCH_ERROR_MAX_DELAY;
    
    $max_delay = $DEFAULT_CATCH_ERROR_MAX_DELAY if $max_delay < 0;

    $max_delay = $min_delay if $min_delay > $max_delay;

    return $max_delay;
}

sub catch_error_delay {
    my ($self) = @_;

    my $min = $self->catch_error_min_delay;
    my $max = $self->catch_error_max_delay;

    return $min == $max ? $min : $min + (int rand $max - $min);
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

    my $error_re = $self->catch_error_pattern;
    my $retries = $error_re ? $self->catch_error_retries : 0;

    RETRY: {
        $Error = { Message => '', Code => '' };

        my $exit_value = $self->_run(\%opt, \@cmd);
        my $ret = $self->_handle($service, $operation, $exit_value);

        return $ret unless $Error->{Code};

        if ($retries-- > 0 and $Error->{Message} =~ $error_re) {
            my $delay = $self->catch_error_delay;

            warn "Caught error matching $error_re, sleeping $delay seconds before retrying\n"
                if $ENV{AWSCLI_DEBUG};

            sleep $delay;

            redo RETRY;
        }

        croak $Error->{Message} if $self->{croak_on_error};

        return $ret;
    }
}

sub _run {
    my ($self, $opt, $cmd) = @_;

    my $ret;
    if (exists $opt->{'nofork'} && $opt->{'nofork'}) {
        # better for perl debugger
        my($ok, $err, $buf, $stdout_buf, $stderr_buf) = IPC::Cmd::run(
            command => join(' ', @$cmd),
            timeout => $opt->{timeout} || $self->{timeout},
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
        $ret = IPC::Cmd::run_forked(join(' ', @$cmd), {
            timeout => $opt->{timeout} || $self->{timeout},
        });
    }

    return $ret;
}

sub _handle {
    my ($self, $service, $operation, $ret) = @_;

    if ($ret->{exit_code} == 0 && $ret->{timeout} == 0) {
        my $json = $ret->{stdout};
        warn sprintf("%s.%s[%s]: %s\n",
                     $service, $operation, 'OK', $json,
                    ) if $ENV{AWSCLI_DEBUG};
        local $@;
        my($ret) = eval {
            # aws s3 returns null HTTP body, so failed to parse as JSON

            # Temporary disable __DIE__ handler to prevent the
            # exception from decode() from catching by outer
            # __DIE__ handler.
            local $SIG{__DIE__} = sub {};

            $self->json->decode($json);
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
sub accessanalyzer     { shift->_execute('accessanalyzer', @_) }
sub account            { shift->_execute('account', @_) }
sub acm                { shift->_execute('acm', @_) }
sub acm_pca            { shift->_execute('acm-pca', @_) }
sub alexaforbusiness   { shift->_execute('alexaforbusiness', @_) }
sub amp                { shift->_execute('amp', @_) }
sub amplify            { shift->_execute('amplify', @_) }
sub amplifybackend     { shift->_execute('amplifybackend', @_) }
sub amplifyuibuilder   { shift->_execute('amplifyuibuilder', @_) }
sub apigateway         { shift->_execute('apigateway', @_) }
sub apigatewaymanagementapi { shift->_execute('apigatewaymanagementapi', @_) }
sub apigatewayv2       { shift->_execute('apigatewayv2', @_) }
sub appconfig          { shift->_execute('appconfig', @_) }
sub appconfigdata      { shift->_execute('appconfigdata', @_) }
sub appflow            { shift->_execute('appflow', @_) }
sub appintegrations    { shift->_execute('appintegrations', @_) }
sub application_autoscaling { shift->_execute('application-autoscaling', @_) }
sub application_insights { shift->_execute('application-insights', @_) }
sub applicationcostprofiler { shift->_execute('applicationcostprofiler', @_) }
sub appmesh            { shift->_execute('appmesh', @_) }
sub apprunner          { shift->_execute('apprunner', @_) }
sub appstream          { shift->_execute('appstream', @_) }
sub appsync            { shift->_execute('appsync', @_) }
sub arc_zonal_shift    { shift->_execute('arc-zonal-shift', @_) }
sub athena             { shift->_execute('athena', @_) }
sub auditmanager       { shift->_execute('auditmanager', @_) }
sub autoscaling        { shift->_execute('autoscaling', @_) }
sub autoscaling_plans  { shift->_execute('autoscaling-plans', @_) }
sub backup             { shift->_execute('backup', @_) }
sub backup_gateway     { shift->_execute('backup-gateway', @_) }
sub backupstorage      { shift->_execute('backupstorage', @_) }
sub batch              { shift->_execute('batch', @_) }
sub billingconductor   { shift->_execute('billingconductor', @_) }
sub braket             { shift->_execute('braket', @_) }
sub budgets            { shift->_execute('budgets', @_) }
sub ce                 { shift->_execute('ce', @_) }
sub chime              { shift->_execute('chime', @_) }
sub chime_sdk_identity { shift->_execute('chime-sdk-identity', @_) }
sub chime_sdk_media_pipelines { shift->_execute('chime-sdk-media-pipelines', @_) }
sub chime_sdk_meetings { shift->_execute('chime-sdk-meetings', @_) }
sub chime_sdk_messaging { shift->_execute('chime-sdk-messaging', @_) }
sub chime_sdk_voice    { shift->_execute('chime-sdk-voice', @_) }
sub cleanrooms         { shift->_execute('cleanrooms', @_) }
sub cloud9             { shift->_execute('cloud9', @_) }
sub cloudcontrol       { shift->_execute('cloudcontrol', @_) }
sub clouddirectory     { shift->_execute('clouddirectory', @_) }
sub cloudformation     { shift->_execute('cloudformation', @_) }
sub cloudfront         { shift->_execute('cloudfront', @_) }
sub cloudhsm           { shift->_execute('cloudhsm', @_) }
sub cloudhsmv2         { shift->_execute('cloudhsmv2', @_) }
sub cloudsearch        { shift->_execute('cloudsearch', @_) }
sub cloudsearchdomain  { shift->_execute('cloudsearchdomain', @_) }
sub cloudtrail         { shift->_execute('cloudtrail', @_) }
sub cloudtrail_data    { shift->_execute('cloudtrail-data', @_) }
sub cloudwatch         { shift->_execute('cloudwatch', @_) }
sub codeartifact       { shift->_execute('codeartifact', @_) }
sub codebuild          { shift->_execute('codebuild', @_) }
sub codecatalyst       { shift->_execute('codecatalyst', @_) }
sub codecommit         { shift->_execute('codecommit', @_) }
sub codeguru_reviewer  { shift->_execute('codeguru-reviewer', @_) }
sub codeguruprofiler   { shift->_execute('codeguruprofiler', @_) }
sub codepipeline       { shift->_execute('codepipeline', @_) }
sub codestar           { shift->_execute('codestar', @_) }
sub codestar_connections { shift->_execute('codestar-connections', @_) }
sub codestar_notifications { shift->_execute('codestar-notifications', @_) }
sub cognito_identity   { shift->_execute('cognito-identity', @_) }
sub cognito_idp        { shift->_execute('cognito-idp', @_) }
sub cognito_sync       { shift->_execute('cognito-sync', @_) }
sub comprehend         { shift->_execute('comprehend', @_) }
sub comprehendmedical  { shift->_execute('comprehendmedical', @_) }
sub compute_optimizer  { shift->_execute('compute-optimizer', @_) }
sub configservice      { shift->_execute('configservice', @_) }
sub configure          { shift->_execute('configure', @_) }
sub connect            { shift->_execute('connect', @_) }
sub connect_contact_lens { shift->_execute('connect-contact-lens', @_) }
sub connectcampaigns   { shift->_execute('connectcampaigns', @_) }
sub connectcases       { shift->_execute('connectcases', @_) }
sub connectparticipant { shift->_execute('connectparticipant', @_) }
sub controltower       { shift->_execute('controltower', @_) }
sub cur                { shift->_execute('cur', @_) }
sub customer_profiles  { shift->_execute('customer-profiles', @_) }
sub databrew           { shift->_execute('databrew', @_) }
sub dataexchange       { shift->_execute('dataexchange', @_) }
sub datapipeline       { shift->_execute('datapipeline', @_) }
sub datasync           { shift->_execute('datasync', @_) }
sub dax                { shift->_execute('dax', @_) }
sub deploy             { shift->_execute('deploy', @_) }
sub detective          { shift->_execute('detective', @_) }
sub devicefarm         { shift->_execute('devicefarm', @_) }
sub devops_guru        { shift->_execute('devops-guru', @_) }
sub directconnect      { shift->_execute('directconnect', @_) }
sub discovery          { shift->_execute('discovery', @_) }
sub dlm                { shift->_execute('dlm', @_) }
sub dms                { shift->_execute('dms', @_) }
sub docdb              { shift->_execute('docdb', @_) }
sub docdb_elastic      { shift->_execute('docdb-elastic', @_) }
sub drs                { shift->_execute('drs', @_) }
sub ds                 { shift->_execute('ds', @_) }
sub dynamodb           { shift->_execute('dynamodb', @_) }
sub dynamodbstreams    { shift->_execute('dynamodbstreams', @_) }
sub ebs                { shift->_execute('ebs', @_) }
sub ec2                { shift->_execute('ec2', @_) }
sub ec2_instance_connect { shift->_execute('ec2-instance-connect', @_) }
sub ecr                { shift->_execute('ecr', @_) }
sub ecr_public         { shift->_execute('ecr-public', @_) }
sub ecs                { shift->_execute('ecs', @_) }
sub efs                { shift->_execute('efs', @_) }
sub eks                { shift->_execute('eks', @_) }
sub elastic_inference  { shift->_execute('elastic-inference', @_) }
sub elasticache        { shift->_execute('elasticache', @_) }
sub elasticbeanstalk   { shift->_execute('elasticbeanstalk', @_) }
sub elastictranscoder  { shift->_execute('elastictranscoder', @_) }
sub elb                { shift->_execute('elb', @_) }
sub elbv2              { shift->_execute('elbv2', @_) }
sub emr                { shift->_execute('emr', @_) }
sub emr_containers     { shift->_execute('emr-containers', @_) }
sub emr_serverless     { shift->_execute('emr-serverless', @_) }
sub es                 { shift->_execute('es', @_) }
sub events             { shift->_execute('events', @_) }
sub evidently          { shift->_execute('evidently', @_) }
sub finspace           { shift->_execute('finspace', @_) }
sub finspace_data      { shift->_execute('finspace-data', @_) }
sub firehose           { shift->_execute('firehose', @_) }
sub fis                { shift->_execute('fis', @_) }
sub fms                { shift->_execute('fms', @_) }
sub forecast           { shift->_execute('forecast', @_) }
sub forecastquery      { shift->_execute('forecastquery', @_) }
sub frauddetector      { shift->_execute('frauddetector', @_) }
sub fsx                { shift->_execute('fsx', @_) }
sub gamelift           { shift->_execute('gamelift', @_) }
sub gamesparks         { shift->_execute('gamesparks', @_) }
sub glacier            { shift->_execute('glacier', @_) }
sub globalaccelerator  { shift->_execute('globalaccelerator', @_) }
sub glue               { shift->_execute('glue', @_) }
sub grafana            { shift->_execute('grafana', @_) }
sub greengrass         { shift->_execute('greengrass', @_) }
sub greengrassv2       { shift->_execute('greengrassv2', @_) }
sub groundstation      { shift->_execute('groundstation', @_) }
sub guardduty          { shift->_execute('guardduty', @_) }
sub health             { shift->_execute('health', @_) }
sub healthlake         { shift->_execute('healthlake', @_) }
sub history            { shift->_execute('history', @_) }
sub honeycode          { shift->_execute('honeycode', @_) }
sub iam                { shift->_execute('iam', @_) }
sub identitystore      { shift->_execute('identitystore', @_) }
sub imagebuilder       { shift->_execute('imagebuilder', @_) }
sub importexport       { shift->_execute('importexport', @_) }
sub inspector          { shift->_execute('inspector', @_) }
sub inspector2         { shift->_execute('inspector2', @_) }
sub internetmonitor    { shift->_execute('internetmonitor', @_) }
sub iot                { shift->_execute('iot', @_) }
sub iot_data           { shift->_execute('iot-data', @_) }
sub iot_jobs_data      { shift->_execute('iot-jobs-data', @_) }
sub iot_roborunner     { shift->_execute('iot-roborunner', @_) }
sub iot1click_devices  { shift->_execute('iot1click-devices', @_) }
sub iot1click_projects { shift->_execute('iot1click-projects', @_) }
sub iotanalytics       { shift->_execute('iotanalytics', @_) }
sub iotdeviceadvisor   { shift->_execute('iotdeviceadvisor', @_) }
sub iotevents          { shift->_execute('iotevents', @_) }
sub iotevents_data     { shift->_execute('iotevents-data', @_) }
sub iotfleethub        { shift->_execute('iotfleethub', @_) }
sub iotfleetwise       { shift->_execute('iotfleetwise', @_) }
sub iotsecuretunneling { shift->_execute('iotsecuretunneling', @_) }
sub iotsitewise        { shift->_execute('iotsitewise', @_) }
sub iotthingsgraph     { shift->_execute('iotthingsgraph', @_) }
sub iottwinmaker       { shift->_execute('iottwinmaker', @_) }
sub iotwireless        { shift->_execute('iotwireless', @_) }
sub ivs                { shift->_execute('ivs', @_) }
sub ivschat            { shift->_execute('ivschat', @_) }
sub kafka              { shift->_execute('kafka', @_) }
sub kafkaconnect       { shift->_execute('kafkaconnect', @_) }
sub kendra             { shift->_execute('kendra', @_) }
sub kendra_ranking     { shift->_execute('kendra-ranking', @_) }
sub keyspaces          { shift->_execute('keyspaces', @_) }
sub kinesis            { shift->_execute('kinesis', @_) }
sub kinesis_video_archived_media { shift->_execute('kinesis-video-archived-media', @_) }
sub kinesis_video_media { shift->_execute('kinesis-video-media', @_) }
sub kinesis_video_signaling { shift->_execute('kinesis-video-signaling', @_) }
sub kinesis_video_webrtc_storage { shift->_execute('kinesis-video-webrtc-storage', @_) }
sub kinesisanalytics   { shift->_execute('kinesisanalytics', @_) }
sub kinesisanalyticsv2 { shift->_execute('kinesisanalyticsv2', @_) }
sub kinesisvideo       { shift->_execute('kinesisvideo', @_) }
sub kms                { shift->_execute('kms', @_) }
sub lakeformation      { shift->_execute('lakeformation', @_) }
sub lambda             { shift->_execute('lambda', @_) }
sub lex_models         { shift->_execute('lex-models', @_) }
sub lex_runtime        { shift->_execute('lex-runtime', @_) }
sub lexv2_models       { shift->_execute('lexv2-models', @_) }
sub lexv2_runtime      { shift->_execute('lexv2-runtime', @_) }
sub license_manager    { shift->_execute('license-manager', @_) }
sub license_manager_linux_subscriptions { shift->_execute('license-manager-linux-subscriptions', @_) }
sub license_manager_user_subscriptions { shift->_execute('license-manager-user-subscriptions', @_) }
sub lightsail          { shift->_execute('lightsail', @_) }
sub location           { shift->_execute('location', @_) }
sub logs               { shift->_execute('logs', @_) }
sub lookoutequipment   { shift->_execute('lookoutequipment', @_) }
sub lookoutmetrics     { shift->_execute('lookoutmetrics', @_) }
sub lookoutvision      { shift->_execute('lookoutvision', @_) }
sub m2                 { shift->_execute('m2', @_) }
sub machinelearning    { shift->_execute('machinelearning', @_) }
sub macie              { shift->_execute('macie', @_) }
sub macie2             { shift->_execute('macie2', @_) }
sub managedblockchain  { shift->_execute('managedblockchain', @_) }
sub marketplace_catalog { shift->_execute('marketplace-catalog', @_) }
sub marketplace_entitlement { shift->_execute('marketplace-entitlement', @_) }
sub marketplacecommerceanalytics { shift->_execute('marketplacecommerceanalytics', @_) }
sub mediaconnect       { shift->_execute('mediaconnect', @_) }
sub mediaconvert       { shift->_execute('mediaconvert', @_) }
sub medialive          { shift->_execute('medialive', @_) }
sub mediapackage       { shift->_execute('mediapackage', @_) }
sub mediapackage_vod   { shift->_execute('mediapackage-vod', @_) }
sub mediastore         { shift->_execute('mediastore', @_) }
sub mediastore_data    { shift->_execute('mediastore-data', @_) }
sub mediatailor        { shift->_execute('mediatailor', @_) }
sub memorydb           { shift->_execute('memorydb', @_) }
sub meteringmarketplace { shift->_execute('meteringmarketplace', @_) }
sub mgh                { shift->_execute('mgh', @_) }
sub mgn                { shift->_execute('mgn', @_) }
sub migration_hub_refactor_spaces { shift->_execute('migration-hub-refactor-spaces', @_) }
sub migrationhub_config { shift->_execute('migrationhub-config', @_) }
sub migrationhuborchestrator { shift->_execute('migrationhuborchestrator', @_) }
sub migrationhubstrategy { shift->_execute('migrationhubstrategy', @_) }
sub mobile             { shift->_execute('mobile', @_) }
sub mq                 { shift->_execute('mq', @_) }
sub mturk              { shift->_execute('mturk', @_) }
sub mwaa               { shift->_execute('mwaa', @_) }
sub neptune            { shift->_execute('neptune', @_) }
sub network_firewall   { shift->_execute('network-firewall', @_) }
sub networkmanager     { shift->_execute('networkmanager', @_) }
sub nimble             { shift->_execute('nimble', @_) }
sub oam                { shift->_execute('oam', @_) }
sub omics              { shift->_execute('omics', @_) }
sub opensearch         { shift->_execute('opensearch', @_) }
sub opensearchserverless { shift->_execute('opensearchserverless', @_) }
sub opsworks           { shift->_execute('opsworks', @_) }
sub opsworks_cm        { shift->_execute('opsworks-cm', @_) }
sub organizations      { shift->_execute('organizations', @_) }
sub outposts           { shift->_execute('outposts', @_) }
sub panorama           { shift->_execute('panorama', @_) }
sub personalize        { shift->_execute('personalize', @_) }
sub personalize_events { shift->_execute('personalize-events', @_) }
sub personalize_runtime { shift->_execute('personalize-runtime', @_) }
sub pi                 { shift->_execute('pi', @_) }
sub pinpoint           { shift->_execute('pinpoint', @_) }
sub pinpoint_email     { shift->_execute('pinpoint-email', @_) }
sub pinpoint_sms_voice { shift->_execute('pinpoint-sms-voice', @_) }
sub pinpoint_sms_voice_v2 { shift->_execute('pinpoint-sms-voice-v2', @_) }
sub pipes              { shift->_execute('pipes', @_) }
sub polly              { shift->_execute('polly', @_) }
sub pricing            { shift->_execute('pricing', @_) }
sub privatenetworks    { shift->_execute('privatenetworks', @_) }
sub proton             { shift->_execute('proton', @_) }
sub qldb               { shift->_execute('qldb', @_) }
sub qldb_session       { shift->_execute('qldb-session', @_) }
sub quicksight         { shift->_execute('quicksight', @_) }
sub ram                { shift->_execute('ram', @_) }
sub rbin               { shift->_execute('rbin', @_) }
sub rds                { shift->_execute('rds', @_) }
sub rds_data           { shift->_execute('rds-data', @_) }
sub redshift           { shift->_execute('redshift', @_) }
sub redshift_data      { shift->_execute('redshift-data', @_) }
sub redshift_serverless { shift->_execute('redshift-serverless', @_) }
sub rekognition        { shift->_execute('rekognition', @_) }
sub resiliencehub      { shift->_execute('resiliencehub', @_) }
sub resource_explorer_2 { shift->_execute('resource-explorer-2', @_) }
sub resource_groups    { shift->_execute('resource-groups', @_) }
sub resourcegroupstaggingapi { shift->_execute('resourcegroupstaggingapi', @_) }
sub robomaker          { shift->_execute('robomaker', @_) }
sub rolesanywhere      { shift->_execute('rolesanywhere', @_) }
sub route53            { shift->_execute('route53', @_) }
sub route53_recovery_cluster { shift->_execute('route53-recovery-cluster', @_) }
sub route53_recovery_control_config { shift->_execute('route53-recovery-control-config', @_) }
sub route53_recovery_readiness { shift->_execute('route53-recovery-readiness', @_) }
sub route53domains     { shift->_execute('route53domains', @_) }
sub route53resolver    { shift->_execute('route53resolver', @_) }
sub rum                { shift->_execute('rum', @_) }
sub s3                 { shift->_execute('s3', @_) }
sub s3api              { shift->_execute('s3api', @_) }
sub s3control          { shift->_execute('s3control', @_) }
sub s3outposts         { shift->_execute('s3outposts', @_) }
sub sagemaker          { shift->_execute('sagemaker', @_) }
sub sagemaker_a2i_runtime { shift->_execute('sagemaker-a2i-runtime', @_) }
sub sagemaker_edge     { shift->_execute('sagemaker-edge', @_) }
sub sagemaker_featurestore_runtime { shift->_execute('sagemaker-featurestore-runtime', @_) }
sub sagemaker_geospatial { shift->_execute('sagemaker-geospatial', @_) }
sub sagemaker_metrics  { shift->_execute('sagemaker-metrics', @_) }
sub sagemaker_runtime  { shift->_execute('sagemaker-runtime', @_) }
sub savingsplans       { shift->_execute('savingsplans', @_) }
sub scheduler          { shift->_execute('scheduler', @_) }
sub schemas            { shift->_execute('schemas', @_) }
sub sdb                { shift->_execute('sdb', @_) }
sub secretsmanager     { shift->_execute('secretsmanager', @_) }
sub securityhub        { shift->_execute('securityhub', @_) }
sub securitylake       { shift->_execute('securitylake', @_) }
sub serverlessrepo     { shift->_execute('serverlessrepo', @_) }
sub service_quotas     { shift->_execute('service-quotas', @_) }
sub servicecatalog     { shift->_execute('servicecatalog', @_) }
sub servicecatalog_appregistry { shift->_execute('servicecatalog-appregistry', @_) }
sub servicediscovery   { shift->_execute('servicediscovery', @_) }
sub ses                { shift->_execute('ses', @_) }
sub sesv2              { shift->_execute('sesv2', @_) }
sub shield             { shift->_execute('shield', @_) }
sub signer             { shift->_execute('signer', @_) }
sub simspaceweaver     { shift->_execute('simspaceweaver', @_) }
sub sms                { shift->_execute('sms', @_) }
sub snow_device_management { shift->_execute('snow-device-management', @_) }
sub snowball           { shift->_execute('snowball', @_) }
sub sns                { shift->_execute('sns', @_) }
sub sqs                { shift->_execute('sqs', @_) }
sub ssm                { shift->_execute('ssm', @_) }
sub ssm_contacts       { shift->_execute('ssm-contacts', @_) }
sub ssm_incidents      { shift->_execute('ssm-incidents', @_) }
sub ssm_sap            { shift->_execute('ssm-sap', @_) }
sub sso                { shift->_execute('sso', @_) }
sub sso_admin          { shift->_execute('sso-admin', @_) }
sub sso_oidc           { shift->_execute('sso-oidc', @_) }
sub stepfunctions      { shift->_execute('stepfunctions', @_) }
sub storagegateway     { shift->_execute('storagegateway', @_) }
sub sts                { shift->_execute('sts', @_) }
sub support            { shift->_execute('support', @_) }
sub support_app        { shift->_execute('support-app', @_) }
sub swf                { shift->_execute('swf', @_) }
sub synthetics         { shift->_execute('synthetics', @_) }
sub textract           { shift->_execute('textract', @_) }
sub timestream_query   { shift->_execute('timestream-query', @_) }
sub timestream_write   { shift->_execute('timestream-write', @_) }
sub tnb                { shift->_execute('tnb', @_) }
sub transcribe         { shift->_execute('transcribe', @_) }
sub transfer           { shift->_execute('transfer', @_) }
sub translate          { shift->_execute('translate', @_) }
sub voice_id           { shift->_execute('voice-id', @_) }
sub waf                { shift->_execute('waf', @_) }
sub waf_regional       { shift->_execute('waf-regional', @_) }
sub wafv2              { shift->_execute('wafv2', @_) }
sub wellarchitected    { shift->_execute('wellarchitected', @_) }
sub wisdom             { shift->_execute('wisdom', @_) }
sub workdocs           { shift->_execute('workdocs', @_) }
sub worklink           { shift->_execute('worklink', @_) }
sub workmail           { shift->_execute('workmail', @_) }
sub workmailmessageflow { shift->_execute('workmailmessageflow', @_) }
sub workspaces         { shift->_execute('workspaces', @_) }
sub workspaces_web     { shift->_execute('workspaces-web', @_) }
sub xray               { shift->_execute('xray', @_) }

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

Constructor of AWS::CLIWrapper. Acceptable AWS CLI params are:

    region       region_name:Str
    profile      profile_name:Str
    endpoint_url endpoint_url:Str

Additionally, the these params can be used to control the wrapper behavior:

    nofork                  Truthy to avoid forking when executing `aws`
    timeout                 `aws` execution timeout
    croak_on_error          Truthy to croak() with the error message when `aws`
                            exits with non-zero code
    catch_error_pattern     Regexp pattern to match for error handling.
    catch_error_retries     Retries for handling errors.
    catch_error_min_delay   Minimal delay before retrying `aws` call
                            when an error was caught.
    catch_error_max_delay   Maximal delay before retrying `aws` call.

See below for more detailed explanation.

=item B<accessanalyzer>($operation:Str, $param:HashRef, %opt:Hash)

=item B<account>($operation:Str, $param:HashRef, %opt:Hash)

=item B<acm>($operation:Str, $param:HashRef, %opt:Hash)

=item B<acm_pca>($operation:Str, $param:HashRef, %opt:Hash)

=item B<alexaforbusiness>($operation:Str, $param:HashRef, %opt:Hash)

=item B<amp>($operation:Str, $param:HashRef, %opt:Hash)

=item B<amplify>($operation:Str, $param:HashRef, %opt:Hash)

=item B<amplifybackend>($operation:Str, $param:HashRef, %opt:Hash)

=item B<amplifyuibuilder>($operation:Str, $param:HashRef, %opt:Hash)

=item B<apigateway>($operation:Str, $param:HashRef, %opt:Hash)

=item B<apigatewaymanagementapi>($operation:Str, $param:HashRef, %opt:Hash)

=item B<apigatewayv2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<appconfig>($operation:Str, $param:HashRef, %opt:Hash)

=item B<appconfigdata>($operation:Str, $param:HashRef, %opt:Hash)

=item B<appflow>($operation:Str, $param:HashRef, %opt:Hash)

=item B<appintegrations>($operation:Str, $param:HashRef, %opt:Hash)

=item B<application_autoscaling>($operation:Str, $param:HashRef, %opt:Hash)

=item B<application_insights>($operation:Str, $param:HashRef, %opt:Hash)

=item B<applicationcostprofiler>($operation:Str, $param:HashRef, %opt:Hash)

=item B<appmesh>($operation:Str, $param:HashRef, %opt:Hash)

=item B<apprunner>($operation:Str, $param:HashRef, %opt:Hash)

=item B<appstream>($operation:Str, $param:HashRef, %opt:Hash)

=item B<appsync>($operation:Str, $param:HashRef, %opt:Hash)

=item B<arc_zonal_shift>($operation:Str, $param:HashRef, %opt:Hash)

=item B<athena>($operation:Str, $param:HashRef, %opt:Hash)

=item B<auditmanager>($operation:Str, $param:HashRef, %opt:Hash)

=item B<autoscaling>($operation:Str, $param:HashRef, %opt:Hash)

=item B<autoscaling_plans>($operation:Str, $param:HashRef, %opt:Hash)

=item B<backup>($operation:Str, $param:HashRef, %opt:Hash)

=item B<backup_gateway>($operation:Str, $param:HashRef, %opt:Hash)

=item B<backupstorage>($operation:Str, $param:HashRef, %opt:Hash)

=item B<batch>($operation:Str, $param:HashRef, %opt:Hash)

=item B<billingconductor>($operation:Str, $param:HashRef, %opt:Hash)

=item B<braket>($operation:Str, $param:HashRef, %opt:Hash)

=item B<budgets>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ce>($operation:Str, $param:HashRef, %opt:Hash)

=item B<chime>($operation:Str, $param:HashRef, %opt:Hash)

=item B<chime_sdk_identity>($operation:Str, $param:HashRef, %opt:Hash)

=item B<chime_sdk_media_pipelines>($operation:Str, $param:HashRef, %opt:Hash)

=item B<chime_sdk_meetings>($operation:Str, $param:HashRef, %opt:Hash)

=item B<chime_sdk_messaging>($operation:Str, $param:HashRef, %opt:Hash)

=item B<chime_sdk_voice>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cleanrooms>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloud9>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudcontrol>($operation:Str, $param:HashRef, %opt:Hash)

=item B<clouddirectory>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudformation>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudfront>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudhsm>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudhsmv2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudsearch>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudsearchdomain>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudtrail>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudtrail_data>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cloudwatch>($operation:Str, $param:HashRef, %opt:Hash)

=item B<codeartifact>($operation:Str, $param:HashRef, %opt:Hash)

=item B<codebuild>($operation:Str, $param:HashRef, %opt:Hash)

=item B<codecatalyst>($operation:Str, $param:HashRef, %opt:Hash)

=item B<codecommit>($operation:Str, $param:HashRef, %opt:Hash)

=item B<codeguru_reviewer>($operation:Str, $param:HashRef, %opt:Hash)

=item B<codeguruprofiler>($operation:Str, $param:HashRef, %opt:Hash)

=item B<codepipeline>($operation:Str, $param:HashRef, %opt:Hash)

=item B<codestar>($operation:Str, $param:HashRef, %opt:Hash)

=item B<codestar_connections>($operation:Str, $param:HashRef, %opt:Hash)

=item B<codestar_notifications>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cognito_identity>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cognito_idp>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cognito_sync>($operation:Str, $param:HashRef, %opt:Hash)

=item B<comprehend>($operation:Str, $param:HashRef, %opt:Hash)

=item B<comprehendmedical>($operation:Str, $param:HashRef, %opt:Hash)

=item B<compute_optimizer>($operation:Str, $param:HashRef, %opt:Hash)

=item B<configservice>($operation:Str, $param:HashRef, %opt:Hash)

=item B<configure>($operation:Str, $param:HashRef, %opt:Hash)

=item B<connect>($operation:Str, $param:HashRef, %opt:Hash)

=item B<connect_contact_lens>($operation:Str, $param:HashRef, %opt:Hash)

=item B<connectcampaigns>($operation:Str, $param:HashRef, %opt:Hash)

=item B<connectcases>($operation:Str, $param:HashRef, %opt:Hash)

=item B<connectparticipant>($operation:Str, $param:HashRef, %opt:Hash)

=item B<controltower>($operation:Str, $param:HashRef, %opt:Hash)

=item B<cur>($operation:Str, $param:HashRef, %opt:Hash)

=item B<customer_profiles>($operation:Str, $param:HashRef, %opt:Hash)

=item B<databrew>($operation:Str, $param:HashRef, %opt:Hash)

=item B<dataexchange>($operation:Str, $param:HashRef, %opt:Hash)

=item B<datapipeline>($operation:Str, $param:HashRef, %opt:Hash)

=item B<datasync>($operation:Str, $param:HashRef, %opt:Hash)

=item B<dax>($operation:Str, $param:HashRef, %opt:Hash)

=item B<deploy>($operation:Str, $param:HashRef, %opt:Hash)

=item B<detective>($operation:Str, $param:HashRef, %opt:Hash)

=item B<devicefarm>($operation:Str, $param:HashRef, %opt:Hash)

=item B<devops_guru>($operation:Str, $param:HashRef, %opt:Hash)

=item B<directconnect>($operation:Str, $param:HashRef, %opt:Hash)

=item B<discovery>($operation:Str, $param:HashRef, %opt:Hash)

=item B<dlm>($operation:Str, $param:HashRef, %opt:Hash)

=item B<dms>($operation:Str, $param:HashRef, %opt:Hash)

=item B<docdb>($operation:Str, $param:HashRef, %opt:Hash)

=item B<docdb_elastic>($operation:Str, $param:HashRef, %opt:Hash)

=item B<drs>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ds>($operation:Str, $param:HashRef, %opt:Hash)

=item B<dynamodb>($operation:Str, $param:HashRef, %opt:Hash)

=item B<dynamodbstreams>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ebs>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ec2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ec2_instance_connect>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ecr>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ecr_public>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ecs>($operation:Str, $param:HashRef, %opt:Hash)

=item B<efs>($operation:Str, $param:HashRef, %opt:Hash)

=item B<eks>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elastic_inference>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elasticache>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elasticbeanstalk>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elastictranscoder>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elb>($operation:Str, $param:HashRef, %opt:Hash)

=item B<elbv2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<emr>($operation:Str, $param:HashRef, %opt:Hash)

=item B<emr_containers>($operation:Str, $param:HashRef, %opt:Hash)

=item B<emr_serverless>($operation:Str, $param:HashRef, %opt:Hash)

=item B<es>($operation:Str, $param:HashRef, %opt:Hash)

=item B<events>($operation:Str, $param:HashRef, %opt:Hash)

=item B<evidently>($operation:Str, $param:HashRef, %opt:Hash)

=item B<finspace>($operation:Str, $param:HashRef, %opt:Hash)

=item B<finspace_data>($operation:Str, $param:HashRef, %opt:Hash)

=item B<firehose>($operation:Str, $param:HashRef, %opt:Hash)

=item B<fis>($operation:Str, $param:HashRef, %opt:Hash)

=item B<fms>($operation:Str, $param:HashRef, %opt:Hash)

=item B<forecast>($operation:Str, $param:HashRef, %opt:Hash)

=item B<forecastquery>($operation:Str, $param:HashRef, %opt:Hash)

=item B<frauddetector>($operation:Str, $param:HashRef, %opt:Hash)

=item B<fsx>($operation:Str, $param:HashRef, %opt:Hash)

=item B<gamelift>($operation:Str, $param:HashRef, %opt:Hash)

=item B<gamesparks>($operation:Str, $param:HashRef, %opt:Hash)

=item B<glacier>($operation:Str, $param:HashRef, %opt:Hash)

=item B<globalaccelerator>($operation:Str, $param:HashRef, %opt:Hash)

=item B<glue>($operation:Str, $param:HashRef, %opt:Hash)

=item B<grafana>($operation:Str, $param:HashRef, %opt:Hash)

=item B<greengrass>($operation:Str, $param:HashRef, %opt:Hash)

=item B<greengrassv2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<groundstation>($operation:Str, $param:HashRef, %opt:Hash)

=item B<guardduty>($operation:Str, $param:HashRef, %opt:Hash)

=item B<health>($operation:Str, $param:HashRef, %opt:Hash)

=item B<healthlake>($operation:Str, $param:HashRef, %opt:Hash)

=item B<history>($operation:Str, $param:HashRef, %opt:Hash)

=item B<honeycode>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iam>($operation:Str, $param:HashRef, %opt:Hash)

=item B<identitystore>($operation:Str, $param:HashRef, %opt:Hash)

=item B<imagebuilder>($operation:Str, $param:HashRef, %opt:Hash)

=item B<importexport>($operation:Str, $param:HashRef, %opt:Hash)

=item B<inspector>($operation:Str, $param:HashRef, %opt:Hash)

=item B<inspector2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<internetmonitor>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iot>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iot_data>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iot_jobs_data>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iot_roborunner>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iot1click_devices>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iot1click_projects>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iotanalytics>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iotdeviceadvisor>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iotevents>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iotevents_data>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iotfleethub>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iotfleetwise>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iotsecuretunneling>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iotsitewise>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iotthingsgraph>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iottwinmaker>($operation:Str, $param:HashRef, %opt:Hash)

=item B<iotwireless>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ivs>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ivschat>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kafka>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kafkaconnect>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kendra>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kendra_ranking>($operation:Str, $param:HashRef, %opt:Hash)

=item B<keyspaces>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kinesis>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kinesis_video_archived_media>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kinesis_video_media>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kinesis_video_signaling>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kinesis_video_webrtc_storage>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kinesisanalytics>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kinesisanalyticsv2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kinesisvideo>($operation:Str, $param:HashRef, %opt:Hash)

=item B<kms>($operation:Str, $param:HashRef, %opt:Hash)

=item B<lakeformation>($operation:Str, $param:HashRef, %opt:Hash)

=item B<lambda>($operation:Str, $param:HashRef, %opt:Hash)

=item B<lex_models>($operation:Str, $param:HashRef, %opt:Hash)

=item B<lex_runtime>($operation:Str, $param:HashRef, %opt:Hash)

=item B<lexv2_models>($operation:Str, $param:HashRef, %opt:Hash)

=item B<lexv2_runtime>($operation:Str, $param:HashRef, %opt:Hash)

=item B<license_manager>($operation:Str, $param:HashRef, %opt:Hash)

=item B<license_manager_linux_subscriptions>($operation:Str, $param:HashRef, %opt:Hash)

=item B<license_manager_user_subscriptions>($operation:Str, $param:HashRef, %opt:Hash)

=item B<lightsail>($operation:Str, $param:HashRef, %opt:Hash)

=item B<location>($operation:Str, $param:HashRef, %opt:Hash)

=item B<logs>($operation:Str, $param:HashRef, %opt:Hash)

=item B<lookoutequipment>($operation:Str, $param:HashRef, %opt:Hash)

=item B<lookoutmetrics>($operation:Str, $param:HashRef, %opt:Hash)

=item B<lookoutvision>($operation:Str, $param:HashRef, %opt:Hash)

=item B<m2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<machinelearning>($operation:Str, $param:HashRef, %opt:Hash)

=item B<macie>($operation:Str, $param:HashRef, %opt:Hash)

=item B<macie2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<managedblockchain>($operation:Str, $param:HashRef, %opt:Hash)

=item B<marketplace_catalog>($operation:Str, $param:HashRef, %opt:Hash)

=item B<marketplace_entitlement>($operation:Str, $param:HashRef, %opt:Hash)

=item B<marketplacecommerceanalytics>($operation:Str, $param:HashRef, %opt:Hash)

=item B<mediaconnect>($operation:Str, $param:HashRef, %opt:Hash)

=item B<mediaconvert>($operation:Str, $param:HashRef, %opt:Hash)

=item B<medialive>($operation:Str, $param:HashRef, %opt:Hash)

=item B<mediapackage>($operation:Str, $param:HashRef, %opt:Hash)

=item B<mediapackage_vod>($operation:Str, $param:HashRef, %opt:Hash)

=item B<mediastore>($operation:Str, $param:HashRef, %opt:Hash)

=item B<mediastore_data>($operation:Str, $param:HashRef, %opt:Hash)

=item B<mediatailor>($operation:Str, $param:HashRef, %opt:Hash)

=item B<memorydb>($operation:Str, $param:HashRef, %opt:Hash)

=item B<meteringmarketplace>($operation:Str, $param:HashRef, %opt:Hash)

=item B<mgh>($operation:Str, $param:HashRef, %opt:Hash)

=item B<mgn>($operation:Str, $param:HashRef, %opt:Hash)

=item B<migration_hub_refactor_spaces>($operation:Str, $param:HashRef, %opt:Hash)

=item B<migrationhub_config>($operation:Str, $param:HashRef, %opt:Hash)

=item B<migrationhuborchestrator>($operation:Str, $param:HashRef, %opt:Hash)

=item B<migrationhubstrategy>($operation:Str, $param:HashRef, %opt:Hash)

=item B<mobile>($operation:Str, $param:HashRef, %opt:Hash)

=item B<mq>($operation:Str, $param:HashRef, %opt:Hash)

=item B<mturk>($operation:Str, $param:HashRef, %opt:Hash)

=item B<mwaa>($operation:Str, $param:HashRef, %opt:Hash)

=item B<neptune>($operation:Str, $param:HashRef, %opt:Hash)

=item B<network_firewall>($operation:Str, $param:HashRef, %opt:Hash)

=item B<networkmanager>($operation:Str, $param:HashRef, %opt:Hash)

=item B<nimble>($operation:Str, $param:HashRef, %opt:Hash)

=item B<oam>($operation:Str, $param:HashRef, %opt:Hash)

=item B<omics>($operation:Str, $param:HashRef, %opt:Hash)

=item B<opensearch>($operation:Str, $param:HashRef, %opt:Hash)

=item B<opensearchserverless>($operation:Str, $param:HashRef, %opt:Hash)

=item B<opsworks>($operation:Str, $param:HashRef, %opt:Hash)

=item B<opsworks_cm>($operation:Str, $param:HashRef, %opt:Hash)

=item B<organizations>($operation:Str, $param:HashRef, %opt:Hash)

=item B<outposts>($operation:Str, $param:HashRef, %opt:Hash)

=item B<panorama>($operation:Str, $param:HashRef, %opt:Hash)

=item B<personalize>($operation:Str, $param:HashRef, %opt:Hash)

=item B<personalize_events>($operation:Str, $param:HashRef, %opt:Hash)

=item B<personalize_runtime>($operation:Str, $param:HashRef, %opt:Hash)

=item B<pi>($operation:Str, $param:HashRef, %opt:Hash)

=item B<pinpoint>($operation:Str, $param:HashRef, %opt:Hash)

=item B<pinpoint_email>($operation:Str, $param:HashRef, %opt:Hash)

=item B<pinpoint_sms_voice>($operation:Str, $param:HashRef, %opt:Hash)

=item B<pinpoint_sms_voice_v2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<pipes>($operation:Str, $param:HashRef, %opt:Hash)

=item B<polly>($operation:Str, $param:HashRef, %opt:Hash)

=item B<pricing>($operation:Str, $param:HashRef, %opt:Hash)

=item B<privatenetworks>($operation:Str, $param:HashRef, %opt:Hash)

=item B<proton>($operation:Str, $param:HashRef, %opt:Hash)

=item B<qldb>($operation:Str, $param:HashRef, %opt:Hash)

=item B<qldb_session>($operation:Str, $param:HashRef, %opt:Hash)

=item B<quicksight>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ram>($operation:Str, $param:HashRef, %opt:Hash)

=item B<rbin>($operation:Str, $param:HashRef, %opt:Hash)

=item B<rds>($operation:Str, $param:HashRef, %opt:Hash)

=item B<rds_data>($operation:Str, $param:HashRef, %opt:Hash)

=item B<redshift>($operation:Str, $param:HashRef, %opt:Hash)

=item B<redshift_data>($operation:Str, $param:HashRef, %opt:Hash)

=item B<redshift_serverless>($operation:Str, $param:HashRef, %opt:Hash)

=item B<rekognition>($operation:Str, $param:HashRef, %opt:Hash)

=item B<resiliencehub>($operation:Str, $param:HashRef, %opt:Hash)

=item B<resource_explorer_2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<resource_groups>($operation:Str, $param:HashRef, %opt:Hash)

=item B<resourcegroupstaggingapi>($operation:Str, $param:HashRef, %opt:Hash)

=item B<robomaker>($operation:Str, $param:HashRef, %opt:Hash)

=item B<rolesanywhere>($operation:Str, $param:HashRef, %opt:Hash)

=item B<route53>($operation:Str, $param:HashRef, %opt:Hash)

=item B<route53_recovery_cluster>($operation:Str, $param:HashRef, %opt:Hash)

=item B<route53_recovery_control_config>($operation:Str, $param:HashRef, %opt:Hash)

=item B<route53_recovery_readiness>($operation:Str, $param:HashRef, %opt:Hash)

=item B<route53domains>($operation:Str, $param:HashRef, %opt:Hash)

=item B<route53resolver>($operation:Str, $param:HashRef, %opt:Hash)

=item B<rum>($operation:Str, $param:HashRef, %opt:Hash)

=item B<s3>($operation:Str, $path:ArrayRef, $param:HashRef, %opt:Hash)

=item B<s3api>($operation:Str, $param:HashRef, %opt:Hash)

=item B<s3control>($operation:Str, $param:HashRef, %opt:Hash)

=item B<s3outposts>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sagemaker>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sagemaker_a2i_runtime>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sagemaker_edge>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sagemaker_featurestore_runtime>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sagemaker_geospatial>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sagemaker_metrics>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sagemaker_runtime>($operation:Str, $param:HashRef, %opt:Hash)

=item B<savingsplans>($operation:Str, $param:HashRef, %opt:Hash)

=item B<scheduler>($operation:Str, $param:HashRef, %opt:Hash)

=item B<schemas>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sdb>($operation:Str, $param:HashRef, %opt:Hash)

=item B<secretsmanager>($operation:Str, $param:HashRef, %opt:Hash)

=item B<securityhub>($operation:Str, $param:HashRef, %opt:Hash)

=item B<securitylake>($operation:Str, $param:HashRef, %opt:Hash)

=item B<serverlessrepo>($operation:Str, $param:HashRef, %opt:Hash)

=item B<service_quotas>($operation:Str, $param:HashRef, %opt:Hash)

=item B<servicecatalog>($operation:Str, $param:HashRef, %opt:Hash)

=item B<servicecatalog_appregistry>($operation:Str, $param:HashRef, %opt:Hash)

=item B<servicediscovery>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ses>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sesv2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<shield>($operation:Str, $param:HashRef, %opt:Hash)

=item B<signer>($operation:Str, $param:HashRef, %opt:Hash)

=item B<simspaceweaver>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sms>($operation:Str, $param:HashRef, %opt:Hash)

=item B<snow_device_management>($operation:Str, $param:HashRef, %opt:Hash)

=item B<snowball>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sns>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sqs>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ssm>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ssm_contacts>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ssm_incidents>($operation:Str, $param:HashRef, %opt:Hash)

=item B<ssm_sap>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sso>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sso_admin>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sso_oidc>($operation:Str, $param:HashRef, %opt:Hash)

=item B<stepfunctions>($operation:Str, $param:HashRef, %opt:Hash)

=item B<storagegateway>($operation:Str, $param:HashRef, %opt:Hash)

=item B<sts>($operation:Str, $param:HashRef, %opt:Hash)

=item B<support>($operation:Str, $param:HashRef, %opt:Hash)

=item B<support_app>($operation:Str, $param:HashRef, %opt:Hash)

=item B<swf>($operation:Str, $param:HashRef, %opt:Hash)

=item B<synthetics>($operation:Str, $param:HashRef, %opt:Hash)

=item B<textract>($operation:Str, $param:HashRef, %opt:Hash)

=item B<timestream_query>($operation:Str, $param:HashRef, %opt:Hash)

=item B<timestream_write>($operation:Str, $param:HashRef, %opt:Hash)

=item B<tnb>($operation:Str, $param:HashRef, %opt:Hash)

=item B<transcribe>($operation:Str, $param:HashRef, %opt:Hash)

=item B<transfer>($operation:Str, $param:HashRef, %opt:Hash)

=item B<translate>($operation:Str, $param:HashRef, %opt:Hash)

=item B<voice_id>($operation:Str, $param:HashRef, %opt:Hash)

=item B<waf>($operation:Str, $param:HashRef, %opt:Hash)

=item B<waf_regional>($operation:Str, $param:HashRef, %opt:Hash)

=item B<wafv2>($operation:Str, $param:HashRef, %opt:Hash)

=item B<wellarchitected>($operation:Str, $param:HashRef, %opt:Hash)

=item B<wisdom>($operation:Str, $param:HashRef, %opt:Hash)

=item B<workdocs>($operation:Str, $param:HashRef, %opt:Hash)

=item B<worklink>($operation:Str, $param:HashRef, %opt:Hash)

=item B<workmail>($operation:Str, $param:HashRef, %opt:Hash)

=item B<workmailmessageflow>($operation:Str, $param:HashRef, %opt:Hash)

=item B<workspaces>($operation:Str, $param:HashRef, %opt:Hash)

=item B<workspaces_web>($operation:Str, $param:HashRef, %opt:Hash)

=item B<xray>($operation:Str, $param:HashRef, %opt:Hash)

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
    default is 30 seconds, unless overridden with AWS_CLIWRAPPER_TIMEOUT environment variable.

  nofork => Int (>0)
    Call IPC::Cmd::run vs. IPC::Cmd::run_forked (mostly useful if/when in perl debugger).  Note: 'timeout', if used with 'nofork', will merely cause an alarm and return.  ie. 'run' will NOT kill the awscli command like 'run_forked' will.

  croak_on_error => Int (>0)
    When set to a truthy value, this will make AWS::CLIWrapper to croak() with error message when `aws` command exits with non-zero status. Default behavior is to set $AWS::CLIWrapper::Error and return.

  catch_error_pattern => RegExp
    When defined, this option will enable catching `aws-cli` errors matching this pattern
    and retrying `aws-cli` command execution. Environment variable
    AWS_CLIWRAPPER_CATCH_ERROR_PATTERN takes precedence over this option, if both
    are defined.

    Default is undef.

  catch_error_retries => Int (>= 0)
    When defined, this option will set the number of retries to make when `aws-cli` error
    was caught with catch_error_pattern, before giving up. Environment variable
    AWS_CLIWRAPPER_CATCH_ERROR_RETRIES takes precedence over this option, if both
    are defined.

    0 (zero) retries is a valid way to turn off error catching via environment variable
    in certain scenarios. Negative values are invalid and will be reset to default.

    Default is 3.

  catch_error_min_delay => Int (>= 0)
    When defined, this option will set the minimum delay in seconds before attempting
    a retry of failed `aws-cli` execution when the error was caught. Environment variable
    AWS_CLIWRAPPER_CATCH_ERROR_MIN_DELAY takes precedence over this option, if both
    are defined.

    0 (zero) is a valid value. Negative values are invalid and will be reset to default.

    Default is 3.

  catch_error_max_delay => Int (>= 0)
    When defined, this option will set the maximum delay in seconds before attempting
    a retry of failed `aws-cli` execution. Environment variable AWS_CLIWRAPPER_CATCH_ERROR_MAX_DELAY
    takes precedence over this option, if both are defined.

    0 (zero) is a valid value. Negative values are invalid and will be reset to default.
    If catch_error_min_delay is greater than catch_error_max_delay, both are set
    to catch_error_min_delay value.

    Default is 10.

=back

=head1 ENVIRONMENT

=over 4

=item HOME: used by default by /usr/bin/aws utility to find it's credentials (if none are specified)

Special note: cron on Linux will often have a different HOME "/" instead of "/root" - set $ENV{'HOME'}
to use the default credentials or specify $ENV{'AWS_CONFIG_FILE'} directly.

=item AWS_CLIWRAPPER_TIMEOUT

If this variable is set, this value will be used instead of default timeout (30 seconds) for every
invocation of `aws-cli` that does not have a timeout value provided in the options argument of the
called function.

=item AWS_CLIWRAPPER_CATCH_ERROR_PATTERN

If this variable is set, AWS::CLIWrapper will retry `aws-cli` execution if stdout output
of failed `aws-cli` command matches the pattern. See L<ERROR HANDLING>.

=item AWS_CLIWRAPPER_CATCH_ERROR_RETRIES

How many times to retry command execution if an error was caught. Default is 3.

=item AWS_CLIWRAPPER_CATCH_ERROR_MIN_DELAY

Minimal delay before retrying command execution if an error was caught, in seconds.

Default is 3.

=item AWS_CLIWRAPPER_CATCH_ERROR_MAX_DELAY

Maximal delay before retrying command execution, in seconds. Default is 10.

=item AWS_CONFIG_FILE

=item AWS_ACCESS_KEY_ID

=item AWS_SECRET_ACCESS_KEY

=item AWS_DEFAULT_REGION

See documents of aws-cli.

=back

=head1 ERROR HANDLING

=over 4

By default, when `aws-cli` exits with an error code (> 0), AWS::CLIWrapper will set
the error code and message to $AWS::CLIWrapper::Error (and optionally croak), thus
relaying the error to calling code. While this approach is beneficial 99% of the time,
in some use cases `aws-cli` execution fails for a temporary reason unrelated to
both calling code and AWS::CLIWrapper, and can be safely retried after a short delay.

One of this use cases is executing `aws-cli` on AWS EC2 instances, where `aws-cli`
retrieves its configuration and credentials from the API exposed to the EC2 instance;
at certain times these credentials may be rotated and calling `aws-cli` at exactly
the right moment will cause it to fail with `Unable to locate credentials` error.

To prevent this kind of errors from failing the calling code, AWS::CLIWrapper allows
configuring an RegExp pattern and retry `aws-cli` execution if it fails with an error
matching the configured pattern.

The error catching pattern, as well as other configuration, can be defined either
as AWS::CLIWrapper options in the code, or as respective environment variables
(see L<ENVIRONMENT>).

The actual delay before retrying a failed `aws-cli` execution is computed as a
random value of seconds between catch_error_min_delay (default 3) and catch_error_max_delay
(default 10). Backoff is not supported at this moment.

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
