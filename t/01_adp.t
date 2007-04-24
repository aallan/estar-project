#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 11;

use lib $ENV{"ESTAR_PERL5LIB"};
use eSTAR::ADP qw ( :all );

{ # Test interpolate point...
   my @x_range = (1.0, 5.0);
   my @y_range = (2.0, 8.0);

   my $x_val = 5.0;
   is(interpolate_point(@x_range, @y_range, $x_val), 8, 'interpolate_point - max_val');

   $x_val = 1.0;
   is(interpolate_point(@x_range, @y_range, $x_val), 2, 'interpolate_point - min_val');

   # Some values very like those we actually use...
   @y_range          = (1.016920091, 1.031960083);
   $x_val            = 1.98412698412698;
   my $expected_base = 1.02062040649206;
   
   is(interpolate_point(@x_range, @y_range, $x_val), $expected_base,
      'interpolate_point - real ADP usage');
   
}


{ # Test find_optimal_base...
   my @ratio_files = qw( data/2.0_nyquist_dataset.dat
                         data/5.0_nyquist_dataset.dat );

   my $u_ratio = 1.984126;
   my $n_total = 100;
   is(find_optimal_base($u_ratio, $n_total, @ratio_files), 1.016920091, 
      'find_optimal_base - typical values');
      
   $u_ratio = 1.0;
   $n_total = 100;      
   is(find_optimal_base($u_ratio, $n_total, @ratio_files), 1, 
      'find_optimal_base - linear sampling');
      
   $u_ratio = 12.5;
   $n_total = 100;
   is(find_optimal_base($u_ratio, $n_total, @ratio_files), undef, 
      'find_optimal_base - severe undersampling');

   $u_ratio = 3.0;         
   $n_total = 500;
   is(find_optimal_base($u_ratio, $n_total, @ratio_files), 1.005640097, 
      'find_optimal_base - high values');

   $u_ratio = 3.0;         
   $n_total = 501;
   is(find_optimal_base($u_ratio, $n_total, @ratio_files), undef, 
      'find_optimal_base - out of range n_total');


   $n_total = 10000;
   $u_ratio = 3.0;         
   is(find_optimal_base($u_ratio, $n_total, @ratio_files), undef, 
      'find_optimal_base - out of range n_total');
      
}


{ # Test find_window_length...
   my $n_extra = 2;
   my $n_obs = 3;
   my $optimum_intervals = [0.02, 0.03, 0.05, 0.05];

   is(find_window_length($n_obs, $n_extra, $optimum_intervals),
      0.02, 'find_window_length - normal usage');
      
}


{ # Test get_times...
   my %obs_hash = (
                    '2007-04-12T21:53:36' => 'observation_[2007-04-12T21:53:36]',
                    '2007-04-12T23:16:20' => 'observation_[2007-04-12T23:20:16]',
                    '2007-04-13T00:39:04' => 'submitted',
                   );
   my @expected = ('2007-04-12T21:53:36', '2007-04-12T23:20:16',
                   '2007-04-13T00:39:04');
   my @received = get_times(%obs_hash);

   is_deeply(\@received, \@expected, 'get_times - normal usage');
}
