use warnings;
use strict;

package IOMux::File::Write;
use base 'IOMux::Handler::Write';

use Log::Report    'iomux';
use Fcntl;
use File::Basename 'basename';

=chapter NAME
IOMux::File::Write - write to file

=chapter SYNOPSIS
  my $mux = IOMux::Select->new;  # or ::Poll

  use IOMux::Open '>';
  my $file = $mux->open('>', $filename);

  use IOMux::File::Write;
  my $file = IOMux::File::Write->new
    (file => $filename, mode => '>>');
  $mux->add($file);

  $file->write($text);
  $file->print($text);

  write $file $text;
  print $file $text;

=chapter DESCRIPTION
Open a file to be written.

=chapter METHODS

=section Constructors

=c_method new OPTIONS

=requires file FILENAME|HANDLE
The file to be managed, either provided as FILENAME or as HANDLE. When
a HANDLE is passed, most other options will be ignored. The HANDLE must
be in non-blocking mode already and opened for writing (only).

=default  name '$mode$file'

=option   mode '>'|'>>'
=default  mode '>'
The C<&gt;&gt;> is short for normal open plus the append option set.

=option   exclusive BOOLEAN
=default  exclusive <false>

=option   create    BOOLEAN
=default  create    <true>

=option   append    BOOLEAN
=default  append    <false>

=option   modeflags INTEGER
=default  modeflags <undef>
When defined, the C<mode>, C<exclusive>, C<create> and C<append> options
are not used, but your value is taken. Use constants defined by Fcntl.
Do not forget to include C<O_NONBLOCK>.
=cut

sub init($)
{   my ($self, $args) = @_;

    my $file  = $args->{file}
        or error __x"no file to open specified in {pkg}", pkg => __PACKAGE__;

    my $flags = $args->{modeflags};
    my $mode  = $args->{mode} || '>';
    unless(ref $file || defined $flags)
    {      if($mode eq '>>') { $args->{append} = 1 }
        elsif($mode eq '>')  { $mode = '>>' if $args->{append} }
        else
        {   error __x"unknown file mode '{mode}' for {fn} in {pkg}"
              , mode => $mode, fn => $file, pkg => __PACKAGE__;
        }
    
        $flags  = O_WRONLY|O_NONBLOCK;
        $flags |= O_CREAT  unless exists $args->{create} && !$args->{create};
        $flags |= O_APPEND if $args->{append};
        $flags |= O_EXCL   if $args->{exclusive};
    }

    my $fh;
    if(ref $file)
    {   $fh = $file;
    }
    else
    {   sysopen $fh, $file, $flags
            or fault __x"cannot open file {fn} for {pkg}"
               , fn => $file, pkg => __PACKAGE__;
        $self->{IMFW_mode} = $flags;
    }
    $args->{name} = $mode.(basename $file);
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

sub mode() {shift->{IMFW_mode}}

1;
