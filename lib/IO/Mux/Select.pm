use warnings;
use strict;

package IO::Mux::Select;
use base 'IO::Mux';

use Log::Report 'io-mux';

use List::Util  'min';
use POSIX       'errno_h';

$SIG{PIPE} = 'IGNORE';   # pipes are handled in select

=chapter NAME
IO::Mux::Select - simplify use of select()

=chapter SYNOPSIS
  use IO::Mux::Select;

  my $mux    = IO::Mux::Select->new;
  my $server = IO::Mux::Service::TCP->new(...);
  $mux->add($server);
  $mux->loop;

=chapter DESCRIPTION
Multiplexer implemented around the C<select()> system call. This C<select()>
is usually less powerful and slower than the C<poll()> call (implemented
in M<IO::Mux::Poll>) however probably available on more systems.

=chapter METHODS

=section Constructors
=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $self->{IMS_readers} = '';
    $self->{IMS_writers} = '';
    $self->{IMS_excepts}  = '';
    $self;
}

#-----------------
=section User interface

=method showFlags [FLAGS|(RDFLAGS,WRFLAGS,EXFLAGS)]
Display the select FLAGS (one of the values received from M<selectFlags()>)
or all of these flags. You may also specify three sets of FLAGS explicitly.

When three sets of FLAGS are passed, it will result in three lines
preceeded with labels. With only one set, no label will be used.

The flagged filenos are shown numerically (modulo 10) and positionally.
For instance, if both filehandle 1 and 4 are flagged, the output string
will be C<-1--4>.

=example
  my ($rd, $wr, $er) = $client->selectFlags;
  print "read flags: ",$client->showFlags($rd);

  print $client->showFlags(rd, $wr, $er);
  print $client->showFlags;   # saem result

  print $client->showFlags($client->waitFlags);
=cut

sub _flags2string($);
sub showFlags($;$$)
{   my $self = shift;
    return _flags2string(shift)
        if @_==1;

    my ($rdbits, $wrbits, $exbits) = @_ ? @_ : $self->selectFlags;
    my $rd = _flags2string $rdbits;
    my $wr = _flags2string $wrbits;
    my $ex = _flags2string $exbits;

    <<__SHOW;
  read: $rd
 write: $wr
except: $ex
__SHOW
}

sub _flags2string($)
{   my $bytes = shift;
    use bytes;
    my $bits  = length($bytes) * 8;
    my $out   = '';
    for my $fileno (0..$bits-1)
    {   $out .= vec($bytes, $fileno, 1)==1 ? ($fileno%10) : '-';
    }
    $out =~ s/-+$//;
    length $out ? $out : '(none)';
}

#--------------------------
=section For internal use
=cut

sub fdset($$$$$)
{   my ($self, $fileno, $state, $r, $w, $e) = @_;
    vec($self->{IMS_readers}, $fileno, 1) = $state if $r;
    vec($self->{IMS_writers}, $fileno, 1) = $state if $w;
    vec($self->{IMS_excepts}, $fileno, 1) = $state if $e;
    # trace "fdset(@_), now: " .$self->showFlags($self->waitFlags);
}

sub one_go($$)
{   my ($self, $wait, $heartbeat) = @_;

#   trace "SELECT=".$self->showFlags($self->waitFlags);

    my ($rdready, $wrready, $exready) = ('', '', '');
    my ($numready, $timeleft) = select
       +($rdready = $self->{IMS_readers})
      , ($wrready = $self->{IMS_writers})
      , ($exready = $self->{IMS_excepts})
      , $wait;

#   trace "READY=".$self->showFlags($rdready, $wrready, $exready);

    if($heartbeat)
    {   # can be collected from within heartbeat
        $self->{IMS_select_flags} = [$rdready, $wrready, $exready];
        $heartbeat->($self, $numready, $timeleft)
    }

    unless(defined $numready)
    {   return if $! == EINTR || $! == EAGAIN;
        alert "Leaving loop with $!";
        return 0;
    }

    # Hopefully the regexp improves performance when many slow connections
    $self->_ready(mux_read_flagged  => $rdready) if $rdready =~ m/[^\x00]/;
    $self->_ready(mux_write_flagged => $wrready) if $wrready =~ m/[^\x00]/;
    $self->_ready(mux_except_flagged => $exready) if $exready =~ m/[^\x00]/;
    1;  # success
}

# It would be nice to have an algorithm which is better than O(n)
sub _ready($$)
{   my ($self, $call, $flags) = @_;
    my $handlers = $self->_handlers;
    while(my ($fileno, $conn) = each %$handlers)
    {   $conn->$call($fileno) if (vec $flags, $fileno, 1)==1;
    }
}

=method waitFlags
Returns a list of three: respectively the read, write and error flags
which show how the files are enlisted.
=cut

sub waitFlags() { @{$_[0]}{ qw/IMS_readers IMS_writers IMS_excepts/} }

=method selectFlags
Returns a list of three: respectively the read, write and error flags
which show the file numbers that the internal C<select()> call has
flagged as needing inspection.

This method can, for instance, be used from within the heartbeat routine.
=example
  $mux->loop(\&heartbeat);
  sub heartbeat($$$)
  {   my ($mux, $numready, $timeleft) = @_;
      my ($rd, $rw, $ex) = $mux->selectFlags;
      if(vec($rd, $fileno, 1)==1) {...}
  }
=cut

sub selectFlags() { @{shift->{IMS_select_flags} || []} }

1;

__END__
=chapter DETAILS

=section Implementation limitations

The C<select> system call is very powerful, however the (UNIX) standard
specifies quite a weak subset of the features usually offered. The
standard only requires sockets to be supported. The Windows/cygwin
implementation limits itself to that. Modern UNIX dialects usually
also support normal pipes and file handlers to be attached.

Please help extending the list of OS specific limitations below!

=subsection Limitations on Windows
The C<select()> system call is very limited: it only works on sockets,
not on files or pipes. This means that the process will stall on each
file access and pipe activity.

=subsection Limitations on UNIX/Linux
Be careful with the use of files. You should open files with the
non-stdio version of C<open()>, with option C<O_NONBLOCK>. But even
then, asynchronous support for reading and writing files and pipes
may be lacking on your UNIX dialect.

=back
=cut
