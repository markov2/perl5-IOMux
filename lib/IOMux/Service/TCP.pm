use warnings;
use strict;

package IOMux::Service::TCP;
use base 'IOMux::Handler::Service';

use Log::Report 'iomux';
use IOMux::Net::TCP ();

use Socket 'SOCK_STREAM';

=chapter NAME
IOMux::Service::TCP - TCP (socket) based service

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
This CLASS must extend  M<IOMux::Net::TCP>. You may also provide a
CODE reference which will be called with the socket leading to the client.

=option  conn_opts ARRAY
=default conn_opts []
Pass some extra options when objects of C<conn_type> are created.

=default name 'listen tcp $host:$port'
=cut

sub init($)
{   my ($self, $args) = @_;

    my $socket = $args->{fh}
      = (delete $args->{socket}) || $self->extractSocket($args);

    my $proto = $socket->socktype;
    $proto eq SOCK_STREAM
         or error __x"{pkg} needs STREAM protocol socket", pkg => ref $self;

    $args->{name} ||= "listen tcp ".$socket->sockhost.':'.$socket->sockport;

    $self->SUPER::init($args);

    my $ct = $self->{IMST_conn_type} = $args->{conn_type}
        or error __x"a conn_type for incoming request is need by {name}"
          , name => $self->name;

    $self->{IMST_conn_opts} = $args->{conn_opts} || [];
    $self;
}

#------------------------
=section Accessors
=method clientType
=method socket
=cut

sub clientType() {shift->{IMST_conn_type}}
sub socket()     {shift->fh}

#-------------------------
=section Multiplexer
=cut

# The read flag is set on the socket, which means that a new connection
# attempt is made.

sub mux_read_flagged()
{   my $self = shift;

    if(my $client = $self->socket->accept)
    {   my $ct = $self->{IMST_conn_type};
        my $handler = ref $ct eq 'CODE'
          ? $ct->(socket => $client, @{$self->{IMST_conn_opts}})
          : $ct->new(socket => $client, @{$self->{IMST_conn_opts}});
        $self->mux->add($handler);
        $self->mux_connection($client);
    }
    else
    {   alert "accept for {name} failed", name => $self->name;
    }
}

1;
