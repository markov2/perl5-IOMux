use warnings;
use strict;

package IO::Mux::Bundle;
use base 'IO::Mux::Handler::Read', 'IO::Mux::Handler::Write';

use Log::Report 'io-mux';

##### WORK IN PROGRESS!

=chapter NAME
IO::Mux::Bundle - logical group of connections

=chapter SYNOPSIS
  my $syscall = IO::Mux::Bundle::Parallel->new(...);
  $mux->add($syscall);

=chapter DESCRIPTION
A bundle is a set of file handles, so a convenience wrapper around
a set of different connections with a single purpose.

=chapter METHODS

=section Constructors

=c_method new OPTIONS
The C<stdin>, C<stdout> and C<stderr> objects are from the perspective
of the other side.

=requires stdin  M<IO::Mux::Handler::Write>  object
=requires stdout M<IO::Mux::Handler::Read>   object

=option   stderr M<IO::Mux::Handler::Read>   object
=default  stderr <undef>
=cut

sub init($)
{   my ($self, $args) = @_;

    # stdin to be a writer is a bit counter-intuitive, therefore some
    # extra tests.
    my $name = $args->{name};

    my $in   = $self->{IMB_stdin}  = $args->{stdin}
        or error __x"no stdin handler for {name}", name => $name;
    UNIVERSAL::isa($in, 'IO::Mux::Handler::Write')
        or error __x"stdin {name} is not at writer", name => $name;

    my $out = $self->{IMB_stdout} = $args->{stdout}
        or error __x"no stdout handler for {name}", name => $name;
    UNIVERSAL::isa($out, 'IO::Mux::Handler::Read')
        or error __x"stdout {name} is not at reader", name => $name;

    my $err = $self->{IMB_stderr} = $args->{stderr};
    !$err || UNIVERSAL::isa($out, 'IO::Mux::Handler::Read')
        or error __x"stderr {name} is not at reader", name => $name;

    my @filenos = ($in->fileno, $out->fileno);
    push @filenos, $err->fileno if $err;

    $self->{IMB_filenos} = \@filenos;
    $args->{name} .= ', ('.join(',',@filenos).')';

    $self->SUPER::init($args);
    $self;
}

#---------------
=section Accessors
=method stdin
=method stdout
=method stderr
=method connections
=cut

sub stdin()  {shift->{IMB_stdin}}
sub stdout() {shift->{IMB_stdout}}
sub stderr() {shift->{IMB_stderr}}

sub connections()
{   my $self = shift;
    ( $self->{IMB_stdin}
    , $self->{IMB_stdout},
    , ($self->{IMB_stderr} ? $self->{IMB_stderr} : ())
    );
}

#---------------

# say, print and printf use write()
sub write(@)     { shift->{IMB_stdin}->write(@_) }
sub mux_outbuffer_empty() { shift->{IMB_stdin}->mux_outbuffer_empty(@_) }
sub mux_output_waiting()  { shift->{IMB_stdin}->mux_output_waiting(@_) }
sub mux_write_flagged()   { shift->{IMB_stdin}->mux_write_flagged(@_) }

sub readline(@)  { shift->{IMB_stdout}->readline(@_)  }
sub slurp(@)     { shift->{IMB_stdout}->slurp(@_)     }
sub mux_input($) { shift->{IMB_stdout}->mux_input(@_) }
sub mux_eof($)   { shift->{IMB_stdout}->mux_eof(@_)   }

sub mux_read_flagged($)
{   my ($self, $fileno) = @_;
    if(my $e = $self->{IMB_stderr})
    {   return $e->mux_read_flagged(@_)
            if $fileno==$e->fileno;
    }
    $self->{IMB_stdin}->mux_read_flagged(@_);
}

sub timeout() { shift->{IMB_stdin}->timeout(@_) }

sub close(;$)
{   my ($self, $cb) = @_;
    my $close_error = sub 
       { if(my $err = $self->{IMB_stderr}) { $err->close($cb) }
         elsif($cb) { $cb->($self) }
       };

    my $close_out  = sub
       { if(my $out = $self->{IMB_stdout}) { $out->close($close_error) }
         else { $close_error->() }
       };

    if(my $in = $self->{IMB_stdin}) { $in->close($close_out) }
    else { $close_out->() }
}

sub mux_remove()
{   my $self = shift;
    $_->mux_remove for $self->connections;
    trace "mux remove bundle ".$self->name;
}

sub mux_init($)
{   my ($self, $mux) = @_;

    $_->mux_init($mux, $self)  # I want control
        for $self->connections;

    trace "mux add bundle ".$self->name;
}

#---------------
=section Multiplexer
=subsection Errors

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

#---------------

sub show()
{   my $self = shift;
    join "\n", map({$_->show} $self->connections),'';
}

sub fdset() {panic}

1;
