use warnings;
use strict;

package IOMux;
use Log::Report 'iomux';

use List::Util  'min';
use POSIX       'errno_h';

$SIG{PIPE} = 'IGNORE';     # pipes are handled in mux

use constant
  { LONG_TIMEOUT   => 60   # no-one has set a timeout
  };

=chapter NAME
IOMux - simplify use of file-event loops

=chapter SYNOPSIS
  use IOMux;
  use IOMux::Service::TCP;

  my $mux    = IOMux->new;
  my $server = IOMux::Service::TCP->new(...);
  $mux->add($server);
  $mux->loop;
  exit 0;

=chapter DESCRIPTION

C<IOMux> is designed to take the effort out of managing multiple socket,
file or pipe connections within a single process. It is essentially a
really fancy front end to various kinds of event mechanisms, currently
limited to C<select> and C<poll>.

In addition to maintaining the event loop, all input and output of the
data stream gets buffered for you which tends to be quite difficult in
event driven programs. Methods are provided to simulate common methods
for M<IO::Handle>

On many platforms, the capabilities of various event mechanisms differ
a lot. Be careful which mechanism you pick. Test it! Read the man-pages
which contain information about limitations and please contribute
information you discover.

See L</DETAILS> far below for a long description about
=over 4
=item * event managers C<select()> and C<poll()>
=item * managed file handles
=item * interesting implementation details.
=back

There are at least ten other event modules on CPAN. See M<IOMux::Alternatives>
for a comparison between this module and, amongst other, M<IO::Multiplex>,
M<AnyEvent>, M<IO::Async> and <POE>.

=chapter METHODS

=section Constructors

=c_method new %options
There can only be one of these objects in your program. After
instantiating this, you will M<add()> file-handles and sockets.  Finally,
M<loop()> is called to go into C<select>-driven connection handling.

There are currently no %options, but they will probably arrive in the
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
=cut

#-------------
=section User interface

=method add $handler|$bundle
Add an $handler or $bundle to the multiplexer. Handlers extend
M<IOMux::Handler>. Bundles are related sets of handlers and
extend M<IOMux::Bundle>.
=cut

# add() is the main user interface to mux, because from then the
# user works with connection objects. Therefore, offer some extra
# features here.

sub add($)
{   my ($self, $handler) = @_;

    UNIVERSAL::isa($handler, 'IOMux::Handler')
        or error __x"attempt to add non handler {pkg}"
          , pkg => (ref $handler || $handler);

    $handler->muxInit($self);
    $handler;
}

=method open $mode, $params
This C<open()> provides a simplified interface to M<IOMux::Open>, which on
its turn is a simplification on using all kinds of handlers. See the manual
of M<IOMux::Open> for an extended description of the use.

=example
  use IOMux::Open '-|';  # loads handler code
  sub print_line($$)
  {   my ($handler, $line) = @_;
      print "line = $line";
  }

  # the short form
  my $who = $mux->open('-|', 'who');
  $who->readline(\&print_line);

  # equivalent to the longer
  my $who = IOMux::Open->new('-|', 'who');
  $mux->add($who);
  $who->readline(\&print_line);

  # or even longer
  use IOMux::Pipe::Read;
  my $who = IOMux::Pipe::Read->new(command => 'who');
  $mux->add($who);
  $who->readline(\&print_line);
  
=cut

sub open(@)
{   my $self = shift;
    IOMux::Open->can('new')
        or error __x"IOMux::Open not loaded";
    my $conn = IOMux::Open->new(@_);
    $self->add($conn) if $conn;
    $conn;
}

=method loop [$heartbeat]
Enter the main loop and start processing IO events. The loop will terminate
when all handles are closed, serious errors emerge or M<endLoop()> was
called.

You may provide a $heartbeat code reference, which will get called each
time the internal C<select()> has found a file handle with something
to do or a timeout has expired. As arguments, it get the multiplexer
object, the number of events and the time left to the next timeout.
The validity of that third argument depends on the operating system
and the actual muxer type.

=example loop
  $mux->loop;
  exit 0;

=example loop with heartbeat

  sub hb($$)
  {   my ($mux, $count, $t) = @_;
      ...
  }

  $mux->loop(\&hb);
=cut

sub loop(;$)
{   my($self, $heartbeat) = @_;
    $self->{IM_endloop} = 0;

    my $handlers = $self->{IM_handlers};
    keys %$handlers
        or error __x"there are no handlers for the mux loop";

  LOOP:
    while(!$self->{IM_endloop} && keys %$handlers)
    {
#       while(my($fileno, $conn) = each %$handlers)
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
        for values %$handlers;
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

#-------------
=section For internal use

The following methods are provided, but end-users should avoid calling
these methods directly: call them via the specific extension of
M<IOMux::Handler>.

=method handlers 
Returns a list of all registered handlers (also the listening sockets).
=example
  foreach my $handler ($mux->handlers)
  {   say $handler->name;
  }
=cut

sub handlers()  {values %{shift->{IM_handlers}}}
sub _handlers() {shift->{IM_handlers}}

=method handler $fileno, [$handler]
Returns (or sets) the handler which maintains $fileno.
=example
  $mux->handler(1);   # probably STDOUT
=cut

sub handler($;$)
{   my $hs     = shift->{IM_handlers};
    my $fileno = shift;
    @_ or return $hs->{$fileno};
    (defined $_[0]) ? ($hs->{$fileno} = shift) : (delete $hs->{$fileno});
}

=method remove $fileno
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
    $obj->muxRemove;

    if(my $timeout = delete $self->{IM_timeouts}{$fileno})
    {   delete $self->{IM_next_timeout}
            if $self->{IM_next_timeout}==$timeout;
    }

    $self;
}

=method fdset $fileno, $state, $read, $write, $except
Change the select bit $state for the $fileno. Change the $read, $write
and/or $except-ion state. An end-users of this module should never need
this.
=example
  # clear read and except, keep write
  $mux->fdset($conn->fileno, 0, 1, 0, 1);

  # preferred this way:
  $conn->fdset(0, 1, 0, 1);
=cut

sub fdset($$$$$) {panic}

=method changeTimeout $fileno, $oldtimeout, $newtimeout
One of the connections wants to change its timeouts. A value of
zero or undef means I<not active>.

The correct $oldtimeout must be provided to make it fast to detect whether
this was the first timeout to expire. Checking the first timeout takes
C<O(n)> time, so we wish to avoid that.

=example
  # set timeout
  $mux->changeTimeout($conn->fileno, undef, 10);

  # preferred this way
  $conn->timeout(10);
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
        $hnd->{$fileno}->muxTimeout($self);
        delete $timo->{$fileno};
    }

    $self->{IM_next_timeout} = min values %$timo;
}

1;

__END__
=chapter DETAILS

=section Installation

Many components of IO-driven programming are quite platform dependent.
Therefore, C<IOMux> does not enforce the installation of these
dependencies during installation. However, when you choose to use some of
the components, you will discover you need to install additional modules.
For instance, when you use M<IOMux::Poll> you will need M<IO::Poll>.

Many perl modules (like LWP) use autoloading to get additional code in
when it gets used. This is a nice help for users who do not need to load
those modules explicitly. It is also a speed-up for the boot-time of
scripts. However, C<IOMux> is usually run in a daemon (see F<examples/>
directory) which should load all code before child processes are started.
Besides, initialization time does not really matter for daemons.

=section Event managers

The following event managers are available on the moment:

=over 4
=item * M<IOMux::Select>
uses a C<select> call (see "man 2 select" on UNIX/Linux). The number
of file handles it can monitor is limited (but quite large) and the
overhead increases with the number of handles. On Windows only usable
with sockets, no pipes nor files.

=item * M<IOMux::Poll>
uses a C<poll> call (see "man 2 poll" on UNIX/Linux). Not available
on Windows, afaik. More efficient than C<select> when the number of
file handles grows, and many more filehandles can be monitored at
once.
=back

Other possible mechanisms include C<epoll>, C<ppoll>, C<pselect>,
C<kqueue>, and C<Glib>, may get added later. Connections to other event
frameworks as C<POE>, C<IO::Async>, and C<AnyEvent> may get added as well.

=section File handles

The event managers looks to one or more file handles for changes: either
the write buffer gets empty (the program may send more), requested data
has arrived (ready to be read) or (unexpected) error text comes in.

The following handles are supported, although maybe not on your
platform.

=over 4
=item * M<IOMux::Service::TCP>
A server for TCP based application, like a web-server. On each
incoming connection, a M<IOMux::Net::TCP> will be started to
handle it.

=item * M<IOMux::Net::TCP>
Handle a single TCP connection.

=item * M<IOMux::File::Read> and M<IOMux::File::Write>
Read and write a file asynchronously, only few Operating Systems
support this.

=item * M<IOMux::Pipe::Read> and M<IOMux::Pipe::Write>
Read the output from an command, respectively send bytes to
and external command.

=back

=cut
