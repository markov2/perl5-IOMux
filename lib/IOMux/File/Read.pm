use warnings;
use strict;

package IOMux::File::Read;
use base 'IOMux::Handler::Read';

use Log::Report    'iomux';
use Fcntl;
use File::Basename 'basename';

=chapter NAME
IOMux::File::Read - write to file

=chapter SYNOPSIS
  my $mux = IOMux::Select->new;  # or ::Poll

  use IOMux::Open '<';
  my $file = $mux->open('<', $filename);

  use IOMux::File::Read;
  my $file = IOMux::File::Read->new(file => $filename);
  $mux->add($file);

  $file->getline(sub {print "\n"});

=chapter DESCRIPTION
In an event driven program, reading is harder to use than writing: the
read will very probably be stalled until data has arrived, so you will
need a callback to handle the resulting data.

=chapter METHODS

=section Constructors

=c_method new OPTIONS

=requires file FILENAME|HANDLE

=default  name '<$file'

=option   mode '<'
=default  mode '<'
For now, the mode is always simply

=option   exclusive BOOLEAN
=default  exclusive <false>

=option   modeflags INTEGER
=default  modeflags <undef>
When defined, the C<exclusive> option is not used, but your value is
taken. Use constants defined by Fcntl.
Do not forget to include C<O_NONBLOCK>.
=cut

sub init($)
{   my ($self, $args) = @_;

    my $file  = $args->{file}
        or error __x"no file to open specified in {pkg}", pkg => __PACKAGE__;

    my $flags = $args->{modeflags};
    unless(ref $file || defined $flags)
    {   $flags  = O_RDONLY|O_NONBLOCK;
        $flags |= O_EXCL   if $args->{exclusive};
    }

    my $fh;
    if(ref $file)
    {   $fh = $file;
        $self->{IMFR_mode} = $args->{mode} || '<';
    }
    else
    {   sysopen $fh, $file, $flags
            or fault __x"cannot open file {fn} for {pkg}"
               , fn => $file, pkg => __PACKAGE__;
        $self->{IMFR_mode} = $flags;
    }
    $args->{name} = '<'.(basename $file);
    $args->{fh}   = $fh;

    $self->SUPER::init($args);
    $self;
}

=c_method open MODE, FILE, OPTIONS
=cut

sub open($$@)
{   my ($class, $mode, $file, %args) = @_;
    $class->new(file => $file, mode => $mode, %args);
}

#-------------------
=section Accessors

=method mode
The bits of the open mode.
=cut

sub mode() {shift->{IMFR_mode}}

1;
