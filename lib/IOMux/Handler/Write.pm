use warnings;
use strict;

package IOMux::Handler::Write;
use base 'IOMux::Handler';

use Log::Report 'iomux';
use Fcntl;
use POSIX 'errno_h';
use File::Spec       ();;
use File::Basename   'basename';

use constant PIPE_BUF_SIZE => 4096;

=chapter NAME
IOMux::Handler::Write - any mux writer

=chapter SYNOPSIS
  # only use extensions

=chapter DESCRIPTION
In an event driven program, you must be careful with every Operation
System call, because it can block the event mechanism, hence the program
as a whole. Often you can be lazy with writes, because its communication
buffers are usually working quite asynchronous... but not always. You
may skip the callbacks for small writes and prints.

=chapter METHODS

=section Constructors

=c_method new OPTIONS

=option  write_size INTEGER
=default write_size 4096

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $self->{IMHW_write_size} = $args->{write_size} || 4096;
    $self;
}

#-------------------
=section Accessors

=method writeSize [INTEGER]
The number of bytes written at each write.
=cut

sub writeSize(;$)
{   my $self = shift;
    @_ ? $self->{IMHW_write_size} = shift : $self->{IMHW_write_size};
}

#-----------------------
=section User interface

=subsection Writing

=method print STRING|SCALAR|LIST|ARRAY
Send one or more lines to the output. The data is packed into a
single string first. The ARRAY (of strings) and SCALAR (ref string)
choices are available for efficiency.

=examples
  $conn->print($some_text);
  $conn->print(\$some_text);

  my $fh = $conn->fh;
  print $fh "%s%d%X", $foo, $bar, $baz;
=cut

sub print(@)
{   my $self = shift;
    $self->write( !ref $_[0] ? (@_>1 ? \join('',@_) : \shift)
                : ref $_[0] eq 'ARRAY' ? \join('',@{$_[0]}) : $_[0] );
}

=method say STRING|SCALAR|LIST|ARRAY
Like M<print()> but adding a newline at the end.
=cut

sub say(@)
{   my $self = shift;
    $self->write
      ( !ref $_[0] ? \join('',@_, "\n")
      : ref $_[0] eq 'ARRAY' ? \join('',@{$_[0]}, "\n")
      : $_[0]."\n"
      );
}

=method printf FORMAT, PARAMS
=examples
    $conn->printf("%s%d%X", $foo, $bar, $baz);

    my $fh = $conn->fh;
    $fh->printf("%s%d%X", $foo, $bar, $baz);
=cut

sub printf($@)
{   my $self = shift;
    $self->write(\sprintf(@_));
}

=method write SCALAR, [MORE]
Send the content of the string, passed as reference in SCALAR. You
probably want to use M<print()> or M<printf()>.  You may provide
a code reference to produce MORE info when the output buffer get
empty.
=cut

sub write($;$)
{   my ($self, $blob, $more) = @_;

    if(exists $self->{IMHW_outbuf})
    {   ${$self->{IMHW_outbuf}} .= $$blob;
        $self->{IMHW_more} = $more;
        return;
    }

    my $bytes_written = syswrite $self->fh, $$blob, $self->{IMHW_write_size};
    if(!defined $bytes_written)
    {   return if $!==EWOULDBLOCK || $!==EINTR;
        warning __x"write to {name} failed: {err}"
          , name => $self->name, err => $!;
        $self->close;
        return
    }

    if($bytes_written==length $$blob)
    {   # we got rit of all at once.  Cheap!
        $more->($self) if $more;
        $self->{IMHW_is_closing}->($self)
            if $self->{IMHW_is_closing};
        return;
    }

    substr($$blob, 0, $bytes_written) = '';
    $self->{IMHW_outbuf} = $blob;
    $self->{IMHW_more} = $more;
    $self->fdset(1, 0, 1, 0);
}


#-------------------------
=section Multiplexer

=subsection Writing

=cut

sub mux_init($)
{   my ($self, $mux) = @_;
    $self->SUPER::mux_init($mux);
    $self->fdset(1, 0, 1, 0);
}

sub mux_write_flagged()
{   my $self   = shift;
    my $outbuf = $self->{IMHW_outbuf};
    unless($outbuf)
    {   $outbuf = $self->{IMHW_outbuf} = $self->mux_outbuffer_empty;
        unless(defined $outbuf)
        {   # nothing can be produced on call, so we don't need the
            # empty-write signals on the moment (enabled at next write)
            $self->fdset(0, 0, 1, 0);
            return;
        }
        unless(length $$outbuf)
        {   # retry at next interval
            delete $self->{IMHW_outbuf};
            return;
        }
    }

    my $bytes_written = syswrite $self->fh, $$outbuf, $self->{IMHW_write_size};
    if(!defined $bytes_written)
    {   # should happen, but we're kind
        return if $! == EWOULDBLOCK || $! == EINTR || $! == EAGAIN;
        warning __x"write to {name} failed: {err}"
          , name => $self->name, err => $!;
        $self->close;
    }
    elsif($bytes_written==length $$outbuf)
         { delete $self->{IMHW_outbuf} }
    else { substr($$outbuf, 0, $bytes_written) = '' }
}

=method mux_outbuffer_empty
Called after all pending output has been written to the file descriptor.
You may use this callback to produce more data to be written.

When this method is not overruled, the multiplexer will stop listening
to the write flag until an explicit M<write()> gets executed.

=example
  package My::Service;
  use base 'IOMux::Net::TCP';

  sub mux_outbuffer_empty()
  {   my $self = shift;
      if(my $data = $self->produce_more_data)
      {   $self->write(\$data);
      }
      else
      {   $self->SUPER::mux_outbuffer_empty;
      }
  }
=cut

sub mux_outbuffer_empty()
{   my $self = shift;
    my $more = delete $self->{IMHW_more};
    return $more->() if defined $more;

    $self->fdset(0, 0, 1, 0);
    $self->{IMHW_is_closing}->($self)
        if $self->{IMHW_is_closing};
}

=method mux_output_waiting
Returns true is there is output queued.
=cut

sub mux_output_waiting() { exists shift->{IMHW_outbuf} }

# Closing write handlers is a little complex: it should be delayed
# until the write buffer is empty.

sub close(;$)
{   my ($self, $cb) = @_;
    if($self->{IMHW_outbuf})
    {   # delay closing until write buffer is empty
        $self->{IMHW_is_closing} = sub { $self->SUPER::close($cb)};
    }
    else
    {   # can close immediately
        $self->SUPER::close($cb);
    }
}

1;
