#!/usr/bin/env perl
use warnings;
use strict;

use lib "lib", "../lib";
use Test::More;
use File::Temp qw/mktemp/;

#use Log::Report mode => 3;  # debugging

sub check_write();

BEGIN { eval "require IO::Poll";
        $@ and plan skip_all => "IO::Poll not installed";

        plan tests => 21;
      }

use_ok('IO::Mux::Poll');

my $mux = IO::Mux::Poll->new;
isa_ok($mux, 'IO::Mux::Poll');

my $tempfn = mktemp 'iomux-test.XXXXX';
ok(1, "tempfile = $tempfn");
check_write;

$mux->loop;
ok(1, 'clean exit of mux');

unlink $tempfn;

exit 0;
#####

sub check_write()
{   use_ok('IO::Mux::File::Write');

    my $wr = IO::Mux::File::Write->new(file => $tempfn);

    isa_ok($wr, 'IO::Mux::File::Write');
    my $wr2 = $mux->add($wr);
    cmp_ok($wr, 'eq', $wr2);
    $wr->print("tic\n");
    $wr->print("tac\n");
    $wr->close(\&check_read);
}

sub check_read($)
{   my $wr = shift;
    isa_ok($wr, 'IO::Mux::File::Write');

    use_ok('IO::Mux::File::Read');
    my $rd = IO::Mux::File::Read->new(file => $tempfn);
    isa_ok($rd, 'IO::Mux::File::Read');

    my $rd2 = $mux->add($rd);
    cmp_ok($rd, 'eq', $rd2);

    $rd->slurp(\&check_read2);
}

sub check_read2($)
{   my ($rd, $bytes) = @_;
    isa_ok($rd, 'IO::Mux::File::Read');
    $rd->close;

    is(ref $bytes, 'SCALAR');
    is($$bytes, "tic\ntac\n");

    my $wr2 = IO::Mux::File::Write->new(file => $tempfn, append => 1);
    isa_ok($wr2, 'IO::Mux::File::Write');
    $mux->add($wr2);
    $wr2->print("toe\n");
    $wr2->close(\&check_write2);
}

sub check_write2()
{   my $wr2 = shift;
    isa_ok($wr2, 'IO::Mux::File::Write');
    $wr2->close;

    my $rd2 = IO::Mux::File::Read->new(file => $tempfn);
    isa_ok($rd2, 'IO::Mux::File::Read');
    $mux->add($rd2);
    $rd2->readline(\&check_read3);
}

sub check_read3($)
{   my ($rd2, $line) = @_;
    is($line, "tic\n", 'tic');
    $rd2->readline(\&check_read4);
}

sub check_read4($)
{   my ($rd2, $line) = @_;
    is($line, "tac\n", 'tac');
    $rd2->readline(\&check_read5);
}

sub check_read5($)
{   my ($rd2, $line) = @_;
    is($line, "toe\n", 'toe');
    $rd2->readline(\&check_read6);
}

sub check_read6($)
{   my ($rd2, $line) = @_;
    cmp_ok($line, 'eq', '', 'eof');
    $rd2->close;
}
