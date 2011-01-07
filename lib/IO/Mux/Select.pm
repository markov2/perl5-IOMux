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
  my $server = IO::Mux::Socket::UDP->new(...);
  $mux->add($server);

=chapter DESCRIPTION

=chapter METHODS

=section Constructors
=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $self->{IMS_readers}  = '';
    $self->{IMS_writers}  = '';
    $self->{IMS_errors}   = '';
    $self;
}

#-------------
=section Handle administration
=cut

sub fdset($$$$$)
{   my ($self, $conn, $fileno, $state, $r, $w, $e) = @_;
    vec($self->{IMS_readers}, $fileno, 1) = $state if $r;
    vec($self->{IMS_writers}, $fileno, 1) = $state if $w;
    vec($self->{IMS_errors},  $fileno, 1) = $state if $e;
}

#------------------
=section Runtime
=cut

sub one_go($$)
{   my ($self, $wait, $heartbeat) = @_;

    my ($rdready, $wrready, $erready) = ('', '', '');
    my ($numready, $timeleft) = select
       +($rdready = $self->{IMS_readers})
      , ($wrready = $self->{IMS_writers})
      , ($erready = $self->{IMS_errors})
      , $wait;

    if($heartbeat)
    {   # can be collected from within heartbeat
        $self->{IMS_select_flags} = [$rdready,$wrready,$erready];
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
    $self->_ready(mux_error_flagged => $erready) if $erready =~ m/[^\x00]/;
    1;  # success
}

# It would be nice to have an algorithm which is better than O(n)
sub _ready($$)
{   my ($self, $call, $flags) = @_;
    my $handlers = $self->_handlers;
    while(my ($fileno, $conn) = each %$handlers)
    {   $conn->$call if (vec $flags, $fileno, 1)==1;
    }
}

=method selectFlags
Returns a list of three: respectively the read, write and error flags.
This method can be used from within the hearbeat routine.
=example
  $mux->loop(\&hb);
  sub hb($$$)
  {   my ($mux, $numready, $timeleft) = @_;
      my ($rd, $rw, $er) = $mux->selectFlags;
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
