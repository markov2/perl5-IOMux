use warnings;
use strict;

package IO::Mux::Connection;
use base 'IO::Mux::Handler';

use Log::Report 'io-mux';

=chapter NAME
IO::Mux::Connection - data stream via select

=chapter SYNOPSIS

=chapter DESCRIPTION

=chapter METHODS

=section Constructors
=cut

#-------------------------
=section Multiplexer

=method write SCALAR
Write a string (passed as reference) to the other side of the connection.
You can better use the M<print()> or M<printf()> methods.
=cut

sub write($) {panic}

=method print STRING|SCALAR|LIST|ARRAY
Send one or more lines to the output. The data is packed into a
single string first. The ARRAY (of strings) and SCALAR (ref string)
choices are available for efficiency.

For convenience, when the file handle is added to the multiplexer, it
is tied to a special class which intercepts all attempts to write to
the file handle.  Thus, you can use C<print()> and C<printf()> to send
output to the handle in a normal manner:

=examples
  $conn->print($some_text);
  $conn->print(\$some_text);

  my $fh = $conn->socket;
  print $fh "%s%d%X", $foo, $bar, $baz;
=cut

sub print(@)
{   my $self = shift;
    $self->write( !ref $_[0] ? (@_>1 ? \join('',@_) : \shift)
                : ref $_[0] eq 'ARRAY' ? \join('',@{$_[0]}) : $_[0] );
}

=method printf FORMAT, PARAMS
=examples
    $conn->printf("%s%d%X", $foo, $bar, $baz);

    my $fh = $conn->socket;
    $fh->printf("%s%d%X", $foo, $bar, $baz);
=cut

sub printf($@)
{   my $self = shift;
    $self->write(\sprintf(@_));
}

=method mux_input BUFFER
Called when new input has arrived on the input. It is passed a
B<reference> to the input BUFFER. It must remove any input that
it you have consumed from the BUFFER, and leave any partially
received data in there.

=example
  sub mux_input
  {   my ($self, $inbuf) = @_;

      # Process each whole line in the input, leaving partial
      # lines in the input buffer for more.
      while($$inbuf =~ s/^(.*?)\r?\n// )
      {   $self->process_command($1);
      }
  }
=cut

sub mux_input($)
{   my ($self, $inbuf) = @_;
    error __x"{count} bytes of input arrived on {name}, but not handled"
       , count => length($$inbuf), name => $self->name;
}

=method mux_error BUFFER
Called when new input has arrived on the error channel. It is passed a
B<reference> to the error BUFFER. It must remove any input that it you
have consumed from the BUFFER, and leave any partially received data
in there for more text to arrive.

=example
  # actually, this is the default behavior
  sub mux_error
  {   my ($self, $errbuf) = @_;
      print STDERR $$errbuf;
      $$errbuf = '';
  }
=cut

sub mux_error($)
{   my ($self, $errbuf) = @_;
    print STDERR $$errbuf;
    $$errbuf = '';
}

=method mux_outbuffer_empty
Called after all pending output has been written to the file descriptor.
You may use this callback to produce more data to be written, of which
a reference must be returned.

When the returned SCALAR points to an empty string, then the method
will be called again in the next loop. However, when undef is returned,
the check for the write bit gets disabled.
=cut

sub mux_outbuffer_empty() {undef}

=method mux_eof INPUT
This is called when an end-of-file condition is present on the
This is does not nessecarily mean that the descriptor has
been closed, as the other end of a socket could have used C<shutdown>
to close just half of the socket, leaving us free to write data back
down the still open half.  Like M<mux_input()>, it is also passed a
reference to the input buffer. You should consume the entire buffer or
else it will just be lost.

=example
In this example, we send a final reply to the other end of the socket,
and then shut it down for writing.  Since it is also shut down for reading
(implicly by the EOF condition), it will be closed once the output has
been sent, after which the mux_close callback will be called.

  sub mux_eof
  {   my ($self, $ref_input) = @_;
      print $fh "Well, goodbye then!\n";
      $self->shutdown(1);
  }
=cut

sub mux_eof($) {shift}

=method mux_close MUX, FILEHANDLE
Called when a handle has been completely closed. At the time that
C<mux_close> is called, the handle will have been removed from the
multiplexer and is already untied.

Of course, the FILEHANDLE cannot be used anymore. However, it may
have been used in some kind of administration for the connection
on package level.
=cut

sub mux_close($$) {shift}

=method mux_timeout
Called when a timer expires on the FILEHANDLE.

Use M<timeout()> to set (or clear) a timeout.
When new data is sent or received on the FILEHANDLE, that will B<not>
expire the timeout.
=cut

sub mux_timeout()
{   my $self = shift;
    error __x"timeout set on {name} but not handled", name => $self->name;
}

1;
