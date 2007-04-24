#!/software/perl-5.8.6/bin/perl


=head1 NAME

adaptive_vs_scheduler.pl - command line client to run an optimised variable
star monitoring campaign.

=head1 SYNOPSIS

  perl ${ESTAR_BIN}/adaptive_vs_scheduler.pl

=head1 DESCRIPTION

A command line client that implements the optimal sampling algorithm of Saunders
et al. (2006), A&A, for the efficient monitoring of periodic variable stars.

=head1 AUTHORS

Alasdair Allan (aa@astro.ex.ac.uk), Eric Saunders (saunders@astro.ex.ac.uk)

=head1 REVISION

$Id: adaptive_vs_scheduler.pl,v 1.2 2007/04/24 16:52:42 saunders Exp $

=head1 COPYRIGHT

Copyright (C) 2003, 2007 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

use strict;
use warnings;
use vars qw / $VERSION $log /;

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR User Agent Software:\n";
      print "Adaptive Scheduling Client $VERSION; Perl Version: $]\n";
      exit;
    }
  }
}

# L O A D I N G -------------------------------------------------------------

use threads;
use threads::shared;
use Thread::Queue;

# eSTAR modules
use lib $ENV{ESTAR_PERL5LIB};
use eSTAR::Nuke;
use eSTAR::Logging;
use eSTAR::Constants qw( :status ); 
use eSTAR::Util;
use eSTAR::Process;
use eSTAR::ADP qw( generate_linear_series find_optimal_base 
                   generate_log_series find_principal_intervals
                   find_window_length find_optimality get_times );
use eSTAR::ADP::Util qw( get_network_time str2datetime init_logging 
                         get_first_datetime datetime_strs2theorytimes
                         theorytime2datetime);

# general modules
#use SOAP::Lite +trace => all;  
use SOAP::Lite;
use Digest::MD5 'md5_hex';
use URI;
use HTTP::Cookies;
use IO::Socket::INET;
use DateTime;
use DateTime::Duration;

use Sys::Hostname;
use Config::User;
use Getopt::Long;
use List::Util qw( max );

# Set up logging...
my $log_verbosity = ESTAR__DEBUG;
$log = init_logging('Adaptive Variable Star Scheduler', $VERSION, $log_verbosity);



# C O M M A N D   L I N E   A R G U E M E N T S -----------------------------

my ( %opt, %obs_request );

# grab options from command line
my $status = GetOptions( 
                         "soaphost=s"    =>   \$opt{soaphost},
                         "soapport=s"    =>   \$opt{soapport},
                         "user=s"        =>   \$obs_request{user},
                         "pass=s"        =>   \$obs_request{pass},
                         "ra=s"          =>   \$obs_request{ra},
                         "dec=s"         =>   \$obs_request{dec},
                         "target=s"      =>   \$obs_request{target},
                         "exposure=s"    =>   \$obs_request{exposure},
                         "sn=s"          =>   \$obs_request{signaltonoise},
                         "mag=s"         =>   \$obs_request{magnitude},
                         "passband=s"    =>   \$obs_request{passband},
                         "type=s"        =>   \$obs_request{type},
                         "followup=s"    =>   \$obs_request{followup},
                         "groupcount=s"  =>   \$obs_request{groupcount},
                         "starttime=s"   =>   \$obs_request{starttime},
                         "endtime=s"     =>   \$obs_request{endtime},
                         "seriescount=s" =>   \$obs_request{seriescount},
                         "interval=s"    =>   \$obs_request{interval},
                         "tolerance=s"   =>   \$obs_request{tolerance},
			 "toop=s"        =>   \$obs_request{toop},
                         "tcpport=i"     =>   \$opt{tcpport},
                         "schedule=s"    =>   \$opt{schedule},
                        );


# Default hostname for the user agent...
$opt{soaphost} = '127.0.0.1' unless defined $opt{soaphost};

# Default soap port for the user agent...
$opt{soapport} = 8000 unless defined $opt{soapport};

# Default tcp port for listening for replies from the user agent...
$opt{tcpport} = 6666 unless defined $opt{tcpport};


# Build soap endpoint to the user agent...
my $endpoint = "http://$opt{soaphost}:$opt{soapport}";
my $uri = new URI($endpoint);
$log->debug("Connecting to server at $endpoint");


# Set obs_request defaults...
$obs_request{type}     = 'VariableMonitor' unless defined $obs_request{type};
$obs_request{followup} = 0                unless defined $obs_request{followup};
unless ( defined $obs_request{user} && defined $obs_request{pass} ) {
   $obs_request{user} = 'saunders';
   $obs_request{pass} = 'vstar';
}


# Set up the shared agent memory...
my $obs_times_for_bi_vir:shared;
my $obs_times_for_bm_vir:shared;
my %obs_of_target:shared;

$obs_times_for_bi_vir = &share({});
$obs_times_for_bm_vir = &share({});
%obs_of_target = (
                      'BI Vir' => $obs_times_for_bi_vir,
                      'BM Vir' => $obs_times_for_bm_vir,
                     );

# Status values are:
#  unsent         - not sent at all
#  pending        - in the process of sending
#  score failed   - no nodes, or all nodes returned score 0. Not sent.
#  request failed - scoring worked, but no confirmation came back
#  submitted      - sent and queued
#  observation    - observation succeeded
#  incomplete (not implmented yet)
#  fail or failed - observation failed
my $obs_request_queue = Thread::Queue->new;




# Build a set of observations...
my $n_obs;

my $undersampling = 3;
my $n_initial = 2;
my $n_total = 60;
my $run_length_in_days = 10;
my $p_min_in_hours     = 2.67;

my %coords_for = ( 
                   'BI Vir' => {
                                 ra  => '12:29:30.42',
                                 dec => '+00:13:27.78',
                                 exp => 5,
                                },
                   'BM Vir' => { 
                                 ra  => '12:31:55.64',
                                 dec => '+00:54:30.85',
                                 exp => 5,
                                }
                  );


my $runlength = DateTime::Duration->new(hours => $run_length_in_days * 24);

# Find the optimal base and set of optimum intervals...
my ($opt_base, $opt_ints) = find_sampling_base($undersampling, $n_total);

                                         
# Create a TCP/IP server to accept and process information returned by the UA...
my $tcpip_server = new_tcpip_server($opt{tcpport}, \&process_message);

# Start the thread that runs the TCP/IP server...
my $tcpip_thread = threads->create( $tcpip_server );

# Start the thread that monitors the status of the observations...
my $adp_thread = threads->create(\&evaluate_schedule_progress, $n_initial,
                                 $n_total);


# Create authentication cookie...
$log->debug('Creating authentication token');
my $cookie = eSTAR::Util::make_cookie($obs_request{user}, $obs_request{pass});
my $cookie_jar = HTTP::Cookies->new();
$cookie_jar->set_cookie(0, user => $cookie, '/', $uri->host, $uri->port);

# Create SOAP connection...
$log->print("Building SOAP client..."); 
my $soap = new SOAP::Lite();
$soap->uri('urn:/user_agent');
$soap->proxy($endpoint, cookie_jar => $cookie_jar);

# NOTE:
# This assumes all observations are the same, apart from the time constraints...
my $request_thread = threads->create(\&obs_request_sender, \%obs_request,
                                     \%coords_for);


# Hang around until the ADP thread thinks we're done...
my $adp_status = $adp_thread->join();




sub obs_request_sender {
   my $obs_request_ref = shift;
   my $coords_for = shift;

   # Make observation requests for the observations in the schedule...
   while ( my $req = $obs_request_queue->dequeue ) {
      my ($target, $start_time) = @{$req};

      # Add the target-specific fields...
      $obs_request_ref->{target}   = $target;
      $obs_request_ref->{ra}       = $coords_for->{$target}->{ra};
      $obs_request_ref->{dec}      = $coords_for->{$target}->{dec};
      $obs_request_ref->{exposure} = $coords_for->{$target}->{exp};

      my $dt = str2datetime($start_time);
      # Set the end time for the observing sequence to something arbitrary...
      my $end_time  = $dt +  DateTime::Duration->new( minutes => 30 );


      # Stringify the observation time constraints...
      $obs_request_ref->{starttime} = "$start_time";
      $obs_request_ref->{endtime}   = "$end_time";

      # Make the SOAP request...
      request_observation($obs_request_ref);
   }
}



sub request_observation {
   my $obs_request_ref = shift;   


   # Dump observation parameters to the log...
   log_obs_request($obs_request_ref);

   my $result;
   eval { $result = $soap->new_observation( %{$obs_request_ref} ); };
   if ( $@ ) {
     $log->error("Error returned by \$soap->new_observation: $@");
     exit;   
   }

   # Check for errors...
   $log->debug("Transport Status: " . $soap->transport()->status() );
   if ( $result->fault ) {
      $log->error("Fault Code      : " . $result->faultcode );
      $log->error("Fault String    : " . $result->faultstring );
   }
   else {
      $log->print("SOAP Result     : " . $result->result );
      my $obs_code = undef;

      # Handle *scoring* rejection scenarios, where $result->result gives:
      # 'Error: No nodes able to carry out observation'
      # 'Error: best score is $best_score, possible problem?'

      if ( $result->result =~ m/^Error: No nodes|^Error: best score/i ) {

         $log->warn("Scoring indicates no available nodes.");              
         $obs_code = 'score failed';
      }


      # Handle *request* rejection scenarios, where $result->result gives:
      # 'Error: Failed to connect to'
      # 'Error: Unable to parse ERS reply, not XML?'
      # 'Error: node $best_node has gone down since scoring'
      # 'Error: Observation rejected.'
      elsif ( $result->result =~ m/
                                   ^Error: \s* Failed \s* to \s* connect\ s* to
                                  |^Error: \s* Unable \s* to \s* parse
                                  |^Error: \s* node
                                  |^Error: \s* Observation \s* rejected
                                                                 /imx ) {

         $log->warn("Scoring was successful, but request failed.");
         $obs_code = 'request failed';
      }
      else {
         $obs_code = 'submitted';
      }




      # Update the shared schedule for the benefit of the other threads...
      my $target = $obs_request_ref->{target};
      my $start_time = $obs_request_ref->{starttime};
      $obs_of_target{$target}->{$start_time} = $obs_code;
   }
   
   return;
}


sub log_obs_request {
   my $obs_request_ref = shift;

   my $target = $obs_request_ref->{target};

   open my $req_fh, '>>', 
   "/home/saunders/testing/estar/requests_$target.obs" 
   or warn "Couldn't open file to write request fields log:$!";


   print $req_fh "\n";
   # Dump observation parameters to the log...
   foreach my $key ( keys %{$obs_request_ref} ) {
     my $parameter = defined $obs_request_ref->{$key} 
                     ? $obs_request_ref->{$key} 
                     : q{};
     print $req_fh "$key => $parameter\n";
   }

   close $req_fh;
   
   return;
}


sub evaluate_schedule_progress {
   my $name = "ADP Thread";
   my $n_initial = shift;
   my $n_total = shift;
   
   $log->debug("Started $name...");


   
   # Initialise the flag structure to keep track of each programme's progress...
   my %complete_flag_for;
   foreach my $target ( keys %obs_of_target ) {
      $complete_flag_for{$target} = undef;
      $log->debug("Initialising completeness flag for $target...");
   }
   
   
   # Poll the memory periodically until all the observations are complete...
   OBS_PENDING:
   while ( 1 ) {   
      # Consider each target programme seperately...
      TARGET:
      foreach my $target ( keys %obs_of_target ) {
         print "Considering target $target...\n";
         next TARGET if $complete_flag_for{$target};
      
         my $n_obs_in_progress = scalar(get_times(%{$obs_of_target{$target}}));
   
         sleep 5;
      
         print_summary($target);
      
         open my $obs_fh, '>', 
            "/home/saunders/testing/estar/submissions_$target.obs" 
            or warn "Couldn't open file to write submissions:$!";

         print $obs_fh "$_ $obs_of_target{$target}->{$_}\n" 
            for (sort keys %{$obs_of_target{$target}});
         close $obs_fh;
      
      
         # Only queue more if we're below our limit...
         if ( $n_obs_in_progress < $n_total ) {
            queue_obs($target);      
            # Loop while observations can still be placed...
            next TARGET;
         }

         # Need this to catch the last few submitted obs...
         foreach my $obs_id ( keys %{$obs_of_target{$target}} ) {         
            
            # Don't stop if there are outstanding observations...
            my $obs_status = $obs_of_target{$target}->{$obs_id};
                        
            if (    $obs_status =~ m/unsent/
                 || $obs_status =~ m/pending/ 
                 || $obs_status =~ m/submitted/ ) {
                           
                next TARGET;
            }
         }
      
         # This target's observations are accounted for...
         $complete_flag_for{$target} = 1;   
         $log->print("All $n_total observations in schedule for $target complete.");

      }

      # Loop again as long as there are unfinished targets...
      next OBS_PENDING if ( grep { !defined $_ } values(%complete_flag_for) );

      # All targets are complete. Escape the loop!
      last OBS_PENDING;
   }

   $log->print("All observations have been completed.");

   foreach my $target ( keys %obs_of_target ) {
      print_summary($target);
   }

   return 1;
}


sub print_summary {   
   my $target = shift;

   # Print a summary of the schedule results...
   my $unsent       = 0;
   my $score_fail   = 0;
   my $request_fail = 0;
   my $pending      = 0;
   my $submitted    = 0;
   my $succeeded    = 0;
   my $failed       = 0;
   foreach my $obs ( keys %{$obs_of_target{$target}} ) {
      $unsent++       if $obs_of_target{$target}->{$obs} =~ m/^unsent/;
      $score_fail++   if $obs_of_target{$target}->{$obs} =~ m/^score failed/;
      $request_fail++ if $obs_of_target{$target}->{$obs} =~ m/^request failed/;      
      $pending++      if $obs_of_target{$target}->{$obs} =~ m/^pending/;
      $submitted++    if $obs_of_target{$target}->{$obs} =~ m/^submitted/;
      $succeeded++    if $obs_of_target{$target}->{$obs} =~ m/^observation/;
      $failed++       if $obs_of_target{$target}->{$obs} =~ m/^fail
                                                             |^incomplete
                                                             |^abort
                                                             |^reject/x;
   }

   my $sent = $submitted + $succeeded + $failed;
   my $n_obs = scalar( keys %{$obs_of_target{$target}} );

   my $now = get_network_time();
   my $first = get_first_datetime( keys %{$obs_of_target{$target}} );
   my ($run_fraction) = datetime_strs2theorytimes($first, $runlength, "$now");

   print "********************SUMMARY FOR TARGET $target*********************\n";
   print "* The time is now $now\n";
   
   $run_fraction = $run_fraction * 100;
   printf "* %3.1f%% of the $run_length_in_days day target observing run has elapsed.\n",
      $run_fraction;
   printf "* $succeeded observations have been completed successfully, from a possible $n_total (%3.1f%%)\n",
      calc_percent($succeeded, $n_total);

   print $n_obs == 1 ? "* $n_obs observation has been scheduled:\n"
                     : "* $n_obs observations have been scheduled:\n";

   printf "* %4.0f unsent (%3.1f%%).\n", $unsent, calc_percent($unsent, $n_obs);
   printf "* %4.0f pending (%3.1f%%).\n", $pending, calc_percent($pending,$n_obs);
   printf "* %4.0f additional observations were scored at 0, and never queued.\n", $score_fail;
   printf "* %4.0f additional observations were scored but the request failed, and were never queued.\n", $request_fail;

   printf "* %4.0f sent to the grid (%3.1f%%), of which:\n", 
                                       $sent, calc_percent($sent,$n_obs);
   printf "*    %4.0f outstanding (%3.1f%%).\n", $submitted, 
                                          calc_percent($submitted, $n_obs);
   printf "*    %4.0f succeeded (%3.1f%%).\n", $succeeded,
                                          calc_percent($succeeded, $n_obs);
   printf "*    %4.0f failed    (%3.1f%%).\n", $failed, 
                                          calc_percent($failed, $n_obs);
   print "*****************END OF SUMMARY FOR TARGET $target*****************\n";
}


sub queue_obs {
   my $target = shift;
   
   my $queued = 0;

   # The maximum number of obs we can place in one go is n initial...
   my $n_available = $n_initial;

      
   # Evaluate the status of the observations to date...
   foreach my $time ( sort keys %{$obs_of_target{$target}} ) {   
      
      # Check whether any score 0 requests have occured. If so, short-circuit
      # any further obs until a suitable time-interval has elapsed.
      if ( $obs_of_target{$target}->{$time} =~ m/score failed/ ) {
         
#         $log->warn("Detected a score failure in the obs list at $time. Evaluating...");
         
         # Set a sleep time to stop us hammering the down telescopes.
         # This could be replaced in future if the telescope returns an 
         # indication of when it will be back up (e.g. a continuum score).
         my $sleep_interval = DateTime::Duration->new(seconds => 1800);
         my $resume_time    = str2datetime($time) + $sleep_interval;
         my $current_time   = get_network_time();
         if ( $current_time < $resume_time ) {
            $log->warn("Blocking further observation submissions until " 
                        . "$resume_time due to score failure" 
                        . " (current time is $current_time)...");
            return;
         }
         else {
#            $log->print("Sleep time exceeded for this request - proceeding...");
         }

      }

      # Reduce the number of available observations by the number outstanding...
      if ( 
           $obs_of_target{$target}->{$time} =~ m/unsent/  ||
           $obs_of_target{$target}->{$time} =~ m/pending/ ||
           $obs_of_target{$target}->{$time} =~ m/submitted/  
                                                             ) {           
           $n_available--;
       }
   }  
   
   # Redundancy stuff to go here...
   my $n_surplus = 0;
      
   # If we have any obs to place, it's time to calculate and place them...
   while ( $n_available > 0 ) {
      
      # Find the window length...
      # Ignore failed observations.
      # A subtlety: Use obs time for successful obs, not start time...

#      use Data::Dumper; 
#      $log->warn("[$target] Current hash values: " . Dumper(%{$obs_of_target{$target}}));

      my @current_real_times = get_times(%{$obs_of_target{$target}});

      my $n_obs_in_progress = scalar @current_real_times;
      my $window_length = find_window_length($n_obs_in_progress, $n_surplus,
                                             $opt_ints);



      $log->warn("[$target] $n_obs_in_progress obs observed or pending...");      
      $log->warn("[$target] $n_available observations currently available...");
      $log->warn("[$target] window length is $window_length...");
      
      # Initialise trackers for best position and time...
      my $new_obs_time = undef;
      my $w_pos_best   = 1;
      my $first_datetime;
      
      # Deal with the special case of the first observation...
      if ( $window_length == 0 ) {
         $log->warn("[$target] Placing special first observation...");
      
         $w_pos_best = 0;
         $new_obs_time = 0;
         $first_datetime = get_network_time();
      }
      # Or, this isn't the first observation...
      else {
      
         # Add a small amount to the window length, to fix the boundary bug...
         # WARNING: This is a hack with hardcoded values!
         # 35 min = 0.583333hrs = 0.024305555 days
         # In a 10 day run, that means fuzzy_int = 0.0024305555.         
         my $fuzzy_int = 0.002430555555;
         $window_length += $fuzzy_int;
            
         # Find the set of observed and pending intervals...
         
         $first_datetime = get_first_datetime(@current_real_times);
         my @theorytimes = datetime_strs2theorytimes($first_datetime, $runlength,
                                                 @current_real_times);
         my @all_ints    = find_principal_intervals(@theorytimes);


         # The largest allowed interval is relative to the largest observed or
         # pending observation...
         my $largest_time = max(@theorytimes);            
         $log->warn("[$target] Largest theoretical timestamp observed or"
         . " pending to date is $largest_time...");
      
         # Find the current theory time...
         my $datetime_now = get_network_time();
#         my $theory_time_now = ($datetime_now - $first_datetime) / $runlength;
#         my ($theory_time_now) = datetime_strs2theorytimes($first_datetime,
#                                  $runlength, "$datetime_now");      

         # Stupid hack to deal with datetime weirdness if values are very small
#         $theory_time_now = 0 if $theory_time_now < 0;

         # Determine the subset of optimum intervals to consider...
         #use Data::Dumper;
         #print Dumper $largest_time, $window_length, $theory_time_now;

         # Each observation taken so far could be up to 30 minutes later than 
         # expected (the expire time for the obs).
         # So the window length needs an additional contribution which covers
         # these extra potential overruns, n x 30 minutes.
         


         my @allowed_ints = grep { $_ <= $window_length } @{$opt_ints};   

         #$log->warn("[$target] Allowed intervals are:");
         #$log->warn("   $_") for @allowed_ints;
      
         my $best_int = undef;
         if ( @allowed_ints ) {
            # Foreach interval (starting with the largest)...   
            foreach my $pos_interval ( @allowed_ints ) {
               my $w_pos = undef;

               $w_pos = find_optimality([@all_ints, $pos_interval],$opt_ints);

               # Keep track of the best interval so far...
               if ( $w_pos < $w_pos_best ) {
                  $w_pos_best = $w_pos;
                  $best_int   = $pos_interval;
               }
            }
         
            # Calculate the timestamp...
            $new_obs_time = $best_int + $largest_time;
            $log->warn("[$target] Best observation is the interval $best_int, "
                       . "with w = $w_pos_best, at theorytime $new_obs_time.");
         
         }

         # If we didn't have any intervals, then we are dealing with redundant
         # observations.

         else {
            $log->warn("[$target] Placing redundant observation...");
            die "This is not implemented yet!!!\n";
         }
      }
      
      $log->warn("[$target] This corresponds to a theoretical timestamp of $new_obs_time.");
      
      $n_available--;
      # Convert the theory time to a real time...
      my $datetime_to_submit = theorytime2datetime($new_obs_time, 
                                                   $first_datetime,
                                                   $runlength);
 
      $log->warn("[$target] This corresponds to a *real* timestamp of $datetime_to_submit (+ 5 minutes).");
      $log->warn("   *************************************************");
 
      # Put in an offset so that we are asking for something just in future...
      my $offset = DateTime::Duration->new( minutes => 5 );
      $datetime_to_submit = $datetime_to_submit + $offset;
      
      # Enqueue the observation...                                                  
      $obs_of_target{$target}->{"$datetime_to_submit"} = 'pending';
      my $req:shared;
      $req = &share([]);
      @{$req} = ($target, "$datetime_to_submit");
      $obs_request_queue->enqueue($req);
      $queued++;
      $log->warn("[$target] Submitted: start time: $datetime_to_submit\n");
      

   }
 
   if ( $queued ) {
      my $ob_plurality = $queued == 1 ? 'observation' : 'observations';
      $log->warn("[$target] Queued $queued $ob_plurality...");
   }
   
   return;
}



sub calc_percent {
   my $numerator = shift;
   my $denominator = shift;

   return $denominator == 0 ? 0 : 100 * $numerator / $denominator;
}

sub build_schedule {
   my ($schedule, $n_obs, $run_length_in_days, $p_min_in_hours) = @_;

   my @run_schedule;

   # Build a linear schedule...
   if ( $schedule eq 'linear' ) {
      @run_schedule = build_linear_schedule($n_obs, $run_length_in_days);
   }
   # Build a logarithmic schedule...
   elsif ( $schedule eq 'logarithmic' ) {
      @run_schedule = build_logarithmic_schedule($n_obs, $run_length_in_days,
                                                 $p_min_in_hours);
   }
   # Request a single observation...
   elsif ( $schedule eq 'single' ) {
      my $date1 = build_single_observation();
      @run_schedule = ( $date1 );
   }
   # Default to a single test observation...
   else {
      my $date1 = build_test_observation();
      @run_schedule = ( $date1 );
   }

   return @run_schedule;
}


sub build_logarithmic_schedule {
   my $n_total = shift;
   my $run_length_in_days = shift;
   my $p_min_in_hrs = shift;

   # Convert input times into seconds...
   my $p_min_in_secs = $p_min_in_hrs * 3600;
   my $run_length_in_secs = $run_length_in_days * 24 * 3600;

   my $p_min       = DateTime::Duration->new( seconds => $p_min_in_secs );
   my $run_length  = DateTime::Duration->new( seconds => $run_length_in_secs );

   print "p_min (secs): "      . $p_min->delta_seconds     . "\n";
   print "run_length (secs): " .$run_length->delta_seconds . "\n";

   my $p_min_rel = $p_min->delta_seconds / $run_length->delta_seconds;
   print "p_min_rel: $p_min_rel\n";

   my $max_rel_freq = 1 / $p_min_rel;
   print "max_rel_freq: $max_rel_freq\n";

   print "n_total: $n_total\n";
   my $undersampling_ratio = 2 * $max_rel_freq / $n_total;
   print "Undersampling ratio: $undersampling_ratio\n";

   # Use the ratio to choose the correct line...
   my @ratio_files = 
                  qw( /home/saunders/optimal_base_data/2.0_nyquist_dataset.dat
                      /home/saunders/optimal_base_data/5.0_nyquist_dataset.dat);

   my $opt_base = find_optimal_base($undersampling_ratio, $n_total, 
                                    @ratio_files);

   print "Optimal base is: $opt_base\n";

   # Fall back to a linear schedule if the optimal base is 1...
   return build_linear_schedule($n_total, $run_length_in_days) if $opt_base == 1;

   # Build the series normalised between 0 and 1...
   my @log_series = generate_log_series($n_total, $opt_base);

   my $start_date = build_single_observation();
   
   # Generate the set of dates...
   my @run_schedule;
   while ( @log_series ) {
      my $frac_date = shift @log_series;
      my $seconds_from_start = int($run_length_in_secs * $frac_date);
      my $current_date = $start_date 
                     + DateTime::Duration->new( seconds => $seconds_from_start);
      push @run_schedule, $current_date;
      print "$frac_date => $current_date\n";
   }

   return @run_schedule;
}


sub build_linear_schedule {
   my $n_obs = shift;
   my $run_length_in_days = shift;
   my $spacing_in_days = $run_length_in_days / $n_obs;

   my $current_date = build_single_observation();


   # TODO: Come back and make this robust...
   # Generate the set of dates...
   my $spacing;
   if ( $spacing_in_days > 1 ) {
      $spacing = DateTime::Duration->new( days => $spacing_in_days );
   }
   else {
      my $spacing_in_hours = $spacing_in_days / 24;
      $spacing = DateTime::Duration->new( hours => $spacing_in_hours );
   }
   
   my @run_schedule;
   for ( 1 .. $n_obs ) {
      push @run_schedule, $current_date;
      $current_date = $current_date + $spacing;
   }   

   print "Run plan generated...\n";
   print "Plan covers the range: $run_schedule[0] - $run_schedule[9]\n";
   print "Individual dates are:\n";
   print "   $_\n" for @run_schedule;

   return @run_schedule;
}


sub build_single_observation {
   my $start_date = shift || get_network_time();
   
   # Set an arbitrary offset so the observation doesn't start immediately...
   my $offset       = DateTime::Duration->new( days => 1.5 );
   my $current_date = $start_date + $offset;
   
   return $current_date;
}


# Provides a fixed date for testing against.
sub build_test_observation {
   my $test_date = DateTime->new(
                                  year       => 2007,
                                  month      => 2,
                                  day        => 14,
                                  hour       => 21,
                                  minute     => 6,
                                  second     => 3,
                                  nanosecond => 0,
                                  time_zone  => "floating",
                                 );
   $test_date->set_time_zone("UTC");
   
   return $test_date;
}


sub process_message {
   my $listen = shift;
   my $thread_name = 'Incoming Message Thread';
   
   # Match something of the form 'key = value', and grab the value...
   my $regex_tail = '\s*=\s*(.*)';
   
   # Set up the different matches for the information we're interested in...
   my %regex_for = (
                     target      => "^target$regex_tail", 
                     id          => "^id$regex_tail", 
                     status      => "^status$regex_tail",
                     type        => "^type$regex_tail",
                     starttime   => "^start time$regex_tail",
                     timestamp   => "^FITS timestamp$regex_tail",
                     messagetype => "^message type$regex_tail",
                    );
   
   # Log where this message came from...
   my $peer_host = $listen->peerhost;
   my $peer_port = $listen->peerport;
   $log->thread2( $thread_name, "Peer address is $peer_host:$peer_port" );

   my %incoming;
   
   # If the socket is talking...
   while ( my $in = <$listen> ) {
      
      # Look through each of our match keywords...
      foreach my $field ( keys %regex_for ) {
         # Move on if we've previously acquired a value for this keyword...
         next if defined $incoming{$field};
         
         # ...Otherwise try matching the keyword regex with what's coming in...
         ($incoming{$field})  = $in =~ m/$regex_for{$field}/i;
      }     
            
   }

   # Dump the list of matches to a log for sanity checking...
   foreach my $field ( keys %incoming ) {
      next unless defined $incoming{$field};
      $log->debug("Received: [$field] => [$incoming{$field}]");
   }

   $log->thread2( $thread_name, "Message terminated at " . get_network_time() );

   # Protect us from errors in the incoming data...
   unless ( defined $incoming{target} ) {
      $log->warn("Received message contains no target!");
      return;
   }
   
   unless ( defined $incoming{starttime} ) {
      $log->warn("Received message contains no start time!");
      return;
   }
   
   unless ( defined $incoming{messagetype} ) {
      $log->warn("Received message contains no message type!");
      return;
   }
    
   # Update the shared agent memory...
   if ( defined $obs_of_target{$incoming{target}}->{$incoming{starttime}} ) {
      $obs_of_target{$incoming{target}}->{$incoming{starttime}} 
         = "$incoming{messagetype}_[$incoming{timestamp}]";
   }
   # The starttime doesn't match our records - this is very wrong...
   else {
      $log->warn(
         "Incoming start time matches no known observation we have requested!");
   }

   return;
}   



# Simple processor for debugging.
sub echo_message {
   my $listen = shift;
   my $thread_name = 'Incoming Message Thread';

   # Log where this message came from...
   my $peer_host = $listen->peerhost;
   my $peer_port = $listen->peerport;
   $log->thread2( $thread_name,  "Peer address is $peer_host:$peer_port" ); 

   # Take the message...
   while ( <$listen> ) {
      #chomp;
      print $_, "\n";
   }

   $log->thread2( $thread_name, "Message terminated at " . get_network_time() );

   return;
};


# Returns a subroutine reference suitable for passing to a new thread, which
# runs a TCP/IP server and calls the provided message processing routine on
# the incoming data.

#   $tcpip_server =  new_tcpip_server($host, $tcp_port, $msg_processor);

sub new_tcpip_server {
   my $tcp_port          = shift;
   my $message_processor = shift;

   my $host = hostname;

   return sub {
      my $thread_name = 'TCP/IP Thread ' . threads->tid();

      # Create TCP/IP daemon...
      $log->thread($thread_name, "Starting server on $host:$tcp_port");
      my $tcp_daemon = new IO::Socket::INET( 
                                             LocalPort => $tcp_port,
                                             Proto     => 'tcp',
                                             Listen    => 5,
                                             Reuse     => 1,
                                            );

      # Complain and die if there was a problem initialising the socket...
      unless ( $tcp_daemon ) {
         chomp( my $error = $@ );
         return "FatalError: $error";
      };
      $log->thread($thread_name, "TCP/IP server up at port $tcp_port");

      # Listen for connections, and pass them to a sub-thread for processing...
      my $n = 1;
      while ( my $listen = $tcp_daemon->accept ) {
         $log->thread( $thread_name,  "Reading from TCP/IP socket... " );
         $log->thread( $thread_name,
                       "Spawning sub-thread to handle incoming message..." );

         # Thread on accept...
         my $msg_thread = threads->create( $message_processor, $listen );

         # Instruct perl to free the thread memory when it's done...
         $msg_thread->detach;
         print "Received message $n...\n";
         $n++;
      } 

      return;
   }
}



# Find the set of optimum points in theoretical space (0..1), given an 
# undersampling rate and the number of observations. Note that when this is
# translated into real times, the maximum and minimum periods are constrained by
# the values provided here. More obs, or higher undersampling, will give a 
# smaller minimum period, while the maximum is defined by the run length.

sub find_sampling_base {
   my ($undersampling_ratio, $n_total) = @_;


   # The ratios from saunders et al. 2006 needed for interpolation of the
   # undersampling value.
   my @ratio_files = 
   qw( /home/saunders/optimal_base_data/2.0_nyquist_dataset.dat
       /home/saunders/optimal_base_data/5.0_nyquist_dataset.dat);

   my $opt_base = find_optimal_base($undersampling_ratio, $n_total,
                                    @ratio_files);

   $log->print("For undersampling=$undersampling_ratio, and $n_total
                observations, optimal base is calculated to be $opt_base");

   # Write the ideal times and gaps to disk as a sanity check...

   my @optimum_times = generate_log_series($n_total, $opt_base);
   my @optimum_ints   = find_principal_intervals(@optimum_times);


   # This should write to the data dir, not hardcoded...

   open my $obs_fh, '>', "/home/saunders/testing/estar/ideal_times.obs" 
      or warn "Couldn't open file to write ideal times:$!";

   print $obs_fh "$_\n" for @optimum_times;
   close $obs_fh;
   
   open my $gaps_fh, '>', "/home/saunders/testing/estar/ideal_gaps.obs" 
      or warn "Couldn't open file to write ideal gaps:$!";

   print $gaps_fh "$_\n" for @optimum_ints;
   close $gaps_fh;

   return ($opt_base, \@optimum_ints);
}

