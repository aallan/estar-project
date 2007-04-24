#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 6;

use lib $ENV{ESTAR_PERL5LIB};
use eSTAR::ADP::Util qw (:all);


# Subroutines which should exist.
my @exported_routines = qw(
                             get_network_time
                             str2datetime
                             init_logging
                             read_n_column_file
                             build_dummy_header
                           );

{  # Test module use dependencies...
   use_ok('eSTAR::Logging');
   use_ok('eSTAR::Constants');
   use_ok('eSTAR::Process');
   use_ok('Sys::Hostname');
   use_ok('DateTime::Format::ISO8601');

   can_ok('main',@exported_routines);
}

