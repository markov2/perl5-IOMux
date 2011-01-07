use warnings;
use strict;

package IO::Mux::Bundle;

use Log::Report 'io-mux';

##### WORK IN PROGRESS!

=chapter NAME
IO::Mux::Bundle - logical group of connections

=chapter SYNOPSIS
  my $syscall = IO::Mux::Bundle::Parallel->new(...);
  $mux->add($syscall);

=chapter DESCRIPTION
A bundle is a set of file handles, so a convenience wrapper around
a set of different connections.

=chapter METHODS

=section Constructors

=method new OPTIONS
=cut

sub new() {bless{},shift}

#---------------
=section Accessors
=method connections
Returns the connections which are part of this bundle.
=cut

sub connections() {shift->{IMB_conns}}

1;
