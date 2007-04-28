package eSTAR::ADP;

=head1 NAME

eSTAR::ADP - A collection of routines for generating different observation
strategies.

=head1 DESCRIPTION

eSTAR::ADP provides routines to generate a range of different observation
distributions, to allow simulation and comparison of alternative observation
strategies. Additionally, it provides implementations of the S and N metrics
described in Saunders et al. 2006, AN, 327, 783.

This version of the module is an amalgamation of the best parts of the original
ADP and ADP::PhaseCoverage modules written for simulation testing, and held in
the CVS tree under 'ADP', updated for the variable star monitoring agent.

=cut

=over 4

=cut


use strict;
use warnings;

use Carp;
use POSIX      qw(ceil floor);
use List::Util qw(max sum shuffle);

use eSTAR::ADP::Util  qw( read_n_column_file );

require Exporter;
use vars qw( $VERSION @EXPORT_OK %EXPORT_TAGS @ISA );

@ISA = qw( Exporter );
@EXPORT_OK = qw(
                  build_linear_dist 
                  build_n_linear_dist
                  fold_dist
                  generate_general_fibonacci_seies
                  generate_general_linear_series
                  generate_general_random_series
                  generate_linear_series
                  generate_log_series
                  generate_general_log_series
                  calc_log_base
                  generate_fibonacci_series
                  generate_random_series
                  find_log_base
                  interpolate_point
                  find_optimal_base
                  sum_square_distances
                  find_interconnectivity
                  find_largest_gap
                  randomise_spacings
                  reorder_spacings
                  generate_spacings
                  get_random_int_list
                  sort_by_number
                  find_principal_intervals
                  find_optimality
                  find_window_length
                  find_n_extra
                  get_times
                );

%EXPORT_TAGS = ( 
                  'all' => [ qw(
                                 build_linear_dist 
                                 build_n_linear_dist
                                 fold_dist
                                 generate_general_fibonacci_seies
                                 generate_general_linear_series
                                 generate_general_random_series
                                 generate_linear_series
                                 generate_log_series
                                 generate_general_log_series
                                 calc_log_base
                                 generate_fibonacci_series
                                 generate_random_series
                                 find_log_base
                                 interpolate_point
                                 find_optimal_base
                                 sum_square_distances
                                 find_interconnectivity
                                 find_largest_gap
                                 randomise_spacings
                                 reorder_spacings
                                 generate_spacings
                                 get_random_int_list
                                 sort_by_number
                                 find_principal_intervals
                                 find_optimality
                                 find_window_length
                                 find_n_extra
                                 get_times
                               )                                                      
                           ],
                 );

                 
=item B<build_linear_dist>

Returns a linear distribution of points with a specified spacing, starting at 0.

   @points = build_linear_dist($n_points, $spacing);

=cut
sub build_linear_dist {
   my ($num_points, $spacing) = @_;
   my @point_set;

   #Add all the points in a linear spacing...
   for  (my $i=0; $i < $num_points;  $i++) {
      push @point_set, ($i * $spacing);
   }
  
   return @point_set;
}


=item B<build_nlinear_dist>

Returns a linear distribution of points starting at 0 and ending at 1.

   @points = build_nlinear_dist($n_points);

=cut
sub build_nlinear_dist {
   my $num_points = shift;

   #Points will run from 0 - 1...
   my $spacing = 1.0 / $num_points;
   
   return build_linear_dist($num_points, $spacing);
}


=item B<fold_dist>

Returns a set of points phase-folded on a specified period.

   @folded = fold_dist($period, @points_to_fold);

=cut
sub fold_dist {
   my ($period, @folded_set) = @_;

   # Fold the data back on the period, and then rescale it to fit in the 
   #'phase box' (0 - 1)...
   
   # F = x / p - int(x / p) where
   #                              x = original timepoint
   #                              p = period
   #                              F = position in phase box   
   # First term folds on the period.
   # Second term pulls folded data into phase box.
   
   foreach my $x ( @folded_set ) {
      $x = ($x / $period) - int($x / $period);
   }
   
   return sort_by_number( @folded_set );
}


=item B<generate_general_fibonacci_series>

Returns a Fibonacci series of specified length, scaled to fit within a given
range. The first element is discarded (for practical observing purposes), and
an extra element added at the end so that the size of the set is consistent.

   @fib_dist = generate_general_fibonacci_series($n_points, $start, $end);

=cut
sub generate_general_fibonacci_series {
   my ($num_points, $start, $end) = @_;
   
   # +1 required because initial point is subsequently removed.
   my @fib_set = generate_fibonacci_series($num_points + 1);

   #Remove the first element (as it is the same as the second)...
   shift @fib_set;

   # Shunt set to correct starting location...
   my $offset = $fib_set[0] - $start;
   foreach my $element ( @fib_set ) {
      $element = $element - $offset;
   }
   
   my $fib_coeff = $end / $fib_set[-1];
      
   #Scale the set to fit the range exactly...
   foreach my $element ( @fib_set ) {
      $element = $element * $fib_coeff;
   }
   
   return @fib_set;
}


=item B<generate_general_linear_series>

Returns a linear series running between a specified start and end point.

   @lin_dist = generate_general_linear_series(n_points, $start, $end);

=cut
sub generate_general_linear_series {
   my ($num_points, $start, $end) = @_;

   my @linear_set = generate_linear_series($num_points, $end - $start);

   #Shunt set to correct starting location...
   foreach my $element ( @linear_set ) {
      $element = $element + $start;
   }

   return @linear_set;
}


=item B<generate_general_random_series>

Returns a random distribution of points running between a specified start and
end point.

   @rand_dist = generate_general_random_series(n_points, $start, $end);

=cut
sub generate_general_random_series {
   my ($num_points, $start, $end) = @_;
   
   my @random_set = generate_random_series($num_points, $end - $start);
   
   #Shunt set to correct starting location...
   foreach my $element (@random_set) {
      $element = $element + $start;
   }
   
   return @random_set;
}


=item B<generate_linear_series>

Generate a linear distribution of points between 0 and a given end point, or
between 0 and 1 if no endpoint has been specified

   @linear_dist = generate_linear_series($n_points, $end);

=cut
sub generate_linear_series {
   my ($num_points, $end) = @_;
   my @linear_set;
   
   # Set upper limit to 1.0 if end point not specified...
   $end = 1.0 unless defined $end; 
   
   #Points will run from 0 - end point...
   my $spacing = $end / $num_points;
   
   #Add all the points in a linear spacing...
   for  (my $i=0; $i < $num_points;  $i++) {
      push @linear_set, ($i * $spacing);
   }

   return @linear_set;
}


=item B<generate_log_series>

Returns a logarithmically spaced set of points, normalised so that the start
point is 0 and the end point is 1. You want to use this to sample lightcurves, 
because you can specify an arbitrary base, since the start point is not fixed.

   @log_dist = generate_log_series($n_total, $log_base);

=cut
sub generate_log_series {
   my ($N, $x) = @_;
   my @log_set;
   
   #            (x**n) - 1
   # t =    -----------------
   #         (x**(N-1)) - 1 
   #                         where:
   #                         t = the value of the point in the series
   #                         x = the (arbitrary) base of the series
   #                         n = the number of the current datapoint (0 - N)
   #                         N = the total number of points

   for ( my $i = 0; $i < $N; $i++ ) {
      push @log_set, ( ( $x**( $i ) ) - 1) / 
                     ( ( $x**( $N - 1 ) ) - 1 );
   }

   return @log_set;
}


=item B<generate_general_log_series>

Returns a logarithmically spaced set of points, normalised so that the start
point is $first and the end point is $last. You want to use this to sample
period ranges, because you have a specific initial period which you care about, 
so the base is fixed for a given n.

   @log_set = generate_general_log_series($n_points, $first, $last);

=cut
sub generate_general_log_series {
   my ($N, $first, $last) = @_;

   # Z_n = y_n ( Z_(N-1) - Z_0 ) + Z_0
   #                         where:
   #                         Z_n   = the value of the point in the series
   #                         y_n   = the value of the nth point in the log series
   #                                 running from 0 - 1 (i.e. the output of
   #                                'generate_log_series')    
   #                         Z_0   = the first point in the series ('first')
   #                         Z_N-1 = the last point in the series ('last')
   
   # Find the log base we need for a true logarithmic series at this scale...
   my $log_base = calc_log_base($N, $first, $last);
   
   # Feed the log base in to find the set of y_n...
   my @unit_log_series = generate_log_series($N, $log_base);
      
   # Offset and scale the series...
   my @general_log_series;
   for ( my $i = 0; $i < $N; $i++ ) {
      push @general_log_series, ( ( $unit_log_series[$i] * ( $last - $first ) )
                                  + $first ); 
   }
   
   return @general_log_series;
}


=item B<calc_log_base>

Returns the log base required to build a series with N points, where the first
and last points are specified.

   $log_base = calc_log_base($n_points, $first, $last);

=cut
sub calc_log_base {
   my ( $N, $first, $last ) = @_;

   # C = ( Z_(N-1) / Z_0 ) ** ( 1 / (N-1) )
   #                         where:
   #                         C     = the log base we need
   #                         Z_0   = the first point in the series ('first')
   #                         Z_N-1 = the last point in the series ('last')

   my $C = ( $last / $first ) ** ( 1 / ( $N - 1) );
      
   return $C;
}


=item B<generate_fibonacci_series>

Returns a Fibonacci series (1,1,2,3,5,...) with a specified number of elements.

   @fib_set = generate_fibonacci_series($n_points);

=cut
sub generate_fibonacci_series {
   my $num_points = shift;
   my @fib_set = (1,1);                   #Seed initial Fibonacci set

   for (my $i=2; $i < $num_points;  $i++) {
      push @fib_set, ( $fib_set[$i-2] + $fib_set[$i-1] );
   }

   return @fib_set;
}


=item B<generate_random_series>

Generate a random distribution of points between 0 and a given end point, or
between 0 and 1 if no endpoint has been specified.

   @random_series = generate_random_series($n_points, [$end_point]);

=cut
sub generate_random_series {
   my ($num_points, $end) = @_;
   my @random_set;
   
   #Set upper limit to 1 if end point not specified...
   $end = 1.0 unless defined $end;
   
   for (my $i=0; $i < $num_points; $i++) {
      push @random_set, rand($end);         #Random number between 0 - end point
   }
   @random_set = sort_by_number(@random_set);
  
   return @random_set; 
}


=item B<find_log_base>

Returns the base power for a power series of the form y = C(x**n) with a
specified number of elements, lying within a specified range. If
$centre is defined (i.e. not undef), then the log series will be
shifted to begin at 0 rather than 1.

DEPRECATED. calc_log_base() is much more likely to be what you want. This
function is left here primarily for illustrative purposes.

   $log_base = find_log_base($n_points, $end_point, $plaw_coeff, [$centre]);

=cut
sub find_log_base {
   my ($num_points, $upper_limit, $coeff, $centre_at_origin) = @_;
   my $offset = 0.0;

   #The default power series is given by
   #
   #  y = C(x**n)
   #
   #and runs from (n=0, y=1) to (n = max_n, y = upper_limit).
   #Rearranging to solve for x (the base power of the series) gives
   #
   # x = (y/C)** 1/n, where
   #                             y = upper limit of dataset
   #                             n = number of points required
   #                             x = the base number to construct the log set
   #   
   #If we want a power series beginning at 0, then:
   #
   #  y = C(x ** n) - 1
   #  x = ( (y + 1) / C )** 1/n
   #
   #This series runs from (n=0, y=0) to (n = max_n, y = upper_limit - 1)
   #The -1 term is required because we are shifting the log set to begin at 0,
   #not 1, so the upper limit is effectively '1 smaller'.
   
   if ( defined $centre_at_origin ) {
      print "    Calculating base for a log series centred at origin.\n";
      $offset = 1.0;
   }
   
   my $x = ( ( $upper_limit + $offset ) / $coeff )**( 1 / $num_points );

   return $x;
}


=item B<new_base_finder>

   Takes the filename of a base curve (n_observations vs optimal base) and
   returns a subroutine, which provides an index into that dataset.

   $find_base = new_base_finder($base_filename);
   $base = $find_base->($n_obs);

=cut                  
sub new_base_finder {
   my $filename = shift;
   
   my @data = read_n_column_file($filename);
   
   # Get the n_obs value of the first observation...
   my $start_obs = $data[0]->[0];

   # Sanity check the list is then numerically ordered integers, with no gaps...
   # This is not at all rigorous!
   my $end_obs = $data[0]->[$#{@{$data[0]}}];
   
   return sub {
      my $n_obs = shift;

      # Find the log base corresponding to the number of observations...
      my $log_base = undef;
      for ( my $i=0; $i< scalar @{$data[0]}; $i++ ) {
         if ( $data[0]->[$i] == $n_obs ) {
            $log_base = $data[1]->[$i];
            last;
         }
      }

      return $log_base;
   };
}


=item B<interpolate_point>

   Returns the linear interpolation (y value) for a given x, when the ranges in
   x and y are specified.
   
   my $y_val = interpolate_point($xmin, $xmax, $ymin, $ymax, $xval);

=cut
sub interpolate_point {
   my ($x_min, $x_max, $y_min, $y_max, $x_val) = @_;

   # Make sure the lower y value really is lower...
   my $y_lower = $y_min < $y_max ? $y_min : $y_max;
   
   # Silently return the y-value if the y-range is 0...
   return $y_min if $y_min == $y_max;
   
   # Calculate the fractional x position of the point in the range...
   my $x_frac  = ($x_val - $x_min) / abs($x_max - $x_min);
   
   # Translate into a fractional y position...
   my $y_val   = abs($y_max - $y_min) * $x_frac + $y_lower;

   return $y_val;
}


=item B<find_optimal_base>

   Implements the optimal base calculation of Saunders et al. 2006, A&A 455,757.

   Takes an undersampling ratio, defined as \nu / \nu_N, where \nu is the 
   limiting frequency, and \nu_N is the effective Nyquist frequency, the total
   number of observations, and the paths of two base files, and returns the
   optimal base for that ratio, interpolating between the undersampling ratios
   provided by the files.

   my $optimal_base = find_optimal_base($undersampling_ratio, $n_total, 
                                        $lower_base_file, $upper_base_file);

=cut
sub find_optimal_base {
   my ($u_ratio, $n_total, $lower_ratio_file, $upper_ratio_file) = @_;
   my $opt_base;

   # Read in the optimal base curves...
   my $get_lower_base = new_base_finder($lower_ratio_file);
   my $get_upper_base = new_base_finder($upper_ratio_file);

   # Set the largest undersampling ratio we know how to deal with...
   my $u_max = 12.5;

   # If we're not undersampling, then we don't need a geometric spacing!
   if ( $u_ratio <= 1.0 ) {
      print "Warning: Enough observations to avoid undersampling!\n";
      print "Falling back to a linear observing strategy...\n";

      $opt_base = 1;
   }
   # We are undersampling - but by how much?
   else {

      # Check we're in an undersampling regime we think to understand...
      if ( $u_ratio < $u_max ) {

         # Set the max and min undersampling we know about...
         my @u_range = (2.0, 5.0);

         # 1 = linear. 5 - 12.5 are roughly equivalent in actual y values...      
         $u_ratio = $u_range[1] if $u_ratio > $u_range[1];

         # Without precise values for the range 1 - 2, we treat it as 2...
         $u_ratio = $u_range[0] if $u_ratio < $u_range[0];

         # Pull out the optimal bases for both curves...
         my @base_range = ( $get_lower_base->($n_total),
                            $get_upper_base->($n_total) );      

         # Check there are values - give up if there aren't...
         if ( defined $base_range[0] && defined $base_range[1] ) {
            # Do the interpolation...
            $opt_base = interpolate_point(@u_range, @base_range, $u_ratio);
         }
         else {
            print "Warning: No base found for n_obs = $n_total! Aborting...\n";
            $opt_base = undef;
         }

      }   
      # This is so severely undersampled we can't be held responsible...
      else { 
         print "Warning: Undersampling ratio > $u_max! Aborting...\n";
         $opt_base = undef;
      }

   }


   return $opt_base;
}


=item B<sum_square_distances>

Returns the sum of the square of the distances between all the adjacent values
in a dataset, after numerical ordering. This implements the phase coverage 
metric 'S' of Saunders et al. (2006).

   $S = sum_square_distances(@points);

=cut
sub sum_square_distances {
   my (@points) = @_;
   my $distance = 0.0;      # Sum of distances between adjacent points, squared

   @points = sort_by_number(@points);                # Numeric ascending order

   for (my $i=0; $i < scalar(@points) - 1;  $i++) {
      $distance = $distance + ( $points[$i+1] - $points[$i] )**2;
   }
   
   # Handle the wrap-round distance between first and last datapoints...
   $distance = $distance + ( $points[-1] - 1 - $points[0] )**2;

   # Normalise so that value is independent of number of
   # data points, according to:
   #     S = sum(gaps**2)/sum(ideal_gaps**2)
   #	   = sum(gaps**2)/N*(1/N**2)
   #	   = N*sum(gaps**2)   
   $distance = $distance * scalar(@points);
      
   return $distance;
}


=item B<find_interconnectivity>

Takes a list of times and returns the interconnectivity, a metric describing 
how well a set of observations is spaced over multiple cycles. The
interconnectedness is an integer (the default) unless normalised by the number
of spaces (including the 'wrap-round' space - see fold_dist for more info). The
algorithm takes the list of times and folds them about a specified period,
preserving the integer part of the fold. The absolute difference between all
adjacent integers is summed, and returned. Thus if two points lie within the
same phase cycle, the value of the interconnectedness statistic for those
points is 0. This implements the interconnectivity metric 'N' of Saunders et al.
(2006).

   $N = find_interconnectivity($period, $norm_flag, @times);

=cut
sub find_interconnectivity {
   my ($period, $norm_flag, @times) = @_;
   my $norm_false = 'raw';
   my %split_times;
   my $N = 0;


   # Default: always normalise unless explicitly told not to by the passing of
   # the argument $normalisation_test_string in via $normalisation_flag...
   $norm_flag = 'normalised' unless $norm_flag eq $norm_false;


   # Fold the times, but preserve the integer component. Don't use 'int' here
   # because need the fractional values for the spacing calculation...   
   foreach my $x ( @times ) {
      $split_times{ ($x / $period) - int($x / $period) } = $x / $period;
   }
   
   # Sort the folded times by phase - i.e. by the fractional component of
   # the values...   
   my @sorted_times;
   foreach my $frac_time ( sort_by_number(keys %split_times) ) {      
      push @sorted_times, $split_times{$frac_time};
   } 

   my @delta_times;
   for ( my $i=0; $i < ( scalar(@sorted_times)-1 ); $i++ ) {
      push @delta_times, ($sorted_times[$i+1] - $sorted_times[$i]);
   }
   
   foreach my $x (@delta_times) {
      $N += abs(floor($x));
   }

   # Handle the wrap-round distance between first and last datapoints...
   $N = $N + abs( floor ($sorted_times[0] - $sorted_times[-1]) );

   # Normalise by the period if required...
   unless ($norm_flag eq $norm_false) {
      print "Normalising... value before normalisation is $N\n";
      $N = $N * $period;
   }
 
   return $N;
}



=item B<find_largest_gap>

Returns the largest gap between a set of points.

   $max_gap = find_largest_gap(@points);

=cut
sub find_largest_gap {
   my (@points) = @_;

   @points = sort_by_number(@points);                # Numeric ascending order

   my @gaps;

   for (my $i=0; $i < scalar(@points) - 1;  $i++) {
      push @gaps, ( $points[$i+1] - $points[$i] )**2;
   }
   
   # Handle the wrap-round distance between first and last datapoints...
   push @gaps, ( $points[-1] - 1 - $points[0] )**2;

   my $max_gap = max(@gaps);
      
   return $max_gap;
}


=item B<randomise_spacings>

Takes a list of times and returns a new list of times, with each time randomly
placed between the first and last time, but with the spacings between each time 
preserved.

   @respaced = randomise_spacings(@times);

=cut
sub randomise_spacings {
   my @times = @_;
      
   my @spacings = &generate_spacings(@times);  

   my $offset = $times[0];
   my @new_times;   
   push @new_times, $times[0];

#Code for ordered spacings (min-max or max-min)   
#   while ( scalar(@spacings) > 0 ) {
#      my $choice = splice ( @spacings, scalar(@spacings) - 1, 1 );   
#      my $choice = splice ( @spacings, 0, 1 );
#      push @new_times, ( $offset + $choice );
#      $offset += $choice;
#   }
   
   while ( scalar(@spacings) > 0 ) {
      my $choice = splice ( @spacings, int rand scalar(@spacings), 1 );
      push @new_times, ( $offset + $choice );
      $offset += $choice;
   }
      
   return @new_times;
}


=item B<reorder_spacings>

Takes a target list of scalar values (normally timestamps) and a list of new 
array positions, and reorders the spacings according to the new list.

   @new_points = reorder_spacings($old_points, $new_ordering);

=cut
sub reorder_spacings {
   my $times_ref = shift;
   my $new_order_ref = shift;
   
   my @times = @{$times_ref};
   my @new_order = @{$new_order_ref};
   
   
   my @spacings = generate_spacings(@times);

   unless ( scalar(@spacings) == scalar(@new_order) ) {
      croak "New order list does not have the same number of elements as the
      number of spaces to reorder!\n";
   }


   my $offset = $times[0];
   my @new_times;   
   push @new_times, $times[0];

   while ( scalar @new_order > 0 ) {
      my $choice = shift @new_order;
      push @new_times, $offset + $spacings[$choice-1];
      $offset += $spacings[$choice-1];
   }
   
   return @new_times;
}


=item B<generate_spacings>

Takes a list of values and returns a new list of the differences between each
pair of values (i.e. the 'spacings' between the data points). Note that the
spacings array returned is 1 element smaller than the value array (think
fenceposts).

   @spacings = generate_spacings(@values);
        
=cut
sub generate_spacings {
   my (@values) = @_;

   #This for loop starts from 1, because we want all the spaces between points.  
   my @spacings;   
   for ( my $i = 1; $i < scalar @values; $i++ ) {
      push @spacings, abs( $values[$i] - $values[$i-1] );      
   }
   
   return @spacings;
}


=item B<get_random_list>

Takes a positive integer number and returns a list of all integers from 1 to 
up to and including that integer, in random order.

   @random_ints = get_random_int_list($max_int);

=cut
sub get_random_int_list {
   my $n = shift;
   my @ordered = ();

   foreach my $i (1..$n) {
      $ordered[$i-1] = $i;
   }

   # Randomise the numbers.
   @ordered = shuffle(@ordered);

   return @ordered;
}


=item B<sort_by_number>

Returns a numerically sorted array.

   @sorted = sort_by_number(@unsorted);

=cut
sub sort_by_number { 
   my @vals = @_;
   #Implemented like this because of nasty problems with scope ($a and $b are
   #part of package Main otherwise, which breaks when called from outside this
   #package's namespace).
   return sort _by_number @vals;
};

# Private numeric sort routine. Public access is by the sort_by_number wrapper.
sub _by_number { $a <=> $b };



sub find_principal_intervals {
   my @times = @_;
   
   # Sort the times from smallest to largest...
   my @sorted_times = sort { $a <=> $b } @times;
   
   return generate_spacings(@sorted_times);
}



sub find_optimality {
   my ($observed, $optimal, $debug) = @_;

   # Make sure there are enough optimal intervals to do this calculation...
   return undef unless ( scalar(@{$optimal}) >= scalar(@{$observed}) );

   # Sort the observed intervals, smallest to largest...
   my @obs_sorted = sort { $a <=> $b } @{$observed};

   # Sort the optimal intervals, smallest to largest...
   my @opt_sorted = sort { $a <=> $b } @{$optimal};

   if ( $debug ) {
      use Data::Dumper; print Dumper @obs_sorted; print "*****\n";print Dumper @opt_sorted;
   }

   # Calculate the optimality of each observed interval...
   my $w = 0;
   for ( my $i=0; $i < scalar @obs_sorted; $i++ ) {
      my $t = abs( $obs_sorted[$i] - $opt_sorted[$i] );
      print "Adding $t to $w...\n" if $debug;
      $w += $t;
#      $w += abs( $obs_sorted[$i] - $opt_sorted[$i] );

   }

   # Intervals not observed are worth 1 each (most non-optimal)...
   #$w += scalar(@opt_sorted) - scalar(@obs_sorted);

   return $w;
}


sub find_window_length {
   my ($n_obs, $n_extra, $optimum_intervals) = @_;

   # Don't take extra (redundant) observations into account...
   my $max_idx = int($n_obs - $n_extra - 1);
   
   warn "max idx: $max_idx\n";
   
   # The window has no length if we have no observations...
   return 0 if $n_obs == 0;
   
   # Window is just large enough to hold every interval...
#   my $w_length = sum(@{$optimum_intervals}[0..$max_idx]);
   
   # Protect us from ridiculous numbers of observations...
   return undef unless defined $optimum_intervals->[$max_idx];
   
   # Window is the *relative* length required to hold the next interval...
   my $w_length = $optimum_intervals->[$max_idx];

   return $w_length;
}

sub find_n_extra {
   my ($u, $sensitivity, $n_initial) = @_;

   return int($u * $sensitivity * $n_initial);
}


=item B<get_times>

Pull the observation times from a hash of stored times. The hash has the form

%obs_hash = 2007-04-12T21:53:36+0000 => observation_[2007-04-12T21:53:36+0000],
            2007-04-12T23:16:20+0000 => observation_[2007-04-12T23:20:16+0000],
            2007-04-13T00:39:04+0000 => submitted,

For entries with successful observations, this routine pulls the actual
timestamp from the value. For pending entries, the start time (key) is used.
Failed entries are ignored.

Note that each value should really be a reference to a hash. But this is hard
to do with hashes shared between threads, hence this ugly solution. Hey, it
works...!

@times = get_times(%obs_hash);

=cut
sub get_times {
   my %obs_hash = @_;
   my @times;

   foreach my $start_time ( keys %obs_hash ) {

      # Skip failed scoring requests...
      next if ( $obs_hash{$start_time} ) =~ m/score failed/;

      # Skip failed requests...
      next if ( $obs_hash{$start_time} ) =~ m/request failed/;      

      # Skip incomplete, aborted, rejected or failed observations...
      next if $obs_hash{$start_time} =~ m/incomplete|abort|reject|fail/;
      
      
      # If the observation was successful, use the real obs time...
      if ( my ($st) = $obs_hash{$start_time} =~ m/observation_\[(.*)\]/ ) {
         push @times, $st;
      }
      # If it's an update message, use that time...
      elsif ( my ($ut) = $obs_hash{$start_time} =~ m/update_\[(.*)\]/ ) {
         
         # This is important to keep the window length accurate - an observation
         # could be in the middle of being updated, prior to being flagged as
         # a successful observation. If we ignore it, we'll submit the same
         # interval again.
         if ( $ut =~ m/none/ ) {
            push @times, $start_time;
         }
         else {
            push @times, $ut;
         }
      }

      # Use the start time if the observation is still unsent, pending or 
      # submitted...
      else {
         push @times, $start_time;
      }
   }

   return @times;
}

=back

=head1 COPYRIGHT

Copyright (C) 2003-2007 University of Exeter. All Rights Reserved.


=head1 AUTHORS

Eric Saunders E<lt>saunders@astro.ex.ac.ukE<gt>

=cut

1;
