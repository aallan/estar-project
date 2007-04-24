#!/usr/bin/perl

use strict;
use warnings;

# adp_algorithm.pl - Test the adaptive dataset planning algorithm
# Eric Saunders, February 2007

use lib $ENV{ESTAR_PERL5LIB};
use eSTAR::ADP qw( generate_log_series find_optimal_base 
                   find_principal_intervals 
                   find_optimality find_n_extra find_window_length 
                   fold_dist sum_square_distances );
                   
use List::Util qw( max );

my $timestep = shift;
my $n_extra  = shift;
my $dump_obs_flag = shift;

open my $log_fh, '>>', "log_step$timestep" . "_extra$n_extra" 
   or die "Couldn't open logfile:$!";


# Generate the set of optimum times...
my $undersampling_ratio = 2;
my $n_total = 100;

my @ratio_files = 
   qw( /home/saunders/optimal_base_data/2.0_nyquist_dataset.dat
       /home/saunders/optimal_base_data/5.0_nyquist_dataset.dat);           


my $opt_base = find_optimal_base($undersampling_ratio, $n_total, 
                                 @ratio_files);

warn "Optimal base is: $opt_base\n";

# Build the series normalised between 0 and 1...
my @optimum_times = generate_log_series($n_total, $opt_base);

#warn "$_\n" for @optimum_times;

# OR... 10 observations in a perfect sequence.
#my @optimum_times = (0, 0.02, 0.05, 0.1, 0.15, 0.26, 0.39, 0.57, 0.77, 1.0);


# Find the optimum intervals...
my @optimum_ints = find_principal_intervals(@optimum_times);
warn "optimum int: $_\n" for @optimum_ints;
#die;

# Set the current state of the observations...
# 0 completed or submitted so far...
my @observed_times = ();
my @pending_times  = ();

# Find the number of observations we are allowed to place...
my $n_initial = 2;


# Find the initial number of observations we have to place...
#my $u = 0.2;
#my $sensitivity = 10;
#my $n_extra = find_n_extra($u, $sensitivity, $n_initial);
my $n_available = $n_initial + $n_extra;

warn "Initially placing $n_initial obs, plus $n_extra extra (redundant) obs...\n";

# Set how far from now the first observation should be placed...
my $offset = 0.00;
my $time_now = 0;

# Run time forwards until the end of the run...
while ( (my $delta = find_delta($offset)) < 1.01 ) {

   # Move any pending obs that should have happened to the observed array...
   while ( @pending_times ) {
      my $obs = shift @pending_times;
      if ( $obs <= $delta ) {
      
         ##### BEGIN HACK #####
         # Hack to block out a 48hr window to simulate telescope downtime...
         my $d_start = 0.3;
         
         # Downtime is 2 nights of a 14 night run...
         my $d_end = $d_start + ( 48 / 336 );         

         if ( ( $delta > $d_start ) && ( $delta < $d_end ) ) {
            warn "Observation $obs is in telescope downtime => FAILED...\n";
         }
         else {
         ##### END HACK #####      
            if ( was_observed() ) {
               warn "Observation $obs SUCCESSFUL...\n";
               push @observed_times, $obs;
            }
            else {
               warn "Observation $obs FAILED...\n";
            }
         ##### BEGIN HACK #####            
         }
         ##### END HACK #####      
 
            # Either way, an observation has returned...
            $n_available++;
         
      }
      else {
         unshift @pending_times, $obs;
         last;
      }
   }


   # As long as we have observations to place...
   while ( $n_available > 0 ) {
      # Make sure the pending times are correctly ordered...
      @pending_times = sort { $a <=> $b } @pending_times;

   
      # Place no more observations if we've run out...
      my $n_obs     = scalar(@observed_times);
      my $n_pending = scalar(@pending_times);
      last if ($n_obs + $n_pending) >= $n_total;


      # Find the current window length...
      
      # Calculate the number of redundant observations submitted to ignore...
      my $n_surplus = $n_obs + $n_pending - $n_initial;
      if ( $n_surplus > 0 ) {
         # Limit the ignored number to a maximum of the redundancy...      
         $n_surplus = $n_surplus > $n_extra ? $n_extra : $n_surplus;
      }
      else {
         $n_surplus = 0;
      }
      
      my $window_length = find_window_length($n_obs+$n_pending, $n_surplus,
                                             \@optimum_ints);

      warn "$n_available observations currently available...\n";


      # Deal with the special case of the first observation...
      my $new_obs_time = undef;
      my $w_pos_best = 1;
      my $fuzz = 0.000005;
      if ( $window_length == 0 ) {
         warn "Placing special first observation...\n";
         
         $w_pos_best = 0;
         $new_obs_time = $delta;
      }
      # This isn't the first observation...
      else {
         
         # Check for the special case where the first observation has failed...
         # This would mean no observations have yet been taken...
         if ( !@observed_times ) {
            # Shift any pending times, so that the next pending obs is at 
            # run length 0...
            my $first_pending = $pending_times[0];
            foreach my $pending ( @pending_times ) {
               warn "No first obs yet - changing pending obs time from $pending";
               $pending = $pending - $first_pending;
               warn " to $pending...\n";
            }
         }
         

         # Find the set of observed intervals...
         my @observed_ints = find_principal_intervals(@observed_times);

         # Find the set of pending intervals...
         # If at least one observation has happened, then we need to take that
         # into account...
         my @pending_ints = $n_obs 
                            ? find_principal_intervals($observed_times[-1], 
                                                       @pending_times)
                            : find_principal_intervals(@pending_times);
      
         warn "Considering placing observation ", $n_obs+$n_pending+1 ,"...\n";
         warn "   The time is now $time_now...\n";
         warn "   Window length based on ", $n_obs + $n_pending - $n_surplus
               ," observed or pending observations is $window_length ($n_surplus surplus obs)...\n";
         warn "   Observation timestamps acquired to date:\n";
         warn "      $_\n" for @observed_times;

         warn "   Pending timestamps submitted to date:\n";
         warn "      $_\n" for @pending_times;

         warn "   Observation intervals acquired to date:\n";
         warn "      $_\n" for @observed_ints;

         warn "   Pending intervals submitted to date:\n";
         warn "      $_\n" for @pending_ints;



         # Combine observed and pending intervals for our decision...
         my @all_ints = sort { $a <=> $b } (@observed_ints, @pending_ints);

         # Determine the subset of optimum intervals we'll be considering...
         # The largest we can go for is relative to the largest observed or
         # pending observation...
         my $largest_time = max(@observed_times, @pending_times);
         warn "Largest timestamp observed or pending to date is $largest_time...\n";
         my @allowed_ints = grep {$_ + $largest_time <= $window_length 
                                  + $time_now} @optimum_ints;   
         warn "Allowed intervals are: \n";
         warn "   $_\n" for @allowed_ints;

         my $best_int = undef;
         if ( @allowed_ints ) {
            # Foreach interval (starting with the largest)...   
            foreach my $pos_interval ( reverse @allowed_ints ) {
               my $w_pos = undef;

               $w_pos = find_optimality([@all_ints, $pos_interval],\@optimum_ints);


               # Check whether this interval would shunt others...
         #      warn "   Considering interval $pos_interval... ($observed_ints[-1])\n";
   #            if ( $pos_interval >= ($all_ints[-1] || 0) ) {
         #         warn "      Interval not shunted.\n";
         #         warn "   w_pos is $w_pos\n";
   #            }
   #            else {
         #         my $int_position = get_int_position($pos_interval, \@all_ints);
         #         warn "      Inserting new interval $pos_interval at position $int_position\n";
         #         warn "      The following intervals will be shunted:\n";
         #         warn "         $_\n" for (@observed_ints[$int_position..$#observed_ints]);

   #            }


               # Keep track of the best interval so far...
               if ( $w_pos < $w_pos_best ) {
                  $w_pos_best = $w_pos;
                  $best_int   = $pos_interval;
               }

            }

            # Calculate the timestamp...
            $new_obs_time = $best_int + $largest_time;
            warn "   Best observation is the interval $best_int, with w = $w_pos_best.\n";

         }

         # If we didn't have any intervals, then we are dealing with redundant
         # observations.
         else {
            warn "Placing redundant observation...\n";
            $new_obs_time = place_redundant_obs($fuzz, \@pending_times, 
                                                $time_now, 
                                                $window_length - $time_now);
         }

      }
      

      warn "   This corresponds to a timestamp of $new_obs_time.\n";
      warn "   *************************************************\n";
      # 'Queue' the observation...
      push @pending_times, $new_obs_time;
      $n_available--;
#      die if $time_now >=0.1;
   }

   $time_now += $timestep;
}


warn "Final set of observation timestamps:\n";
warn "   $_\n" for @observed_times;

warn "Final set of observation intervals:\n";
my $i = 0;
foreach my $int ( sort { $a <=> $b } find_principal_intervals(@observed_times) ) {
   warn "   $int   ($optimum_ints[$i])\n";
   $i++;
}

my $final_w = find_optimality([find_principal_intervals(@observed_times)], 
                              \@optimum_ints);

warn "Optimality of final observed series was $final_w\n";


# Find the value of S...
my $p = 1.69;
my $l = 14;
my $period = $p / $l;
warn "Folding on a period of $period...\n";
my @folded_times = fold_dist($period, @observed_times);
my $s = sum_square_distances(@folded_times);
warn "S = $s";


my $obs_fraction = scalar(@observed_times) / scalar(@optimum_times);
print $log_fh "$final_w     $obs_fraction     $s\n";

close $log_fh;

# Dump the observation times to a file...
if ( $dump_obs_flag ) {
   open my $obs_fh, '>>', "obs_times$timestep" . "_extra$n_extra" 
      or die "Couldn't open obs_times file to write:$!";

   print $obs_fh "$_\n" for @observed_times;

   close $obs_fh;
}

# This function for testing purposes only at present!
sub find_delta {
   my $offset = shift;
   
   my $delta = $time_now + $offset;

   return $delta;
}


sub get_int_position {
   my $target = shift;
   my $intervals = shift;
   
   my $position = 0;
   foreach my $interval ( @{$intervals} ) {
      return $position if $target < $interval;
      $position++;
   }

   return undef;
}


# Determines the fuzziness (start time - end time) of the obs.
sub find_fuzziness {
   my $interval = shift;

   # For now, just use a fixed interval fuzziness. More generally, this should
   # be scale-invariant (i.e. a function of interval length).

   my $fuzziness = $interval / 4;

   return $fuzziness;
}



# The business with fuzziness will obviously have to be fixed when
# we add scaling fuzziness.
sub place_redundant_obs {
   my ($fuzz, $pending_times, $window_bottom, $window_top) = @_;

   my $redundant_fuzz = $fuzz;
   my $obs_width = 2 * $redundant_fuzz;


   warn "Redundant width is $obs_width...\n";

   # For each pending observation...
   for ( my $i=0; $i < scalar(@{$pending_times}); $i++ ) {

      # If there's enough space between the current time and that
      # observation, place it between these points...
      my $lower_window_bound = defined $pending_times->[$i-1]
                               ? ($pending_times->[$i-1] + $fuzz)
                               : $time_now;
      my $p_lower_limit = $pending_times->[$i] - $fuzz;
      my $lower_space = $p_lower_limit - $lower_window_bound;

      warn "Considering pending time $pending_times->[$i]...\n";
      warn "Lower space is $lower_space...\n";
      if ( $lower_space >= $obs_width ) {
         warn "Lower space is acceptable...\n";
         my $obs_time = $p_lower_limit - $redundant_fuzz;
         return $obs_time;
      }

      # Otherwise, try the other side...

      # The upper distance is either the next obs, or the window end...
      my $upper_window_bound = defined $pending_times->[$i+1] 
                                 ? ($pending_times->[$i+1] - $fuzz)
                                 : $window_top;

      my $p_upper_limit = $pending_times->[$i] + $fuzz;
      my $upper_space = $upper_window_bound - $p_upper_limit;

      warn "Upper space is $upper_space...\n";
      if ( $upper_space >= $obs_width ) {
         warn "Upper space is acceptable...\n";
         my $obs_time = $p_upper_limit + $redundant_fuzz;
         return $obs_time;
      }

      # Otherwise, move on to the next pending observation...
   }

   # If we've got to here, this is bad - there are no slots for the
   # redundant observations...
   die "Can't place redundant obs! This is bad!";
   return;
}


sub was_observed {
   my $obs_chance = 0.5;
   
   return rand() < $obs_chance ? 1 : 0;
}
