# This code is part of distribution IOMux.  Meta-POD processed with OODoc
# into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package IOMux::Pipe::Read;
use base 'IOMux::Handler::Read';

use warnings;
use strict;

use Log::Report    'iomux';
use Fcntl;
use POSIX          qw/:errno_h :sys_wait_h/;
use File::Basename 'basename';

=chapter NAME
IOMux::Pipe::Read - read from an external command

=chapter SYNOPSIS
  my $mux = IOMux::Select->new;  # or ::Poll

  use IOMux::Open '-|';
  my $pipe = $mux->open('-|', $command, @cmd_options);

  use IOMux::Pipe::Read;
  my $pipe = IOMux::Pipe::Read->new
    ( command => [$command, @cmd_options] );
  $mux->add($pipe);

  $pipe->getline(sub {print "$_[0]\n"});

=chapter DESCRIPTION
In an event driven program, reading is harder to use than writing: the
read will very probably be stalled until data has arrived, so you will
need a callback to handle the resulting data.

=chapter METHODS

=section Constructors

=c_method new %options

=requires command COMMAND|ARRAY
The external command to be executed. Either the COMMAND needs to
parameters, or you need to pass an ARRAY of the command name and
all its parameters.

=default read_size 4096
=default name  '$cmd|'
=cut

sub init($)
{   my ($self, $args) = @_;
    my $command = $args->{command}
        or error __x"no command to run specified in {pkg}", pkg => __PACKAGE__;

    my ($cmd, @cmdopts) = ref $command eq 'ARRAY' ? @$command : $command;
    my $name = $args->{name} = (basename $cmd)."|";

    my ($rh, $wh);
    pipe $rh, $wh
        or fault __x"cannot create pipe for {cmd}", cmd => $name;

    my $pid = fork;
    defined $pid
        or fault __x"failed to fork for pipe {cmd}", cmd => $name;

    if($pid==0)
    {   # client
        close $rh;
        open STDIN,  '<', File::Spec->devnull;
        open STDOUT, '>&', $wh
            or fault __x"failed to redirect STDOUT for pipe {cmd}", cmd=>$name;
        open STDERR, '>', File::Spec->devnull;

        exec $cmd, @cmdopts
            or fault __x"failed to exec for pipe {cmd}", cmd => $name;
    }

    # parent

    $self->{IMPR_pid}    = $pid;
    $args->{read_size} ||= 4096;  # Unix typical BUFSIZ

    close $wh;
    fcntl $rh, F_SETFL, O_NONBLOCK;
    $args->{fh} = $rh;

    $self->SUPER::init($args);
    $self;
}

=c_method bare %options
Creates a pipe, but does not start a process (yet). Used by
M<IOMux::IPC>, which needs three pipes for one process. Returned
is not only a new pipe object, but also a write handle to be
connected to the other side.

All %options which are available to M<IOMux::Handler::Read::new()>
can be used here as well.

=option  read_size INTEGER
=default read_size 4096

=example
  my ($out, $out_rh)
      = IOMux::Pipe::Read->bare(name => 'stdout');
=cut

sub bare($%)
{   my ($class, %args) = @_;
    my $self = bless {}, $class;

    my ($rh, $wh);
    pipe $rh, $wh
        or fault __x"cannot create bare pipe reader";

    $args{read_size} ||= 4096;  # Unix typical BUFSIZ

    fcntl $rh, F_SETFL, O_NONBLOCK;
    $args{fh} = $rh;

    $self->SUPER::init(\%args);
    ($self, $wh);
}

=c_method open $mode, <$cmd, $cmdopts>|<$cmdarray, %options>
Open the pipe to read. $mode is always C<< -| >>.  When you need to
pass additional %options to the implied M<new()>, then you must use
an ARRAY for command name and its optional parameters.
=examples
  my $mux = IOMux::Poll->new;
  $mux->open('-|', 'who', '-H');  # no opts
  $mux->open('-|', ['who', '-H'], %opts);
  $mux->open('-|', 'who');        # no opts
  $mux->open('-|', ['who'], %opts);

=cut

sub open($$@)
{   my ($class, $mode, $cmd) = (shift, shift, shift);
      ref $cmd eq 'ARRAY'
    ? $class->new(command => $cmd, mode => $mode, @_)
    : $class->new(command => [$cmd, @_] , mode => $mode);
}

#-------------------
=section Accessors

=method mode 
The bits of the open mode.
=method childPid 
The process id of the child on the other side of the pipe.
=cut

sub mode()     {shift->{IMPR_mode}}
sub childPid() {shift->{IMPR_pid}}

#-------------------

sub close($)
{   my ($self, $cb) = @_;
    my $pid = $self->{IMPR_pid}
        or return $self->SUPER::close($cb);

    waitpid $pid, WNOHANG;
    local $?;
    $self->SUPER::close($cb);
}

1;
