# This code is part of distribution IOMux.  Meta-POD processed with OODoc
# into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package IOMux::Bundle;
use base 'IOMux::Handler::Read', 'IOMux::Handler::Write';

use warnings;
use strict;

use Log::Report 'iomux';

use Scalar::Util   qw(blessed);

##### WORK IN PROGRESS!

=chapter NAME
IOMux::Bundle - logical group of connections

=chapter SYNOPSIS
  my $syscall = IOMux::Bundle::Parallel->new(...);
  $mux->add($syscall);

=chapter DESCRIPTION
A bundle is a set of file handles, so a convenience wrapper around
a set of different connections with a single purpose.

Take stdin, stdout and stderr from the viewpoint of a client process
which starts an external command.  So, B<stdin will write> to the stdin
of the remote process, etc.

=chapter METHODS

=section Constructors

=c_method new %options
The C<stdin>, C<stdout> and C<stderr> objects are from the perspective
of the other side.

=requires stdin  M<IOMux::Handler::Write>  object
=requires stdout M<IOMux::Handler::Read>   object

=option   stderr M<IOMux::Handler::Read>   object
=default  stderr <undef>
=cut

sub init($)
{   my ($self, $args) = @_;

    # stdin to be a writer is a bit counter-intuitive, therefore some
    # extra tests.

    my @filenos;
    my $name = $args->{name};

    my $in   = $self->{IMB_stdin}  = $args->{stdin}
        or error __x"no stdin handler for {name}", name => $name;
    blessed $in && $in->isa('IOMux::Handler::Write')
        or error __x"stdin {name} is not at writer", name => $name;
    push @filenos, $in->fileno;

    my $out = $self->{IMB_stdout} = $args->{stdout}
        or error __x"no stdout handler for {name}", name => $name;
    blessed $out && $out->isa('IOMux::Handler::Read')
        or error __x"stdout {name} is not at reader", name => $name;
    push @filenos, $out->fileno;

    if(my $err = $self->{IMB_stderr} = $args->{stderr})
    {   blessed $err && $err->isa('IOMux::Handler::Read')
            or error __x"stderr {name} is not at reader", name => $name;
        push @filenos, $err->fileno;
    }

    $args->{name}       .= ', ('.join(',',@filenos).')';

    $self->SUPER::init($args);

    $self->{IMB_filenos} = \@filenos;
    $self;
}

#---------------
=section Accessors

=method stdin 
=method stdout 
=method stderr 
=cut

sub stdin()  {shift->{IMB_stdin}}
sub stdout() {shift->{IMB_stdout}}
sub stderr() {shift->{IMB_stderr}}

=method connections 
=cut

sub connections()
{   my $s = shift;
    grep defined, $s->{IMB_stdin}, $s->{IMB_stdout}, $s->{IMB_stderr};
}

#---------------

# say, print and printf use write()
sub write(@)            { shift->{IMB_stdin}->write(@_) }
sub muxOutbufferEmpty() { shift->{IMB_stdin}->muxOutbufferEmpty(@_) }
sub muxOutputWaiting()  { shift->{IMB_stdin}->muxOutputWaiting(@_)  }
sub muxWriteFlagged()   { shift->{IMB_stdin}->muxWriteFlagged(@_)   }

sub readline(@)         { shift->{IMB_stdout}->readline(@_) }
sub slurp(@)            { shift->{IMB_stdout}->slurp(@_)    }
sub muxInput($)         { shift->{IMB_stdout}->muxInput(@_) }
sub muxEOF($)           { shift->{IMB_stdout}->muxEOF(@_)   }

sub muxReadFlagged($)
{   my ($self, $fileno) = @_;
    if(my $e = $self->{IMB_stderr})
    {   return $e->muxReadFlagged(@_)
            if $fileno==$e->fileno;
    }
    $self->{IMB_stdin}->muxReadFlagged(@_);
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

sub muxRemove()
{   my $self = shift;
    $_->muxRemove for $self->connections;
    trace "mux remove bundle ".$self->name;
}

sub muxInit($)
{   my ($self, $mux) = @_;

    $_->muxInit($mux, $self)  # I want control
        for $self->connections;

    trace "mux add bundle ".$self->name;
}

#---------------
=section Multiplexer

=subsection Errors

=method muxError $buffer
Called when new input has arrived on the error channel. It is passed a
B<reference> to the error $buffer. It must remove any input that it you
have consumed from the $buffer, and leave any partially received data
in there for more text to arrive.
    
=example
  # actually, this is the default behavior
  sub muxError
  {   my ($self, $errbuf) = @_;
      print STDERR $$errbuf;
      $$errbuf = '';
  } 
=cut
 
sub muxError($)
{   my ($self, $errbuf) = @_;
    print STDERR $$errbuf;
    $$errbuf = '';
}

#---------------

sub show()
{   my $self = shift;
    join "\n", (map $_->show, $self->connections), '';
}

sub fdset() {panic}

1;
