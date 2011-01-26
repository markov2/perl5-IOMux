#!/usr/bin/env perl
use warnings;
use strict;

use Test::More tests => 16;

use lib 'lib', '../lib';

eval "require IO::Poll";
my $has_io_poll = $@ ? 0 : 1;

use_ok("IO::Mux::Handler");
use_ok("IO::Mux::Handler::Read");
use_ok("IO::Mux::Handler::Write");
use_ok("IO::Mux::Handler::Service");

use_ok("IO::Mux::File::Read");
use_ok("IO::Mux::File::Write");
use_ok("IO::Mux::Pipe::Write");
use_ok("IO::Mux::Pipe::Read");

use_ok("IO::Mux::Net::TCP");
use_ok("IO::Mux::Service::TCP");

use_ok("IO::Mux::Bundle");
use_ok("IO::Mux::IPC");

use_ok("IO::Mux");
use_ok("IO::Mux::Select");

if($has_io_poll)
{   use_ok("IO::Mux::Poll");
}
else
{   pass "IO::Poll is not installed (optional)";
}

use_ok("IO::Mux::Open");
