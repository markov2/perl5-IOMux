# This code is part of distribution IOMux.  Meta-POD processed with OODoc
# into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package IOMux::Open;

use warnings;
use strict;

use Log::Report 'iomux';

my %modes =
  ( '-|'  => 'IOMux::Pipe::Read'
  , '|-'  => 'IOMux::Pipe::Write'
  , '|-|' => 'IOMux::IPC'
  , '|=|' => 'IOMux::IPC'
  , '>'   => 'IOMux::File::Write'
  , '>>'  => 'IOMux::File::Write'
  , '<'   => 'IOMux::File::Read'
  , tcp   => 'IOMux::Net::TCP'
  );

sub import(@)
{   my $class = shift;
    foreach my $mode (@_)
    {   my $impl = $modes{$mode}
            or error __x"unknown mode {mode} in use {pkg}"
              , mode => $mode, pkg => $class;
        eval "require $impl";
        panic $@ if $@;
    }
}
    
=chapter NAME
IOMux::Open - simulate the open() function

=chapter SYNOPSIS
  use IOMux::Open qw( -| |- |-| < > >> tcp);

  # pipe for reading
  my $who = $mux->open('-|', 'who', 'am', 'i');
  print <$who>;

  # two-way connection (like IPC::Open3)
  my $echo = $mux->open('=|', 'cat');

  # file
  my $pw = $mux->open('<', '/etc/passwd');
  my @noshell = grep /\:$/, <$pw>;

=chapter DESCRIPTION
This module is a simple wrapper to bring various alternative connection
implementations closer to normal Perl. It also saves you a lot of explicit
require (C<use>) lines of code.

With this module, code is simplified. For instance, the real logic is:

  use IOMux::Pipe::Read;
  my $who = IOMux::Pipe::Read->new
   ( run_shell => [ 'who', 'am', 'i' ]
   );
  $mux->add($who);
  print <$who>;

In the short syntax provided with this module:

  use IOMux::Open '-|';
  my $who = $mux->open('-|', 'who', 'am', 'i');
  print <$who>;

You only need to C<use> one C<::Open> module with some parameter, in
stead of requiring all long names explicitly. As you can see, the
object gets added to the mux as well.

=chapter METHODS

=section Constructors

=c_method new $mode, $params
Available MODES are 

    -|  IOMux::Pipe::Read
   |-   IOMux::Pipe::Write
   |-|  IOMux::IPC
   |=|  IOMux::IPC          (with errors)
    >   IOMux::File::Write
    >>  IOMux::File::Write  (appendinf)
    <   IOMux::File::Read
=cut

sub new($@)
{   my ($class, $mode) = (shift, shift);
    my $real  = $modes{$mode}
        or error __x"unknown mode '{mode}' to open() on mux", mode => $mode;

    $real->can('open')
        or error __x"package {pkg} for mode '{mode}' not required by {me}"
             , pkg => $real, mode => $mode, me => $class;

    $real->open($mode, @_);
}

#--------------
=section Accessors
=cut

1;
