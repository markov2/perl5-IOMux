#!/usr/bin/env perl
# This script can be used as template for daemons using IO::Mux.
# The code is more verbose than needed in the common case.
#
# You may run the test with
#   ls | netcat localhost 5422 || echo 'not running'

use warnings;
use strict;

use Log::Report;
use Any::Daemon;

#use IO::Mux::Select;
use IO::Mux::Poll;
use IO::Mux::Socket::TCP;

use Getopt::Long   qw/GetOptions :config no_ignore_case bundling/;
use File::Basename qw/basename/;

#use IO::Socket::SSL; # when SSL is used anywhere

#
## get command-line options
#

my $mode     = 0;     # increase output

my %os_opts  =
  ( pid_file   => basename($0). '.pid'  # usually in /var/run
  , user       => undef
  , group      => undef
  );

my %run_opts =
  ( background => 1
  , max_childs => 1    # there can only be one multiplexer
  );

my %net_opts =
  ( host       => 'localhost:5422'
  , port       => undef
  );

GetOptions
   'background|bg!' => \$run_opts{background}
 , 'group|g=s'      => \$os_opts{group}
 , 'host|h=s'       => \$net_opts{host}
 , 'pid-file|p=s'   => \$os_opts{pid_file}
 , 'port|p=s'       => \$net_opts{port}
 , 'user|u=s'       => \$os_opts{user}
 , 'v+'             => \$mode  # -v -vv -vvv
    or exit 1;

$run_opts{background} //= 1;

unless(defined $net_opts{port})
{   my $port = $net_opts{port} = $1
        if $net_opts{host} =~ s/\:([0-9]+)$//;
    defined $port or error "no port specified";
}

#
## initialize the daemon activities
#

# From now on, all errors and warnings are also sent to syslog,
# provided by Log::Report. Output still also to the screen.
dispatcher SYSLOG => 'syslog', accept => 'INFO-'
  , identity => 'iomux', facility => 'local0';

dispatcher mode => $mode, 'ALL' if $mode;

my $daemon = Any::Daemon->new(%os_opts);

$daemon->run
  ( child_task => \&run_multiplexer
  , %run_opts
  );

exit 1;   # will never be called

sub run_multiplexer()
{
#   my $mux    = IO::Mux::Select->new;
    my $mux    = IO::Mux::Poll->new;

eval {
    # Create one or more listening TCP or UDP sockets.
    my $addr   = "$net_opts{host}:$net_opts{port}";
    my $server = IO::Mux::Socket::TCP->new
      ( # Options which start with Caps are for IO::Socket::INET/::SSL
        # you may also pass a prepared socket.
        LocalAddr => $addr
      , Listen    => 5
      , Proto     => 'tcp'
     #, use_ssl   => 1     # for SSL socket

        # more options
      , name      => 'echo'           # improves error msgs
      , conn_type => "IO::Mux::Echo"  # required, see below
      );
   $mux->add($server);

   $mux->loop(\&heartbeat);
};
info "EVAL: $@" if $@;
   exit 0;
}

##### HELPERS

# When added to the loop, it will be called each time the select has
# received something.
sub heartbeat($$$)
{   my ($mux, $numready, $timeleft) = @_;
#   info "*$numready $timeleft\n";
}

##### PROTOCOL HANDLER
# Simple echo service which puts back all data it received.
# Usually in a seperate file.

package IO::Mux::Echo;
use base 'IO::Mux::Net::TCP';

use warnings;
use strict;

sub mux_input($)
{   my ($self, $input) = @_;
    $self->write($input);     # write expects SCALAR
    $$input = '';             # all bytes processed
}

1;
