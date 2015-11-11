use warnings;
use strict;

package IOMux::Handler::Read;
use base 'IOMux::Handler';

use Log::Report    'iomux';
use Fcntl;
use POSIX          'errno_h';
use File::Basename 'basename';

=chapter NAME
IOMux::Handler::Read - any mux reader

=chapter SYNOPSIS
  # only use extensions

=chapter DESCRIPTION
This base-class defines the interface which every reader offers.

=chapter METHODS

=section Constructors

=c_method new %options

=option  read_size INTEGER
=default read_size 32768
=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $self->{IMHR_read_size} = $args->{read_size} || 32768;
    $self->{IMHR_inbuf}     = '';
    $self;
}

#-------------------
=section Accessors
=method readSize [$integer]
The number of bytes requested at each read.
=cut

sub readSize(;$)
{   my $self = shift;
    @_ ? $self->{IMHR_read_size} = shift : $self->{IMHR_read_size};
}

#-----------------------
=section User interface

=subsection Reading

=method readline $callback
Read a single line (bytes upto a LF or CRLF). After the whole line
has arrived, the $callback will be invoked with the received line as
parameter. that line is terminated by a LF (\n), even when the file
contains CRLF or CR endings.

At end of file, the last fragment will be returned.
=cut

sub readline($)
{   my ($self, $cb) = @_;
    if($self->{IMHR_inbuf} =~ s/^([^\r\n]*)(?:\r?\n)//)
    {   return $cb->($self, "$1\n");
    }
    if($self->{IMHR_eof})
    {   # eof already before readline and no trailing nl
        my $line = $self->{IMHR_inbuf};
        $self->{IMHR_inbuf} = '';
        return $cb->($self, $line);
    }

    $self->{IMHR_read_more} = sub
      { my ($in, $eof) = @_;
        if($eof)
        {   delete $self->{IMHR_read_more};
            my $line = $self->{IMHR_inbuf};
            $self->{IMHR_inbuf} = '';
            return $cb->($self, $line);
        }
        ${$_[0]} =~ s/^([^\r\n]*)\r?\n//
            or return;
        delete $self->{IMHR_read_more};
        $cb->($self, "$1\n");
      };
}

=method slurp $callback
Read all remaining data from a resource. After everything has been
read, it will be returned as SCALAR (string reference)

=example
  my $pwd  = $mux->open('<', '/etc/passwd');
  my $data = $pwd->slurp;
  my $size = length $$data;
=cut

sub slurp($)
{   my ($self, $cb) = @_;

    if($self->{IMHR_eof})   # eof already before readline
    {   my $in    = $self->{IMHR_inbuf} or return $cb->($self, \'');
        my $bytes = $$in;  # does copy the bytes. Cannot help it easily
        $$in      = '';
        return $cb->($self, \$bytes);
    }

    $self->{IMHR_read_more} = sub
      { my ($in, $eof) = @_;
        $eof or return;
        delete $self->{IMHR_read_more};
        my $bytes = $$in;  # does copy the bytes
        $$in      = '';
        $cb->($self, \$bytes);
      };
}

#-------------------------
=section Multiplexer

=subsection Reading
=cut

sub muxInit($)
{   my ($self, $mux) = @_;
    $self->SUPER::muxInit($mux);
    $self->fdset(1, 1, 0, 0);
}

sub muxReadFlagged($)
{   my $self = shift;

    my $bytes_read
      = sysread $self->fh, $self->{IMHR_inbuf}, $self->{IMHR_read_size}
         , length($self->{IMHR_inbuf});

    if($bytes_read) # > 0
    {   $self->muxInput(\$self->{IMHR_inbuf});
    }
    elsif(defined $bytes_read)   # == 0
    {   $self->fdset(0, 1, 0, 0);
        $self->muxEOF(\$self->{IMHR_inbuf});
    }
    elsif($!==EINTR || $!==EAGAIN || $!==EWOULDBLOCK)
    {   # a bit unexpected, but ok
    }
    else
    {   warning __x"read from {name} closed unexpectedly: {err}"
          , name => $self->name, err => $!;
        $self->close;
    }
}

=method muxInput $buffer
Called when new input has arrived on the input. It is passed a
B<reference> to the input $buffer. It must remove any input that
it you have consumed from the $buffer, and leave any partially
received data in there.

=example
  sub muxInput
  {   my ($self, $inbuf) = @_;

      # Process each whole line in the input, leaving partial
      # lines in the input buffer for more.
      while($$inbuf =~ s/^(.*?)\r?\n// )
      {   $self->process_command($1);
      }
  }
=cut

sub muxInput($)
{   my ($self, $inbuf) = @_;
    return $self->{IMHR_read_more}->($inbuf, 0)
        if $self->{IMHR_read_more};
}

=method muxEOF $input
This is called when an end-of-file condition is present on the handle.
Like M<muxInput()>, it is also passed a reference to the input
buffer. You should consume the entire buffer or else it will just be lost.
=cut

sub muxEOF($)
{   my ($self, $inbuf) = @_;
    $self->{IMHR_eof}   = 1;
    $self->{IMHR_read_more}->($inbuf, 1)
        if $self->{IMHR_read_more};
}

1;
