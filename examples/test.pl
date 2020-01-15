#!/usr/bin/env perl
# This script shows a complex cases, moving data around. To test
# whether various interfaces are working.

# Have a look at the daemon.pl scripts to see how to create a nice
# and maintainable daemon. The example below is just to demonstrate
# (and test) plugins.

# You may run the test with
#   ls | netcat localhost 5422 || echo 'not running'

use warnings;
use strict;

use Log::Report;
use Any::Daemon;

#use IOMux::Select;
use IOMux::Poll;
use IOMux::Socket::TCP;
use IOMux::Open  '>';

my $temp_file = '/tmp/test-iomux';
my $host_port = 'localhost:5422';

dispatcher SYSLOG => 'syslog', accept => 'INFO-'
  , identity => 'iomux', facility => 'local0';

dispatcher mode => 'VERBOSE', 'default';

my $daemon = Any::Daemon->new(pid_file => '');
$daemon->run
  ( child_task => \&run_multiplexer
  , background => 0
  , max_childs => 1
  );

exit 1;

#----------

my ($service, $filewrite);

sub run_multiplexer()
{
#   my $mux  = IOMux::Select->new;
    my $mux  = IOMux::Poll->new;

    $service = IOMux::Socket::TCP->new
      ( LocalAddr => $host_port
      , Listen    => 5
      , Proto     => 'tcp'

        # more options
      , name      => 'service'
      , conn_type => "My::Service"
      );
   $mux->add($service);

   my $filewrite = $mux->open('>', $temp_file);

   $mux->loop;
   exit 0;
}

package My::Service;
use base 'IOMux::Net::TCP';

sub mux_input($)
{   
}

1;
