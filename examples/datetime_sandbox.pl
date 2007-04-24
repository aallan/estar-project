#!/usr/bin/perl

use strict;
use warnings;

# datetime_sandbox.pl - Do some sample calculations using DateTime objects.
# Eric Saunders, January 2007.

use lib $ENV{"ESTAR_PERL5LIB"};
use eSTAR::ADP       qw( interpolate_point find_optimal_base );
use eSTAR::ADP::Util qw( read_n_column_file );

use DateTime;

print "Starting...\n";


my $dt1 = 
  DateTime->new( 
                 year       => 2006,
                 month      => 1,
                 day        => 24,
                 hour       => 17,
                 minute     => 6,
                 second     => 3,
                 nanosecond => 0,
                 time_zone  => "floating",
                );
                
                
my $dt3 = DateTime->now();

print "Time was: $dt1\n";
print "Time is now: $dt3\n";


my $gap1 = DateTime::Duration->new( seconds => 400 );

my $dt4 = $dt3 + $gap1;

print "Future time is: $dt4\n";
print "dt3 is $dt3\n";


# Build a set of observations...
my $p_min_in_hrs = 5;
my $p_max_in_days = 10;
my $run_length_in_days = 21;

my $p_min_in_secs = $p_min_in_hrs * 3600;
my $run_length_in_secs = $run_length_in_days * 24 * 3600;

my $p_min  = DateTime::Duration->new( seconds => $p_min_in_secs );
my $run_length  = DateTime::Duration->new( seconds => $run_length_in_secs );

# Find the minimum relative period...
print "p_min: " . $p_min->delta_seconds . "\n";
print "r_length: " . $run_length->delta_seconds . "\n";

my $p_min_rel = $p_min->delta_seconds / $run_length->delta_seconds;
print "p_min_rel: $p_min_rel\n";

my $max_rel_freq = 1 / $p_min_rel;
print "max_rel_freq: $max_rel_freq\n";

my $n_total = 100;
my $undersampling_ratio = 2 * $n_total / $max_rel_freq;
print "Undersampling ratio: $undersampling_ratio\n";



# Use the ratio to choose the correct line...
my @ratio_files = qw( /home/saunders/optimal_base_data/2.0_nyquist_dataset.dat
                      /home/saunders/optimal_base_data/5.0_nyquist_dataset.dat);

my $opt_base = find_optimal_base($undersampling_ratio, $n_total, @ratio_files);

















