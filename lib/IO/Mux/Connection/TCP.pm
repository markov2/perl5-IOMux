use warnings;
use strict;

package IO::Mux::Connection::TCP;
use base 'IO::Mux::Connection';

use Log::Report 'io-mux';
use POSIX       'errno_h';

use constant BIGSIZE => 10240;

=chapter NAME
IO::Mux::Connection::TCP - handle a TCP connection

=chapter SYNOPSIS

=chapter DESCRIPTION

=chapter METHODS

=section Constructors

=c_method new OPTIONS
Build a connection as client or server. You may either pass an prepared
C<socket> object or parameters to initiate one. All OPTIONS which start
with capitals are passed to the socket creation. See M<extractSocket()>
for those additional OPTIONS.

=cut

sub init($)
{   my ($self, $args) = @_;
    my $socket = $self->{IMCT_socket} = $self->extractSocket($args);
    $args->{fileno} = $socket->fileno;
    $self->SUPER::init($args);

    $self->{IMCT_uses_ssl} = $args->{use_ssl};
    $self->{IMCT_inbuf}  = '';
    $self->{IMCT_errbuf} = '';
    # outbuf is a reference to a string. If it exists, then delayed
    # writing is in progress. All in an attempt to avoid some copies.

    $self;
}

#-------------------
=section Accessors
=method usesSSL
=method socket
=cut

sub usesSSL {shift->{IMCT_uses_ssl}}
sub socket  {shift->{IMCT_socket}}
sub fh      {shift->{IMCT_socket}}

#-------------------------
=section Multiplexer
=cut

sub mux_init($)
{   my ($self, $mux) = @_;
    $self->SUPER::mux_init($mux);
    my $socket = $self->socket;
    info "connected ".$socket->fileno." to ".$socket->peerhost.' via '.(ref $self);
    $self->fdset(1, 1, 1, 0);  # errors as well?
}

sub mux_remove()
{   my $self = shift;
    info "removed connection to ".$self->socket->peerhost;
    $self->SUPER::mux_remove;
}

sub mux_read_flagged()
{   my $self = shift;
    my $bytes_read
      = sysread $self->{IMCT_socket}, $self->{IMCT_inbuf}, BIGSIZE
         , length($self->{IMCT_inbuf});

    if($bytes_read)
    {   $self->mux_input(\$self->{IMCT_inbuf});
    }
    elsif(defined $bytes_read)   # == 0
    {   $self->mux_eof(\$self->{IMCT_inbuf});
        $self->shutdown(0);
        $self->close
            unless $self->{IMCT_outbuf};
    }
    elsif($! == EINTR || $! == EAGAIN || $! == EWOULDBLOCK)
    {   # a bit unexpected, but ok
    }
    else
    {   warning "read connection {name} closed unexpectedly: {err}"
          , name => $self->name, err => $!;
        $self->close;
    }
}

sub mux_write_flagged()
{   my $self   = shift;
    my $outbuf = $self->{IMCT_outbuf};
    unless($outbuf)
    {   $outbuf = $self->{IMCT_outbuf} = $self->mux_outbuffer_empty;
        unless(defined $outbuf)
        {   # nothing can be produced on call, so we don't need the
            # empty-write signals on the moment (enabled at next write)
            $self->fdset(0, 0, 1, 0);

            if($self->{IMCT_shutwrite})
            {   $self->socket->shutdown(1);
                $self->close if $self->{IMCT_shutread};
            }
            return;
        }

        unless(length $$outbuf)
        {   # retry at next interval
            delete $self->{IMCT_outbuf};
            return;
        }
    }

    my $bytes_written = syswrite $self->{IMCT_socket}, $$outbuf;
    if(!defined $bytes_written)
    {   # should happen, but we're kind
        return if $! == EWOULDBLOCK || $! == EINTR || $! == EAGAIN;
        warning "write connection {name} closed unexpectedly: {err}"
          , name => $self->name, err => $!;
        $self->close;
    }
    elsif($bytes_written==length $$outbuf)
         { delete $self->{IMCT_outbuf} }
    else { substr($$outbuf, 0, $bytes_written) = '' }
}

=method write SCALAR
Send the content of the string, passed as reference in SCALAR. You
probably want to use M<print()> or M<printf()>.
=cut

sub write($)
{   my ($self, $blob) = @_;
    if(exists $self->{IMCT_outbuf})
    {   ${$self->{IMCT_outbuf}} .= $$blob;
        return;
    }

    my $bytes_written = syswrite $self->{IMCT_socket}, $$blob;
    if(!defined $bytes_written)
    {   # should happen, but we're kind
        return if $! == EWOULDBLOCK || $! == EINTR || $! == EAGAIN;
        warning "write connection {name} closed unexpectedly: {err}"
          , name => $self->name, err => $!;
        $self->close;
    }
    elsif($bytes_written==length $$blob)
    {   # we got rit of all at once.  Cheap!
        return;
    }

    substr($$blob, 0, $bytes_written) = '';
    $self->{IMCT_outbuf} = $blob;
    $self->fdset(1, 0, 1, 0);
}

=method shutdown (0|1|2)
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
        $self->{IMCT_shutread} = 1;
        # The mux_eof hook must be run from the main loop to consume
        # the rest of the inbuffer if there is anything left.
        # It will also remove $fh from _readers.
        $self->fdset(0, 1, 0, 0);
    }
    if($which!=0)
    {   # Shutdown for writing.  Only do this now if there is no pending data.
        $self->{IMCT_shutwrite} = 1;
        exists $self->{IMCT_outbuf}
            or $socket->shutdown(1);
        $self->fdset(0, 0, 1, 0);
    }

    $self->close
        if $self->{IMCT_shutread}
        && $self->{IMCT_shutwrite} && !$self->{IMCT_outbuf};
}

=method close
Close the connection.
=cut

sub close()
{   my $self = shift;

    warning __x"closing {name} with read buffer", name => $self->name
        if length $self->{ICMT_inbuf};

    warning __x"closing {name} with write buffer", name => $self->name
        if $self->{ICMT_outbuf};

    $self->SUPER::close;
}

1;
