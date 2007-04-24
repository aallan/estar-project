#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 4;

use lib $ENV{"ESTAR_PERL5LIB"};
use eSTAR::ADP qw ( :all );


# Subroutines which should exist.
my @exported_routines = qw(
                             interpolate_point
                           );

{  # Test module use dependencies...
   use_ok('Carp');
   use_ok('POSIX');
   use_ok('List::Util');

   can_ok('main',@exported_routines);
}


