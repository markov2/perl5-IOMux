use warnings;
use strict;

package IO::Mux::Socket::TCP;
use base 'IO::Mux::Socket';

use Log::Report 'io-mux';
use IO::Mux::Connection::TCP ();

use Socket 'SOCK_STREAM';

=chapter NAME
IO::Mux::Socket::TCP - TCP based socket

=chapter SYNOPSIS

=chapter DESCRIPTION
Accept TCP connections. When a connection arrives, it will get
handled by a new object which gets added to the multiplexer as
well.

=chapter METHODS

=section Constructors

=c_method new OPTIONS

=requires conn_type CLASS|CODE
The CLASS (package name) of client to be created for each new contact.
This CLASS must extend  M<IO::Mux::Connection::TCP>. You may also
provide a CODE reference which will be called with the socket leading
to the client.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    my $proto = $self->socket->socktype;
    $proto eq SOCK_STREAM
         or error __x"{pkg} needs STREAM protocol socket", pkg => ref $self;

    my $ct = $self->{IMST_conn_type} = $args->{conn_type}
        or error __x"a conn_type for incoming request is need by {name}"
          , name => $self->name;

    $self;
}

#------------------------
=section Attributes
=method clientType
=cut

sub clientType() {shift->{IMST_conn_type}}

#-------------------------
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

=method mux_read_flagged
The read flag is set on the socket, which means that a new connection
attempt is made.
=cut

sub mux_read_flagged()
{   my $self = shift;

    if(my $client = $self->socket->accept)
    {   my $ct = $self->{IMST_conn_type};
        my $handler = ref $ct eq 'CODE' ? $ct->($client)
          : $ct->new(socket => $client);
        $self->mux->add($handler);
        $self->mux_connection($self, $client);
    }
    else
    {   alert "accept for {name} failed", name => $self->name;
    }
}

1;
