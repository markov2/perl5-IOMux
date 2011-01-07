#!/usr/bin/env perl
use warnings;
use strict;

use Test::More tests => 9;

use_ok('IO::Mux');
use_ok('IO::Mux::Handler');
use_ok('IO::Mux::Socket');
use_ok('IO::Mux::Socket::TCP');
use_ok('IO::Mux::Connection');
use_ok('IO::Mux::Connection::TCP');
use_ok('IO::Mux::Bundle');
use_ok('IO::Mux::Select');
use_ok('IO::Mux::Poll');
