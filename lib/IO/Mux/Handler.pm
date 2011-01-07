use warnings;
use strict;

package IO::Mux::Handler;

use Log::Report  'io-mux';

use Scalar::Util     'weaken';
use Time::HiRes      'time';
use IO::Socket::INET ();

my $start_time = time;

=chapter NAME
IO::Mux::Handler - handle a connection

=chapter SYNOPSIS
 # only extensions can be instantiated

=chapter DESCRIPTION

=chapter METHODS

=section Constructors

=c_method new OPTIONS

=option  name STRING
=default name <stringified handle>
Nice name, most useful in error messages.

=requires fileno INTEGER
The file number is detected by the extending modules.
=cut

sub new(@)  {my $class = shift; (bless {}, $class)->init( {@_} ) }

sub init($)
{   my ($self, $args) = @_;
    $self->{IMH_name}   = $args->{name} || "$self";
    $self->{IMH_fileno} = $args->{fileno} or panic;
    $self;
}

#-------------------------
=section Attributes
=method name
=method mux
=method fileno
The sequence number of the filehandle, UNIX style.  See C<man 3 fileno>
=method fh
Returns the filehandle.
=cut

sub name()   {shift->{IMH_name}}
sub mux()    {shift->{IMH_mux}}
sub fileno() {shift->{IMH_fileno}}
sub fh()     {panic}

#-------------------------
=section Common

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
    my $class  = ref $thing || $thing;

    my $socket = delete $args->{socket};
    return $socket if $socket;
    
    my @sockopts;
    push @sockopts, $_ => delete $args->{$_}
        for grep /^[A-Z]/, keys %$args;

    @sockopts
       or error __x"pass socket or provide parameters to create one for {pkg}"
          , pkg => $class;

    my $ssl  = delete $args->{use_ssl};
    my $make = $ssl ? 'IO::Socket::SSL' : 'IO::Socket::INET';
    $socket  = $make->new(Blocking => 0, @sockopts)
        or fault __x"cannot create {pkg} socket", pkg => $class;

    $socket;
}

=method timeout [TIMEOUT]
Set (or get) the timer. The TIMEOUT value is a certain number of seconds
in the future, after which the C<mux_timeout> callback is called.  When
TIMEOUT is not defined or zero, the timer is cancelled.  Timers are not
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
    @_ or return $self->{IMH_timeout};

    my $old   = $self->{IMH_timeout};
    my $after = shift;
    my $when  = !$after      ? undef
      : $after > $start_time ? $after
      :                        ($after + time);
    $self->{IMH_mux}->changeTimeout($self->{IMH_fileno}, $old, $when);
    $self->{IMH_timeout} = $when;
}

#-------------------------
=section Multiplexer

=method mux_init MUX
Called after the multiplexer has added this handler to its
administration.
=cut

sub mux_init($)
{   my ($self, $mux) = @_;
    $self->{IMH_mux} = $mux;
    weaken($self->{IMH_mux});
}

=method mux_remove
Remove the handler from the multiplexer.
=cut

sub mux_remove()
{   delete shift->{IMH_mux};
}

=method mux_read_flagged
Called when the read flag is set for this handler.

When you extend this module, you probably want to override
C<mux_connection()> or C<mux_input()>, not this "raw" method.

=method mux_write_flagged
Called when the write flag is set for this handler; this indicates
that the output buffer is empty hence more data can be sent.

When you extend this module, you probably want to override
C<mux_outputbuffer_empty()>, not this "raw" method.

=method mux_error_flagged
Called when the error flag is set for this handler: data arrived
from the connected service.

When you extend this module, you probably want to override
C<mux_error()>, not this "raw" method.
=cut

sub mux_read_flagged()  { panic "no input expected on ". shift->name }
sub mux_write_flagged() { shift }  # simply ignore write offers
sub mux_error_flagged() { panic "no error text expected on ". shift->name }

=method fdset STATE, READ, WRITE, ERROR
Change the flags for the READ, WRITE and/or ERROR acceptance by the
mux to STATE.
=cut

sub fdset($$$$)
{   my $self = shift;
    $self->{IMH_mux}->fdset($self->{IMH_fileno}, @_);
}

=method close
Stop the handler.
=cut

sub close()
{   my $self = shift;
    $self->{IMH_mux}->remove($self->{IMH_fileno});
}

1;
