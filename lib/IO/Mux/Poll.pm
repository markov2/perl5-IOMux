use warnings;
use strict;

package IO::Mux::Poll;
use base 'IO::Mux';

use Log::Report 'io-mux';

use List::Util  'min';
use POSIX       'errno_h';
use IO::Poll;
use IO::Handle;

$SIG{PIPE} = 'IGNORE';   # pipes are handled in select

=chapter NAME
IO::Mux::Poll - simplify use of poll()

=chapter SYNOPSIS
  use IO::Mux::Poll;

  my $mux    = IO::Mux::Poll->new;
  my $server = IO::Mux::Service::TCP->new(...);
  $mux->add($server);
  $mux->loop;

=chapter DESCRIPTION
Multiplexer based on the C<poll()> system call, defined by POSIX.

The C<poll> has less administration overhead than the C<select> call
(implemented via M<IO::Mux::Select>) because it avoids the need to play
with bit-vectors to see which file handles got activated. However,
C<poll> is not supported on all platforms.

=chapter METHODS

=section Constructors
=cut

my $poll;
sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $poll ||= IO::Poll->new;
    $self;
}

#-------------
=section Accessors
=method poller
The internal M<IO::Poll> object.
=cut

sub poller {$poll}

#-------------

sub fdset($$$$$)
{   my ($self, $fileno, $state, $r, $w, $e) = @_;
    my $conn = $self->handler($fileno) or return;
    my $fh   = $conn->fh;
    my $mask = $poll->mask($fh);
    if($state==0)
    {   $mask &= ~POLLIN  if $r;
        $mask &= ~POLLOUT if $w;
        $mask &= ~POLLERR if $e;
    }
    else
    {   $mask |=  POLLIN  if $r;
        $mask |=  POLLOUT if $w;
        $mask |=  POLLERR if $e;
    }
    $poll->mask($fh, $mask);
}

sub one_go($$)
{   my ($self, $wait, $heartbeat) = @_;

    my $numready = $poll->poll($wait);

    $heartbeat->($self, $numready, undef)
        if $heartbeat;

    if($numready < 0)
    {   return if $! == EINTR || $! == EAGAIN;
        alert "Leaving loop with $!";
        return 0;
    }

    $numready
        or return 1;
 
    $self->_ready(mux_read_flagged   => POLLIN|POLLHUP);
    $self->_ready(mux_write_flagged  => POLLOUT);
    $self->_ready(mux_except_flagged => POLLERR);

    1;  # success
}

# It would be nice to have an algorithm which is better than O(n)
sub _ready($$)
{   my ($self, $call, $mask) = @_;
    my $handlers = $self->_handlers;
    foreach my $fh ($poll->handles($mask))
    {   my $fileno = $fh->fileno or next;   # close filehandle
        if(my $conn = $handlers->{$fileno})
        {   # filehandle flagged
            $conn->$call($fileno);
        }
        else
        {   # Handler administration error, but when write and error it may
            # be caused by read errors.
            alert "connection for ".$fh->fileno." not registered in $call"
                if $call eq 'mux_read_flagged';
        }
    }
}

1;

__END__
=chapter DETAILS

=section Implementation limitations

Poll is only available on UNIX.  Windows Vista has added a WSAPoll with
comparible functionality (probably), but afaik there is no binary wrapper
available for perl yet.
=cut
