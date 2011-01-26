use warnings;
use strict;

package IO::Mux::Pipe::Write;
use base 'IO::Mux::Handler::Write';

use Log::Report    'io-mux';
use Fcntl;
use POSIX          qw/:errno_h :sys_wait_h/;
use File::Spec     ();
use File::Basename 'basename';

use constant PIPE_BUF_SIZE => 4096;

=chapter NAME
IO::Mux::Pipe::Write - write to an external command

=chapter SYNOPSIS
  my $mux = IO::Mux::Select->new;  # or ::Poll

  use IO::Mux::Open '|-';
  my $pipe = $mux->open('|-', $command, @cmd_options);

  use IO::Mux::Pipe::Write;
  my $pipe = IO::Mux::Pipe::Write->new
    (command => [$command, @cmd_options]);
  $mux->add($pipe);

  $pipe->write($text);
  $pipe->print($text);

  write $pipe $text;
  print $pipe $text;

=chapter DESCRIPTION
In an event driven program, you must be careful with every Operation
System call, because it can block the event mechanism, hence the program
as a whole. Often you can be lazy with writes, because its communication
buffers are usually working quite asynchronous... but not always. You
may skip the callbacks for small writes and prints.

=chapter METHODS

=section Constructors

=c_method new OPTIONS

=requires command COMMAND|ARRAY
The external command to be executed. Either the COMMAND needs to
parameters, or you need to pass an ARRAY of the command name and
all its parameters.

=default name '|$cmd'
=cut

sub init($)
{   my ($self, $args) = @_;

    my $command = $args->{command}
        or error __x"no command to run specified in {pkg}", pkg => __PACKAGE__;

    my ($cmd, @cmdopts) = ref $command eq 'ARRAY' ? @$command : $command;
    my $name = $args->{name} = '|'.(basename $cmd);

    my ($rh, $wh);
    pipe $rh, $wh
        or fault __x"cannot create pipe for {cmd}", cmd => $name;

    my $pid = fork;
    defined $pid
        or fault __x"failed to fork for pipe {cmd}", cmd => $name;

    if($pid==0)
    {   # client
        close $wh;
        open STDIN, '<&', $rh
            or fault __x"failed to redirect STDIN for pipe {cmd}", cmd => $name;
        open STDOUT, '>', File::Spec->devnull;
        open STDERR, '>', File::Spec->devnull;

        exec $cmd, @cmdopts
            or fault __x"failed to exec for pipe {cmd}", cmd => $name;
    }
    $self->{IMPW_pid} = $pid;

    # parent

    close $rh;
    fcntl $wh, F_SETFL, O_NONBLOCK;
    $args->{fh} = $wh;

    $self->SUPER::init($args);
    $self;
}

=c_method bare OPTIONS
Creates a pipe, but does not start a process (yet). Used by
M<IO::Mux::IPC>, which needs three pipes for one process. Returned
is not only a new pipe object, but also a read handle to be
connected to the other side.

All OPTIONS which are available to M<IO::Mux::Handler::Write::new()>
can be used here as well.

=option  read_size INTEGER
=default read_size 4096

=example
  my ($in, $in_rh)
      = IO::Mux::Pipe::Write->bare(name => 'stdin');
=cut

sub bare($%)
{   my ($class, %args) = @_;
    my $self = bless {}, $class;

    my ($rh, $wh);
    pipe $rh, $wh
        or fault __x"cannot create bare pipe writer";

    $args{read_size} ||= 4096;

    fcntl $wh, F_SETFL, O_NONBLOCK;
    $args{fh} = $wh;

    $self->SUPER::init(\%args);
    ($self, $rh);
}

=c_method open MODE, (CMD, CMDOPTS)|(CMDARRAY, OPTIONS)
Open the pipe to write. MODE is always C<< -| >>.  When you need to
pass additional OPTIONS to the implied M<new()>, then you must use
an ARRAY for command name and its optional parameters.
=examples
  my $mux = IO::Mux::Poll->new;
  $mux->open('|-', 'lpr', '-#4');  # no opts
  $mux->open('|-', ['lpr', '-#4'], %opts);
  $mux->open('|-', 'lpr');        # no opts
  $mux->open('|-', ['lpr'], %opts);

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

sub mode()     {shift->{IMPW_mode}}
sub childPid() {shift->{IMPW_pid}}

#-------------------

sub close($)
{   my ($self, $cb) = @_;
    my $pid = $self->{IMPW_pid}
        or return $self->SUPER::close($cb);

    waitpid $pid, WNOHANG;
    local $?;
    $self->SUPER::close($cb);
}



1;
