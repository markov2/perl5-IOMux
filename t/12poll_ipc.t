#!/usr/bin/env perl
use warnings;
use strict;

use lib "lib", "../lib";
use Test::More;
use File::Temp qw/mktemp/;

#use Log::Report mode => 3;  # debugging

BEGIN { eval "require IO::Poll";
        $@ and plan skip_all => "IO::Poll not installed";

        plan tests => 11;
      }

use_ok('IO::Mux::Poll');

my $mux = IO::Mux::Poll->new;
isa_ok($mux, 'IO::Mux::Poll');

my $tempfn = mktemp 'iomux-test.XXXXX';
ok(1, "tempfile = $tempfn");

sub check_write();
check_write;

$mux->loop;
ok(1, 'clean exit of mux');

exit 0;
#####

my $ipc;

sub check_write()
{   use_ok('IO::Mux::IPC');

    $ipc = IO::Mux::IPC->new(command => ['tee', $tempfn]);
    isa_ok($ipc, 'IO::Mux::IPC');
    $mux->add($ipc);

    $ipc->write(\"tic\ntac\n");
    $ipc->write(\"toe\n");

    $ipc->stdin->close(\&written);
}

sub written()
{   my $stdin = shift;

    sleep 1;   # tee is a bit slow writing the file, sometimes

    my $teed = '';
    if(open IN, '<', $tempfn)
    {    local $/;
         $teed = <IN>;
         close IN;
    }
    is($teed, "tic\ntac\ntoe\n", 'remote received all data');

    isa_ok($stdin, 'IO::Mux::Pipe::Write');
    is($stdin, $ipc->stdin);

#print $ipc->show;
    $ipc->slurp(\&slurped);
}

sub slurped($)
{   my ($stdout, $data) = @_;
    isa_ok($stdout, 'IO::Mux::Pipe::Read');
    is($$data, "tic\ntac\ntoe\n");
    $ipc->close;

    unlink $tempfn;
}
