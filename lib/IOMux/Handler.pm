use warnings;
use strict;

package IOMux::Handler;

use Log::Report  'iomux';

use Scalar::Util     'weaken';
use Time::HiRes      'time';
use Socket;
use Fcntl;

my $start_time = time;

=chapter NAME
IOMux::Handler - handle a connection

=chapter SYNOPSIS
 # only extensions can be instantiated

=chapter DESCRIPTION
This is the generic base class for all kinds of connections, both the
readers and the writers.  It is used to administer which file descriptors
are in use in the mux.

=chapter METHODS

=section Constructors

=c_method new %options

=option  name STRING
=default name <stringified handle>
Nice name, most useful in error messages.

=requires fh FILEHANDLE
=cut

sub new(@)  {my $class = shift; (bless {}, $class)->init( {@_} ) }

sub init($)
{   my ($self, $args) = @_;
    return $self if $self->{IH_name}; # already initialized

    my $name = $self->{IH_name} = $args->{name} || "$self";
    if(my $fh = $self->{IH_fh} = $args->{fh})
    {   $self->{IH_fileno}   = $fh->fileno;
        $self->{IH_uses_ssl} = UNIVERSAL::isa($fh, 'IO::Socket::SSL');
    }
    $self;
}

=c_method open $mode, $what, %options
Most handlers provide an easy way to instantiate them via the
M<IOMux::Open> module.
=cut

sub open() {panic}

#-------------------------
=section Accessors
=method name 
=method mux 
=cut

sub name()   {shift->{IH_name}}
sub mux()    {shift->{IH_mux}}

=method fileno 
The sequence number of the filehandle, UNIX style.  See C<man 3 fileno>

=method fh 
Returns the filehandle.

=method usesSSL 
=cut

sub fileno() {shift->{IH_fileno}}
sub fh()     {shift->{IH_fh}}
sub usesSSL(){shift->{IH_uses_ssl}}

#-----------------------
=section User interface

=subsection Connection

=method timeout [$timeout]
Set (or get) the timer. The $timeout value is a certain number of seconds
in the future, after which the C<mux_timeout> callback is called.  When
$timeout is not defined or zero, the timer is cancelled.  Timers are not
reset automatically.

When the timeout value is very large (larger then C<time> when the
program started), it is considered absolute, not relative. This is
very useful when you wish a timeout to appear on some exact moment.

When the timeout is very small (but larger than 0), then still at
least one C<select> loop will be used for this timeout is handled.

=example
  $conn->timeout(23.6);   # over 23 seconds
  print $conn->timeout;   # moment in epoc
  $conn->timeout(0);      # cancel

  use Time::HiRes 'time';
  BEGIN {$begin = time}
  $conn->timeout($begin+2.5);
=cut

sub timeout(;$)
{   my $self  = shift;
    @_ or return $self->{IH_timeout};

    my $old   = $self->{IH_timeout};
    my $after = shift;
    my $when  = !$after      ? undef
      : $after > $start_time ? $after
      :                        ($after + time);

    $self->{IH_mux}->changeTimeout($self->{IH_fileno}, $old, $when);
    $self->{IH_timeout} = $when;
}

=method close [$callback]
Close the handler. When the $callback is provided, it will be called
after the filehandle has been closed and the object disconnected from
the multiplexer.
=cut

sub close(;$)
{   my ($self, $cb) = @_;
    if(my $fh = delete $self->{IH_fh})
    {   if(my $mux = $self->{IH_mux})
        {   $mux->remove($self->{IH_fileno});
        }
        $fh->close;
    }
    local $!;
    $cb->($self) if $cb;
}  

#-------------------------
=section Multiplexer

=subsection Connection

The I<user interface> provides a higher level interaction then the
raw interface. These methods may be extended by users, but there
are usually simpler methods to achieve that.

=method muxInit $mux, [$handler]
Called after the multiplexer has added this handler to its
administration.

In rare cases, it may happen that an other $handler needs to
be called when this filehandle get tickled, especially for
tricks with bundles.
=cut

sub muxInit($;$)
{   my ($self, $mux, $handler) = @_;

    $self->{IH_mux} = $mux;
    weaken($self->{IH_mux});

    my $fileno = $self->{IH_fileno};
    $mux->handler($fileno, $handler || $self);

    if(my $timeout = $self->{IH_timeout})
    {   $mux->changeTimeout($fileno, undef, $timeout);
    }

    trace "mux add #$fileno, $self->{IH_name}";
}

=method muxRemove 
Remove the handler from the multiplexer.
=cut

sub muxRemove()
{   my $self = shift;
    delete $self->{IH_mux};
#use Carp 'cluck';
#cluck "REMOVE";
    trace "mux remove #$self->{IH_fileno}, $self->{IH_name}";
}

=method muxTimeout 
Called when a timer expires on the FILEHANDLE.

Use M<timeout()> to set (or clear) a timeout.
When new data is sent or received on the FILEHANDLE, that will B<not>
expire the timeout.
=cut

sub muxTimeout()
{   my $self = shift;
    error __x"timeout set on {name} but not handled", name => $self->name;
}

#----------------------

=subsection Reading

=method muxReadFlagged $fileno
Called when the read flag is set for this handler.

When you extend this module, you probably want to override
C<muxConnection()> or C<muxInput()>, not this "raw" method.

=cut

#sub muxReadFlagged($)  { panic "no input expected on ". shift->name }

=method muxExceptFlagged $fileno
Called (in the rare case) that an exception event if flagged. This
means that the socket needs urgent inspection.

According to the Linux manual page for C<select()>, these exceptions
only happen when out-of-band (OOB) data arrives over udp or tcp.
=cut

#sub muxExceptFlagged($)  { panic "exception arrived on ". shift->name }

=subsection Writing

=method muxWriteFlagged $fileno
Called when the write flag is set for this handler; this indicates
that the output buffer is empty hence more data can be sent.

When you extend this module, you probably want to override
C<muxOutputbufferEmpty()>, not this "raw" method.
=cut

#sub muxWriteFlagged($) { shift }  # simply ignore write offers

=subsection Service
=cut

#-------------------------
=section Helpers

=method show 
Returns a textblock with some info about the filehandle, for
debugging purposes.
=example
  print $conn->show;
=cut

sub show()
{   my $self = shift;
    my $name = $self->name;
    my $fh   = $self->fh
        or return "fileno=".$self->fileno." is closed; name=$name";

    my $mode = 'unknown';
    unless($^O eq 'Win32')
    {   my $flags = fcntl $fh, F_GETFL, 0       or fault "fcntl F_GETFL";
        $mode = ($flags & O_WRONLY) ? 'w'
              : ($flags & O_RDONLY) ? 'r'
              : ($flags & O_RDWR)   ? 'rw'
              :                       'p';
    }

    my @show = ("fileno=".$fh->fileno, "mode=$mode");
    if(my $sockopts  = getsockopt $fh, SOL_SOCKET, SO_TYPE)
    {   # socket
        my $type = unpack "i", $sockopts;
        my $kind = $type==SOCK_DGRAM ? 'UDP' : $type==SOCK_STREAM ? 'TCP'
          : 'unknown';
        push @show, "sock=$kind";
    }

    join ", ", @show, "name=$name";
}

=method fdset $state, $read, $write, $error
Change the flags for the $read, $write and/or $error acceptance by the
mux to $state.
=cut

sub fdset($$$$)
{   my $self = shift;
    $self->{IH_mux}->fdset($self->{IH_fileno}, @_);
}

=ci_method extractSocket HASH
Extract M<IO::Socket::INET> (or ::SSL) parameters from the HASH and
construct a socket from it. The used options are all starting with
a capital and removed from the HASH. Additionally, some controlling
options are used.

=option  socket M<IO::Socket> object
=default socket <created>
You may pre-initialize an IO::Socket.

=option  use_ssl BOOLEAN
=default use_ssl <false>
When true, a M<IO::Socket::SSL> object will be created, otherwise a
M<IO::Socket::INET> object.
=cut

sub extractSocket($)
{   my ($thing, $args) = @_;
    my $class    = ref $thing || $thing;

    my $socket   = delete $args->{socket};
    return $socket if $socket;

    my @sockopts = (Blocking => 0);
    push @sockopts, $_ => $args->{$_}
        for grep /^[A-Z]/, keys %$args;

    @sockopts
       or error __x"pass socket or provide parameters to create one for {pkg}"
          , pkg => $class;

    my $ssl  = delete $args->{use_ssl};

    # the extension will load these classes
    my $make = $ssl ? 'IO::Socket::SSL' : 'IO::Socket::INET';
    $socket  = $make->new(@sockopts)
        or fault __x"cannot create {pkg} socket", pkg => $class;

    $socket;
}

1;
