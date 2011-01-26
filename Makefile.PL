#!/usr/bin/env perl
use ExtUtils::MakeMaker;

use 5.008;

my $version = '0.11';

WriteMakefile
 ( NAME	 	=> 'IO::Mux'
 , VERSION	=> $version
 , PREREQ_PM    =>
    { Test::More => 0.80
    , IO::Socket => 1.18
    }
 , EXE_FILES    => []
 , AUTHOR       => 'Mark Overmeer'
 , ABSTRACT     => 'event driven programming'
 , LICENSE      => 'perl'
 );

### used by oodist during production of distribution
sub MY::postamble { <<'__POSTAMBLE' }

# for DIST
RAWDIR          = ../public_html/io-mux/raw
DISTDIR         = ../public_html/io-mux/source
LICENSE         = artistic

# for POD
FIRST_YEAR      = 2011
EMAIL           = perl@overmeer.net
WEBSITE         = http://perl.overmeer.net/

EXTENDS		= ../AnyDaemon:../MuxHTTP
PODTAIL		= ../daemon-shared-podtail
__POSTAMBLE
