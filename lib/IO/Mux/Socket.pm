use warnings;
use strict;

package IO::Mux::Socket;
use base 'IO::Mux::Handler';

use Log::Report       'io-mux';

use Socket            'SOCK_DGRAM';
use IO::Socket::INET  ();
# use IO::Socket::SSL ();  # not always installed: user must load it

=chapter NAME
IO::Mux::Socket - socket on select()

=chapter SYNOPSIS

=chapter DESCRIPTION
This base-class defines how sockets are connected to M<IO::Multiplex>
objects.

=chapter METHODS

=section Constructors

=c_method new OPTIONS
Create a new socket to be listened on. You may either pass an prepared
C<socket> object or parameters to initiate one.

All OPTIONS which start with capitals are passed to the socket creation.
See M<extractSocket()>.

=default name  socket name
=cut

sub new(@)
{   my ($class, %args) = @_;
    my $socket    = $args{socket} || $class->extractSocket(\%args);
    $args{name} ||= $socket->sockaddr;
    $args{fileno} = $socket->fileno;

    $class eq __PACKAGE__
        or return $class->SUPER::new(%args, socket => $socket);

    # finally I know what to initialize!
    $class .= '::' . $socket->protocol==SOCK_DGRAM ? 'UDP' : 'TCP';
    $class->new(%args, socket => $socket);  # start all over
}

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my $socket = $self->{IMS_socket} = $args->{socket};
    $self->{IMS_uses_ssl} = $socket->isa('IO::Socket::SSL');
    $self;
}

#------------------------
=section Attributes
=method usesSSL
=method socket
=cut

sub usesSSL {shift->{IMS_uses_ssl}}
sub socket  {shift->{IMS_socket}}
sub fh      {shift->{IMS_socket}}

#-------------------------
=section Multiplexer
=cut

sub mux_init($)
{   my ($self, $mux) = @_;
    $self->SUPER::mux_init($mux);

    my $socket = $self->socket;
    my $addr   = $socket->sockhost . ':' . $socket->sockport;
    info __x"add socket listener {name} is {type} on {addr}"
      , name => $self->name, type => ref $self, addr => $addr;

    $self;
}

=method mux_connection CLIENT
A new connection has arrived on the socket where we are listening
on. The connection has been accepted and the filehandle of the
new CLIENT has been added to the MUX. You may wish to send an
initial string.
=cut

sub mux_connection($)
{   my ($self, $client) = @_
    # don't know yet
}

1;
