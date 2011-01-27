use warnings;
use strict;

package IOMux::Handler::Service;
use base 'IOMux::Handler';

use Log::Report       'iomux';

=chapter NAME
IOMux::Handler::Service - any mux service

=chapter SYNOPSIS
  # only use extensions

=chapter DESCRIPTION
This base-class defines what interface services provide. A service is
(in the general case) a socket which is listening to incoming connections)

=chapter METHODS

=section Multiplexer
=cut

sub mux_init($)
{   my ($self, $mux) = @_;
    $self->SUPER::mux_init($mux);
    $self->fdset(1, 1, 0, 0);  # 'read' new connections
}

sub mux_remove()
{   my $self = shift;
    $self->SUPER::mux_remove;
    $self->fdset(0, 1, 0, 0);
}

=subsection Service

=method mux_connection CLIENT
A new connection has arrived on the file-handle (socket) where we are
listening on. The connection has been accepted and the filehandle
of the new CLIENT has been added to the MUX. You may wish to send an
initial string.
=cut

sub mux_connection($) {shift}

1;
