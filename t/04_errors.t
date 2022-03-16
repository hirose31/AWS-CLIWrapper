use strict;
use Test::More tests => 4;

use AWS::CLIWrapper;

# Default error handling
my $aws = AWS::CLIWrapper->new;

my $res = $aws->elbv2();

is $res, undef, "default result is undefined";

# Is this a TODO?
is $AWS::CLIWrapper::Error->{Code}, "Unknown", "default error code match";

my $want_err_msg = qq!exited with code [252]
stderr:

usage: aws [options] <command> <subcommand> [<subcommand> ...] [parameters]
To see help text, you can run:

  aws help
  aws <command> help
  aws <command> <subcommand> help

aws: error: argument operation: Invalid choice, valid choices are:

add-listener-certificates                | add-tags                                
create-listener                          | create-load-balancer                    
create-rule                              | create-target-group                     
delete-listener                          | delete-load-balancer                    
delete-rule                              | delete-target-group                     
deregister-targets                       | describe-account-limits                 
describe-listener-certificates           | describe-listeners                      
describe-load-balancer-attributes        | describe-load-balancers                 
describe-rules                           | describe-ssl-policies                   
describe-tags                            | describe-target-group-attributes        
describe-target-groups                   | describe-target-health                  
modify-listener                          | modify-load-balancer-attributes         
modify-rule                              | modify-target-group                     
modify-target-group-attributes           | register-targets                        
remove-listener-certificates             | remove-tags                             
set-ip-address-type                      | set-rule-priorities                     
set-security-groups                      | set-subnets                             
wait                                     | help                                    


!;

is $AWS::CLIWrapper::Error->{Message}, $want_err_msg, "default error message match";

# Croaking
my $aws_croak = AWS::CLIWrapper->new(croak_on_error => 1);

eval {
    $aws_croak->elbv2();
};

is $@, "$want_err_msg at t/04_errors.t line 56.\n", "croak on error message match";
