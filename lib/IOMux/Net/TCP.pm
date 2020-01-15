# This code is part of distribution IOMux.  Meta-POD processed with OODoc
# into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package IOMux::Net::TCP;
use base 'IOMux::Handler::Read', 'IOMux::Handler::Write';

use warnings;
use strict;

use Log::Report 'iomux';
use Socket      'SOCK_STREAM';
use IO::Socket::INET;

=chapter NAME
IOMux::Net::TCP - handle a TCP connection

=chapter SYNOPSIS

=chapter DESCRIPTION
Handle a service or locally initiated TCP connection.

=chapter METHODS

=section Constructors

=c_method new %options
Build a connection as client or server. You may either pass an prepared
C<socket> object or parameters to initiate one. All %options which start
with capitals are passed to the socket creation. See M<extractSocket()>
for those additional %options.

=default name  'tcp $host:$port'

=requires socket M<IO::Socket::INET>
Provide a socket, either as object or the parameters to instantiate it.

=example
  # long form, most flexible
  my $socket = IO::Socket::INET->new(PeerAddr => 'www.example.com:80');
  my $client = IOMux::Net::TCP->new(socket => $socket);
  $mux->add($client);

  # short form
  my $client = IOMux::Net::TCP->new(PeerAddr => 'www.example.com:80');
  $mux->add($client);

  # even shorter
  my $client = $mux->open('tcp', PeerAddr => 'www.example.com:80');
=cut

sub init($)
{   my ($self, $args) = @_;

    $args->{Proto} ||= 'tcp';
    my $socket = $args->{fh}
      = (delete $args->{socket}) || $self->extractSocket($args);

    $args->{name}  ||= "tcp ".$socket->peerhost.':'.$socket->peerport;

    $self->IOMux::Handler::Read::init($args);
    $self->IOMux::Handler::Write::init($args);

    $self;
}

#-------------------
=section Accessors
=method socket 
=cut

sub socket() {shift->fh}

#-------------------
=section User interface

=subsection Connection

=method shutdown <0|1|2>
Shut down a socket for reading or writing or both. See the C<shutdown>
Perl documentation for further details.

If the shutdown is for reading (0 or 2), it happens immediately. However,
shutdowns for writing (1 or 2) are delayed until any pending output has
been successfully written to the socket.
=example
  $conn->shutdown(1);
=cut

sub shutdown($)
{   my($self, $which) = @_;
    my $socket = $self->socket;
    my $mux    = $self->mux;

    if($which!=1)
    {   # Shutdown for reading.  We can do this now.
        $socket->shutdown(0);
        $self->{IMNT_shutread} = 1;
        # The muxEOF hook must be run from the main loop to consume
        # the rest of the inbuffer if there is anything left.
        # It will also remove $fh from _readers.
        $self->fdset(0, 1, 0, 0);
    }
    if($which!=0)
    {   # Shutdown for writing.  Only do this now if there is no pending data.
        $self->{IMNT_shutwrite} = 1;
        unless($self->muxOutputWaiting)
        {   $socket->shutdown(1);
            $self->fdset(0, 0, 1, 0);
        }
    }

    $self->close
        if $self->{IMNT_shutread}
        && $self->{IMNT_shutwrite} && !$self->muxOutputWaiting;
}

sub close()
{   my $self = shift;

    warning __x"closing {name} with read buffer", name => $self->name
        if length $self->{ICMT_inbuf};

    warning __x"closing {name} with write buffer", name => $self->name
        if $self->{ICMT_outbuf};

    $self->socket->close;
    $self->SUPER::close;
}

#-------------------------
=section Multiplexer
=cut

sub muxInit($)
{   my ($self, $mux) = @_;
    $self->SUPER::muxInit($mux);

    # we will not listen for write until we have something to write
    $self->fdset(1, 1, 0, 1);
}

sub muxOutbufferEmpty()
{   my $self = shift;
    $self->SUPER::muxOutbufferEmpty;

    if($self->{IMNT_shutwrite} && !$self->muxOutputWaiting)
    {   $self->socket->shutdown(1);
        $self->fdset(0, 0, 1, 0);
        $self->close if $self->{IMNT_shutread};
    }
}

=method muxEOF 
For sockets, this does not nessecarily mean that the descriptor has been
closed, as the other end of a socket could have used M<shutdown()> to
close just half of the socket, leaving us free to write data back down
the still open half.

=example
In this example, we send a final reply to the other end of the socket,
and then shut it down for writing.  Since it is also shut down for reading
(implicly by the EOF condition), it will be closed once the output has
been sent, after which the M<close()> callback will be called.

  sub muxEOF
  {   my ($self, $ref_input) = @_;
      print $fh "Well, goodbye then!\n";
      $self->shutdown(1);
  }
=cut

1;
