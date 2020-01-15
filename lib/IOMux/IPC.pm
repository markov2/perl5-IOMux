# This code is part of distribution IOMux.  Meta-POD processed with OODoc
# into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package IOMux::IPC;
use base 'IOMux::Bundle';

use warnings;
use strict;

use Log::Report    'iomux';

use IOMux::Pipe::Read  ();
use IOMux::Pipe::Write ();

use POSIX              qw/:errno_h :sys_wait_h/;
use File::Basename     'basename';

=chapter NAME
IOMux::IPC - exchange data with external command

=chapter SYNOPSIS
  my $mux = IOMux::Select->new;  # or ::Poll

  use IOMux::Open '|-|', '|=|';
  my $pipe = $mux->open('|-|', $cmd, @cmdopts);

  use IOMux::IPC;
  my $ipc = IOMux::IPC->new(command => [$cmd, @cmdopts]);
  $mux->add($ipc);

  $pipe->getline(sub {print "$_[0]\n"});

=chapter DESCRIPTION
With this handler, you set-up a two way communication between the
current process and some other process. This is not easy to program:
you may need to play with timeouts every once in a while.

This module is based on M<IOMux::Bundle>, because it will use
two or three pipes to facilitate the communication.

=chapter METHODS

=section Constructors

=c_method new %options

=requires command COMMAND|ARRAY
The external command to be executed. Either the COMMAND needs to
parameters, or you need to pass an ARRAY of the command name and
all its parameters.

=default name  '|$cmd|'

=option  mode C<< |-| >> or  C<< |=| >>
=default mode C<< |=| >>
In the C<< |-| >> mode, only STDIN and STDOUT are processed. Specifing
the C<< |=| >> has the same effect as setting the C<errors> option: open
a connection for STDERR as well.

=option  errors BOOLEAN
=default errors <true>
Include the stderr channel in the communication as well. These will
be printed to STDERR by default.

=cut

sub init($)
{   my ($self, $args) = @_;
    my $command = $args->{command}
        or error __x"no command to run specified in {pkg}", pkg => __PACKAGE__;

    my ($cmd, @cmdopts) = ref $command eq 'ARRAY' ? @$command : $command;
    my $name   = $args->{name} = '|'.(basename $cmd).'|';

    my $mode   = $args->{mode} || '|-|';
    my $errors = $args->{errors};
       if($mode eq '|=|') { $errors //= 1 }
    elsif($mode eq '|-|') { $mode = '|=|' if $errors }
    else
    {   error __x"unknown mode {mode} for {pkg}"
          , mode => $mode, pkg => __PACKAGE__;
    }

    ($args->{stdin},  my $in_rh)
       = IOMux::Pipe::Write->bare(name => 'stdin');
    ($args->{stdout}, my $out_wh)
       = IOMux::Pipe::Read->bare(name => 'stdout');
    ($args->{stderr}, my $err_wh)
      = $errors ? IOMux::Pipe::Read->bare(name => 'stderr') : ();

    my $pid = fork;
    defined $pid
        or fault __x"failed to fork for ipc {cmd}", cmd => $name;

    if($pid==0)
    {   # client
        open STDIN,  '<&', $in_rh
            or fault __x"failed to redirect STDIN for ipc {cmd}", cmd=>$name;
        open STDOUT, '>&', $out_wh
            or fault __x"failed to redirect STDOUT for ipc {cmd}", cmd=>$name;
        if($err_wh)
        {   open STDERR, '>&', $err_wh
                or fault __x"failed to redirect STDERR for ipc {cmd}"
                   , cmd => $name;
        }
        else
        {   open STDERR, '>', File::Spec->devnull;
        }

        exec $cmd, @cmdopts
            or fault __x"failed to exec for pipe {cmd}", cmd => $name;
    }

    # parent

    close $in_rh;
    close $out_wh;
    close $err_wh if $err_wh;

    $self->{IMI_pid} = $pid;
    $self->SUPER::init($args);
    $self;
}

=c_method open $mode, <$cmd, $cmdopts>|<$cmdarray, %options>
Open the pipe to read. $mode is either C<< |-| >> or C<< |=| >>.  When you
need to pass additional %options to the implied M<new()>, then you must
use an ARRAY for command name and its optional parameters.
=examples
  my $mux = IOMux::Poll->new;
  $mux->open('|-|', 'sort', '-u');  # no opts
  $mux->open('|-|', ['sort', '-u'], %opts);
  $mux->open('|-|', 'sort');        # no opts
  $mux->open('|-|', ['sort'], %opts);

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

sub mode()     {shift->{IMI_mode}}
sub childPid() {shift->{IMI_pid}}

#-------------------

sub close($)
{   my ($self, $cb) = @_;
    waitpid $self->{IMI_pid}, WNOHANG;
    local $?;
    $self->SUPER::close($cb);
}

1;
