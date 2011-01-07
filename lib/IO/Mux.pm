use warnings;
use strict;

package IO::Mux;
use Log::Report 'io-mux';

use List::Util  'min';
use POSIX       'errno_h';

$SIG{PIPE} = 'IGNORE';     # pipes are handled in mux

use constant
  { LONG_TIMEOUT   => 60   # no-one has set a timeout
  };

=chapter NAME
IO::Mux - simplify use of select()

=chapter SYNOPSIS
  use IO::Mux;

  my $mux    = IO::Mux->new;
  my $server = IO::Mux::Socket::UDP->new(...);
  $mux->add($server);

=chapter DESCRIPTION

C<IO::Mux> is designed to take the effort out of managing multiple socket
connections within one process. It is essentially a really fancy front
end to various kinds of event mechanisms, like C<select> and C<poll>. In
addition to maintaining the event loop, all input and output of the data
stream gets buffered for you. You do not need to play with filehandles
yourself.

On many platforms, the capabilities of various event mechanisms do differ
a lot. Be careful which mechanism you pick. Test it! Read the man-pages
which contain information about limitations and please contribute
information you discover.

See L</DETAILS> far below for a long description about differences with
M<IO::Multiplex> and M<IO::Async>, plus interesting implementation
details.

The following event managers are available on the moment:

=over 4
=item * M<IO::Mux::Select>
uses a C<select> call (see "man 2 select" on UNIX/Linux). The number
of file handles it can monitor is limited (but quite large) and the
overhead increases with the number of handles. On Windows only usable
with sockets, no pipes nor files.

=item * M<IO::Mux::Poll>
uses a C<poll> call (see "man 2 poll" on UNIX/Linux). Not available
on Windows, afaik. More efficient than C<select> when the number of
file handles grows, and many more filehandles can be monitored at
once.
=back

Other possible mechanisms include C<epoll>, C<ppoll>, C<pselect>,
C<kqueue>, and C<Glib>, may get added later. Connections to other event
frameworks as C<POE>, C<IO::Async>, and C<AnyEvent> may get added as well.

=chapter METHODS

=section Constructors

=ci_method new OPTIONS
There can only be one of these objects in your program. After
instantiating this, you will M<add()> file-handles and sockets.  Finally,
M<loop()> is called to go into C<select>-driven connection handling.

There are currently no OPTIONS, but they will probably arrive in the
upcoming releases.
=cut

sub new(@)  {my $class = shift; (bless {}, $class)->init( {@_} ) }
sub init($)
{   my ($self, $args) = @_;
    $self->{IM_handlers} = {};
    $self->{IM_timeouts} = {};
    $self;
}

#-------------
=section Accessors
=method handlers
Returns a list of all registered handlers (also the sockets).
=example
  foreach my $conn ($mux->handlers) { ... }
=cut

sub handlers()  {values %{shift->{IM_handlers}}}
sub _handlers() {shift->{IM_handlers}}

=method handler FILENO
Returns the handler which maintains FILENO.
=example
  $mux->handler(1);   # probably STDOUT
=cut

sub handler($) {$_[0]->{IM_handlers}{$_[1]}}

#-------------
=section Handle administration

=method add HANDLER|BUNDLE
Add an HANDLER or BUNDLE to the multiplexer.
Handlers extend M<IO::Mux::Handle>.
Bundles are related sets of handlers and extend M<IO::Mux::Bundle>.
=cut

# add() is the main user interface to mux, because from then the
# user works with connection objects. Therefore, offer some extra
# features here.

sub add($)
{   my ($self, $handler) = @_;

    if($handler->isa('IO::Mux::Bundle'))
    {   $self->add($_) for $handler->connections;
        return;
    }

    $handler->isa('IO::Mux::Handler')
        or error __x"attempt to add non handler {pkg}", pkg => ref $handler;

    my $fileno = $handler->fileno;
    $self->{IM_handlers}{$fileno} = $handler;

    trace "mux add fileno=$fileno ".$handler->name;
    if(my $timeout = $handler->timeout)
    {   $self->{IM_timeouts}{$fileno} = $timeout;
    }

    $handler->mux_init($self);
    $handler;
}

=method remove FILENO
Remove a connection from the multiplexer. Better to use the
connection close method.

=example
  $mux->remove($conn->fileno);

  # better this way:
  $conn->close;
=cut

sub remove($)
{   my ($self, $fileno) = @_;

    my $obj = delete $self->{IM_handlers}{$fileno}
        or return $self;

    $self->fdset($fileno, 0, 1, 1, 1);
    $obj->mux_remove;

    if(my $timeout = delete $self->{IM_timeouts}{$fileno})
    {   delete $self->{IM_next_timeout}
            if $self->{IM_next_timeout}==$timeout;
    }

    $self;
}

=method fdset FILENO, STATE, READ, WRITE, ERROR
Change the select bit STATE for the FILENO. Change the READ, WRITE
and/or ERROR state.
=example
  # clear read and error, keep write
  $mux->fdset($conn->fileno, 0, 1, 0, 1);

  # better this way:
  $conn->fdset(0, 1, 0, 1);
=cut

sub fdset($$$$$) {panic}

=method open MODE, PARAMS

=example
  # the short form
  my $who = $mux->open('-|', 'who');
  $who->readline( sub {print ${$_[0]}} }

  # equivalent to the longer
  my $who = IO::Mux::Open->new('-|', 'who');
  $mux->add($who);
  print <$who>;
=cut

sub open(@)
{   my $self = shift;
    my $open = IO::Mux::Open->can('new')
       or error __x"IO::Mux::Open not loaded";
    my $conn = $open->(@_);
    $self->add($conn) if $conn;
    $conn;
}

#------------------
=section Runtime

=method loop [HEARTBEAT]
Enter the main loop and start processing IO events. The loop will terminate
when all handles are closed, serious errors emerge or M<endLoop()> was
called.

You may provide a HARTBEAT code reference, which will get called each
time the internal C<select()> has found a file handle with something
to do or a timeout has expired. As arguments, it get the multiplexer
object, the number of events and the time left to the next timeout.
The validity of that third argument depends on the operating system
and the actual muxer type.

=example loop
  $mux->loop;
  exit 0;

=example loop with heartbeat
  $mux->loop(\&hb);
  sub hb($$)
  {   my ($mux, $count, $t) = @_;
  }

=cut

sub loop(;$)
{   my($self, $heartbeat) = @_;
    $self->{IM_endloop} = 0;

  LOOP:
    while(!$self->{IM_endloop} && keys %{$self->{IM_handlers}})
    {
#       while(my($fileno, $conn) = each %{$self->{IM_handlers}})
#       {   $conn->read
#               if $conn->usesSSL && $conn->pending;
#       }

        my $timeout = $self->{IM_next_timeout};
        my $wait    = defined $timeout ? $timeout-time : LONG_TIMEOUT;

        # For negative values, still give select a chance, to avoid
        # starvation when timeout handling starts consuming all
        # processor time.
        $wait       = 0.001 if $wait < 0.001;

        $self->one_go($wait, $heartbeat)
            or last LOOP;

        $self->_checkTimeouts($timeout);
    }

    $_->close
        for values %{$self->{IM_handlers}};
}

=method endLoop BOOLEAN
When this flag is set to C<true>, the activities will end after having
processed all currently flagged handles. All open handles when get
closed cleanly.

The loop will also be terminated when all the handlers are removed
(closed) That is a saver way to close the activities of your program
where a call to C<endLoop()> in many uses can be seen as tricky
side-effect of a single handler.
=cut

sub endLoop($) { $_[0]->{IM_endloop} = $_[1] }

=method changeTimeout FILENO, OLDTIMEOUT, NEWTIMEOUT
One of the connections wants to change its timeouts. A value of
zero or undef means I<not active>. 
=cut

sub changeTimeout($$$)
{   my ($self, $fileno, $old, $when) = @_;
    return if $old==$when;

    my $next = $self->{IM_next_timeout};
    if($old)
    {   # next timeout will be recalculated max once per loop
        delete $self->{IM_timeouts}{$fileno};
        $self->{IM_next_timeout} = $next = undef if $next && $next==$old;
    }

    if($when)
    {   $self->{IM_next_timeout} = $when if !$next || $next > $when;
        $self->{IM_timeouts}{$fileno} = $when;
    }
}

# handle all timeouts which have expired either during the select
# or during the processing of flags.
sub _checkTimeouts($)
{   my ($self, $next) = @_;

    my $now  = time;
    if($next && $now < $next)
    {   # Even when next is cancelled, none can have expired.
        # However, a new timeout may have arrived which may expire immediately.
        return $next if $self->{IM_next_timeout};
    }

    my $timo = $self->{IM_timeouts};
    my $hnd  = $self->{IM_handlers};
    while(my ($fileno, $when) = each %$timo)
    {   $when <= $now or next;
        $hnd->{$fileno}->mux_timeout($self);
        delete $timo->{$fileno};
    }

    $self->{IM_next_timeout} = min values %$timo;
}

1;

__END__
=chapter DETAILS

=section Alternatives

=subsection IO::Multiplex

This module started as a rework of M<IO::Multiplex>. It follows the
same concept, but with major internal and visible improvements. Some
core logic of this module has been derived from work by Bruce J Keeler
and Rob Brown. Examples, tests and documentation are derived from their
work as well.

=subsubsection Difference to IO::Multiplex

The M<IO::Mux> (I<Mux>) implementation is much closer to M<IO::Multiplex>
(I<Plex>) than you may expect. Similar enough to write a comparison.

Main differences:

=over 4

=item . Event managers
In Plex, all is organized around a C<select> loop.  In Mux, you have
a choice between various mechanisms of which some still need to be
implemented.

=item . Callback objects
In Plex, the file-handle may have a callback object associated to it. If
not, a default is used.  In Mux, the callback has the focus, which has
a file-handle associated to it. This use if the multiplexing C<select>
less visible this way, which should simplify implementations.

Mux does not support callbacks to name-spaces, because the object is
used for per-handle administration. In Plex, that administration is
located inside the multiplex object (and therefore difficult to extend
with higher level applications)

=item . Callback routines
The Mux implementation defines the same C<mux_*> methods as Plex, but
has organized them. In Plex, the connection accepting C<mux_connection>
and the input callback C<mux_input> are always available, even though
the callback object will only support one of both (if your abstraction
is correct). In Mux, there is a clear distinction between various kinds
of handlers.

In Mux, you have a few more locations where you can hook the process,
a few more callbacks.

=item . Error channel
Mux supports the error handle (when available) as well.

=item . Pipes and files
Mux added support for file reading and writing, pipes and proxies.

=item . Timeouts
One should use timeouts on all handlers, because no connection can be
trusted even files (which may come from stalled NFS partitions).

=subsection IO::Async / Net::Async

Paul Evans has developed a large number of modules which is more
feature complete than <IO::Mux>. It supports far more event loops,
is better tested, and has many higher level applications ready to
be used.

Certain applications will benefit from M<IO::Mux> (especially my
personal development projects), because it is based on the M<OODoc>
module for object oriented perl module documentation, and M<Log::Report>
for error handling and translations. Besides, the M<IO::Multiplex>
interface is much easier to use than the IO::Async concept.

=back
=cut
