package eSTAR::VT::Handler;

# Basic handler class for SOAP requests for the virtual telescope. It also
# acts as a container class for eSTAR::SOAP::User class which handles
# authentication.

use lib $ENV{"ESTAR_PERL5LIB"};     

use strict;
use subs qw( new set_user ping handle_rtml  );

#
# Threading code (ithreads)
# 
use threads;
use threads::shared;
use Thread::Semaphore;
#
# General modules
#
#use SOAP::Lite +trace =>   
# [transport => sub { print (ref $_[0] eq 'CODE' ? &{$_[0]} : $_[0]) }]; 
use SOAP::Lite;
use MIME::Entity;
use Digest::MD5 'md5_hex';
use Fcntl qw( :DEFAULT :flock );
use Time::localtime;
use Sys::Hostname;
use Net::Domain qw( hostname hostdomain );
use Config::Simple;
use Config::User;

use IO::Socket;
use DateTime;

# 
# eSTAR modules
#
use eSTAR::SOAP::User;
use eSTAR::Logging;
use eSTAR::LDAP::Search;
use eSTAR::Constants qw( :all);
use eSTAR::Util;
use eSTAR::Mail;
use eSTAR::Config;
use eSTAR::ADP::Util qw( get_network_time str2datetime build_dummy_header );

use XML::Document::RTML;
use Astro::Telescope;
use Astro::Coords;

my ($log, $process, $ua, $config);

# The Astro::Telescope object used for location information.
my $telescope;

my $semaphore = new Thread::Semaphore;
my %obs_schedule;
share(%obs_schedule);


# ==========================================================================
# U S E R   A U T H E N T I C A T I O N
# ==========================================================================

sub new {
   my ( $class, $user, $passwd ) = @_;

   my $self = bless {}, $class;
   $log     = eSTAR::Logging::get_reference();
   $process = eSTAR::Process::get_reference();
   $ua      = eSTAR::UserAgent::get_reference();
   $config  = eSTAR::Config::get_reference();

   if( $user and $passwd ) {
     return undef unless $self->set_user( user => $user, password => $passwd );
   }

   $log->thread2( "Handler Thread", 
     "Created new eSTAR::VT::Handler object (\$tid = ".threads->tid().")");

    # Instantiate a telescope object to simulate position on the Earth...    
    my %attrs_for = ( 
                      'lt' => {
                               name => 'Virtual LT',
                               long => 5.97113454, 
                               lat  => 0.502001024,
                               alt  => 2344,
                              },
                      'ftn' => {
                                name => 'Virtual FTN',                     
                                long => 3.55604516, 
                                lat  => 0.362078821,
                                alt  => 3055,
                               },
                      'fts' => {
                                name => 'Virtual FTS',
                                long => 2.60153048, 
                                lat  => -0.54577638,
                                alt  => 1150,
                               }
                             
                                                       );
    
    foreach my $name ( keys %attrs_for ) {
       my $proc_name = $process->get_process;
       if ( $proc_name =~ m/$name/i  ) {
          $log->thread2("Instantiating telescope with coords for $name...");
          $telescope = new Astro::Telescope(
                                             Name => $attrs_for{$name}->{name}, 
                                             Long => $attrs_for{$name}->{long},
                                             Lat  => $attrs_for{$name}->{lat},
                                             Alt  => $attrs_for{$name}->{alt}
                                            );         
         last;
       }
    }
    

   return $self;
}

# intialise and load specific user information into the main object
sub set_user {
   my ($self, %args ) = @_;
      
   $self->{_user} = new eSTAR::SOAP::User();
   unless ( ref($self) and $args{user} and 
            $self->{_user}->get_user($args{user})) {
            
      # user isn't know, return error string      
      undef $self->{_user};
      
      $log->warn("SOAP Request: Could not load data for $args{user}");
      return "Could not load data for $args{user}";
   }
   
   # user data is loaded beforehand, so that the password is available
   # for testing. If the validation fails, user object is destroyed
   # before the error is sent, so that the called does not accidentially
   # get the user data.
   if( $args{password} ) {

      unless( $args{password} eq $self->{_user}->passwd()) {
      
         undef $self->{_user};
      
         $log->warn("SOAP Request: Bad password for $args{user}");
         return "Bad password for $args{user}";
      }
      
   } elsif( $args{cookie} ) {

      unless( $args{cookie} eq 
              eSTAR::Util::make_cookie($args{user}, $self->{_user}->{passwd}) ) {
              
         undef $self->{_user};

         $log->warn(
            "SOAP Request: Authentication token for $args{user} invalid");
         return "Authentication token for $args{user} invalid";
      }
      
   } else {
   
      undef $self->{_user};

      $log->warn(
          "SOAP Request: No authentication present for $args{user}");
      return "No authentication present for $args{user}";
   
   } 
   
   $log->print( "SOAP Request: from $args{user} on ". get_network_time() );
   return $self;             
}


sub send_message { 
   my ($message, $host, $port) = @_;
   
   $log->debug( "send_message (\$tid = " . threads->tid() . ")" ); 
   
              
   # End point...
   my $endpoint = "http://" . $host . ":" . $port;
   my $uri = new URI($endpoint);
   
   # Create a user/passwd cookie...
   my $cookie = eSTAR::Util::make_cookie( $config->get_option( "ua.user" ), 
                             $config->get_option( "ua.passwd" ) );
    
   my $cookie_jar = HTTP::Cookies->new();
   $cookie_jar->set_cookie( 0, user => $cookie, '/', 
                              $uri->host(), $uri->port());

   # Create a SOAP connection...
   my $soap = new SOAP::Lite();
  
   $soap->uri('urn:/user_agent'); 
   $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
   # report
   $log->print("Connecting to " . $host . "..." );
   
   # fudge RTML document? 
   $message =~ s/</&lt;/g;
       
   # grab result 
   my $result;
   eval { $result = $soap->handle_rtml(  
               SOAP::Data->name('document', $message)->type('xsd:string') ); };
   if ( $@ ) {
      $log->error("Error: Failed to connect to " . $host );
   } else {
     
      # Check for errors
      unless ($result->fault() ) {
        $log->debug("Transport Status: " . $soap->transport()->status() );
      } else {
        $log->error("Fault Code   : " . $result->faultcode() );
        $log->error("Fault String : " . $result->faultstring() );
      }
      
      my $reply = $result->result();   
      $log->debug("Got a '" . $reply . "' message from $host" ); 
   
   }
   
   return;
};



# ==========================================================================
# H A N D L E R S 
# ==========================================================================

# test function
sub ping {
   my $self = shift;

   $log->debug("Called ping() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data"
   }
     
   $log->debug("Returned ACK message");
   return SOAP::Data->name('return', 'ACK')->type('xsd:string');
} 


sub is_dark {
   my $time     = shift;
   my $telescope = shift;
   
   my $sun = new Astro::Coords(planet => 'sun');
   $sun->datetime( $time );
   $sun->telescope( $telescope );

   my $sunrise = $sun->rise_time( horizon => Astro::Coords::AST_TWILIGHT );
   my $sunset  = $sun->set_time( horizon => Astro::Coords::AST_TWILIGHT );
   
   if ( $sunrise < $sunset ) {
      return wantarray() ? (1, $sunrise) : 1;
   }
   else {
      return wantarray() ? (0, $sunset) : 0;
   }
}

sub is_within_limits {
   my $target_el = shift;

   my $min_el = new Astro::Coords::Angle(30, units => 'deg');
#   $log->warn("target_el: " . $target_el->radians .  " min_el: " . $min_el->radians);
#   $log->warn("target_el: " . $target_el->degrees .  " min_el: " . $min_el->degrees);

   return ( $target_el > $min_el ) ? 1 : 0;
}

sub parse_rtml {
   my $rtml = shift;
   my $parsed;
   eval { $parsed = new XML::Document::RTML( XML => $rtml ) };
   if ( $@ ) {
      my $error = "Error: Unable to parse RTML file...";
      $log->error( "$@" );
      $log->error( $error );
      $log->error( "\nRTML File:\n$rtml" );
      throw eSTAR::Error::FatalError($error, ESTAR__FATAL);            
   }

   return $parsed;
}

sub sleep_until_obs_time {
   my ($start_time, $end_time, $thread_name) = @_;
   my $sleep_time = 1;

   OBS_LOOP:
   while ( 1 ) {
      my $status = check_obs_time($start_time, $end_time);

      # It's either time to observe, or we missed our slot - tell caller...
      return $status if defined $status;

      # Otherwise, cycle and try again in a few seconds...
      my $cur_time = get_network_time();
      $log->thread($thread_name, "start = $start_time, current = $cur_time)"
                   . " - sleeping...\n");
      sleep $sleep_time;
      next OBS_LOOP;
   }

}

sub check_obs_time {
      my ($start_time, $end_time) = @_;

      my $cur_time = get_network_time();
      
      $log->debug("Checked observation time. Current time is $cur_time...");
      $log->debug("Obs start time is $start_time...");
      
      # If we've missed the observation window...
      if ( $cur_time >= $end_time ) {
         return 0;
      }
      # If it's time to observe...
      elsif ( $cur_time >= $start_time ) {
        return $cur_time;
      }
      
      # It's not time yet...
      
      $log->debug("Not time to observe yet...");
      
      return undef;
}


sub build_and_send_message {
   my $message_type = shift;
   my $rtml         = shift;

   my @valid_messages = qw(update observation incomplete fail);

   # Complain unless we're asked to send a valid message...
   unless ( grep { $message_type =~ m/$_/ } @valid_messages ) {
      $log->warn("Invalid message type '$message_type' specified!");
      return undef;
   }


#   $log->debug("Parsing RTML for $message_type message (\$tid = " 
#               . threads->tid . ')');
   my $parsed = parse_rtml($rtml);

   # Insert the data array if this is an observation message...
   if ( $message_type =~ m/observation/ ) {
      my $data = shift;
      $parsed->data( @{$data} );
   }

   # Grab the update contents if this is an update message...
   my $obs_status = shift if $message_type =~ m/update/;


   my $msg;
   eval { $msg = $parsed->build( Type => "$message_type" ) };   

   if ( $@ ) { 
      $log->error("Error: Build of $message_type message failed: $@");
      return undef;
   }
   else {      
      $log->print( "$message_type message sent from manage_obs()..." );
      send_message($msg, $parsed->host, $parsed->port);
      return 1;
   }

}

sub determine_message_type {
   my ( $succeeded_obs, $failed_obs ) = @_;

   # The type of termination message depends on what observations occured...
   my $msg_type = $succeeded_obs == 0                     ? 'failed'
                : $succeeded_obs > 0 && $failed_obs > 0   ? 'incomplete'
                :                                           'observation'
                ;

   return $msg_type;
}



sub send_final_message {
   my ($msg_type, $rtml) = @_;


   # Make some fake data if the observation 'happened'...
   my $data = undef;
   if ( $msg_type eq 'observation' ) {
      # Build a FITS header, and insert the observation timestamp...
      my $time_now = get_network_time();
      my $header   = build_dummy_header( $time_now );
      $log->print( "Added obs timestamp '$time_now' to FITS header...\n" );

      # Build the data array that holds a catalogue, URL and the header. For now
      # the catalogue and URL are dummy placeholders.
      $data = [ {   
      Catalogue => 'http://161.72.57.3/~estar/data/c_e_20060910_36_1_1_1.votable',
      URL => 'http://161.72.57.3/~estar/data/c_e_20060910_36_1_1_2.fits',
      Header => $header } ];
   }

   # Send the message...
   build_and_send_message($msg_type, $rtml, $data);   
}


sub initialise_coordinates {
   my ($ra, $dec, $equinox, $time) = @_;

   # Instantiate an Astro::Coords object to represent the object...
   my $object = new Astro::Coords(
                                   ra    => $ra,
                                   dec   => $dec,
                                   type  => $equinox,
                                   units => 'sexagesimal'
                                  );

   # Associate the object with the telescope location...
   $object->telescope( $telescope );

   # Associate the object with the current time...
   
   $time = get_network_time() unless defined $time;
   
   $object->datetime ( $time );

   return $object;
}

# Lexical closure passed to a new asynchronous thread to manage an ongoing
# observation.
sub manage_obs {
   my $rtml = shift;
   my $thread_name = 'Obs Thread ' . threads->tid;
 
   # Parse the RTML scalar and store in an object...
#   $log->debug('Parsing RTML ($thread_name)');
   my $parsed = parse_rtml($rtml);
   
   
   # Grab the time constraints and convert back into DateTime objects...
   my @time_constraints = $parsed->time_constraint;
   my $start_time = str2datetime($time_constraints[0]);
   my $end_time   = str2datetime($time_constraints[1]);   
   
   # Counters for the number of observations that did and didn't happen...
   my $succeeded_obs = 0;
   my $failed_obs    = 0;

   # Send an update message after each group is completed...
   # Send one, even if the group count is 0...
   foreach ( 0 .. $parsed->group_count ) {
         
      # Sleep until it's time to observe...
      my $status = sleep_until_obs_time($start_time, $end_time, $thread_name);

      # Check we haven't missed the observation window...
      if ( $status ) {
         $log->thread($thread_name, "Observation is eligible to begin..."
                      . "(time is now $status)");
      }
      else {
         $log->warn("Observation end time exceeded - can't complete request...");
         $log->warn("$thread_name: Observation failed.");
         # Send an update indicating failure...
         build_and_send_message('update', $rtml, 'end time exceeded');
         
         # Note the failure...
         $failed_obs++;
         
         # Move on to the next observation...
         next;
      }


      # Check whether we can observe the object...
      my $object = initialise_coordinates($parsed->ra, $parsed->dec,
                                          $parsed->equinox);

      my $current_time = get_network_time();
      
      # Set the horizon to something conservative (matches timn's OBSPLAN)
      my $horizon = new Astro::Coords::Angle(30, units => 'deg');

      # Find the transit times of these coords...
      my $rise_time = $object->rise_time( horizon => $horizon->radians );
      my $set_time  = $object->set_time( horizon => $horizon->radians );


      # Check whether the object is in the observable sky...
      if ( is_within_limits($object->el) ) {
         $log->warn("$thread_name: Observable     (object sets at  $set_time)");
      }
      else {
         $log->warn("$thread_name: Not observable (object rises at $rise_time)");
         $log->warn("$thread_name: Observation failed.");
         # Send an update indicating failure...
         build_and_send_message('update', $rtml, 'object not observable');

         # Note the failure...
         $failed_obs++;
         
         # Move on to the next observation...
         next;
      }


      # Check whether it's dark or not...
      my @dark_status = is_dark($current_time, $telescope);
      if ( $dark_status[0] ) {
         $log->warn("$thread_name:"
                      . "It is night    (next sunrise at $dark_status[1])");
      }
      else {
         $log->warn("$thread_name:"
                      . "It is day      (next sunset at  $dark_status[1])");
         $log->warn("$thread_name: Observation failed.");
         # Send an update indicating failure...
         build_and_send_message('update', $rtml, 'it is day');
         
         # Note the failure...
         $failed_obs++;
         
         # Move on to the next observation...
         next;      
      }
   

      # If we've got to here then the observation can happen.

      # Simulate a readout delay...
      #sleep 2;

      $log->warn("$thread_name: Observation successful!");

      # Send an update indicating success...
      build_and_send_message('update', $rtml, 'observation successful');

      # Note the success...
      $succeeded_obs++;
   }
   
   
   # Send a termination message once the request has reached completion...
   my $msg_type = determine_message_type($succeeded_obs, $failed_obs);
   send_final_message($msg_type, $rtml);

};


sub manage_schedule {
   my $thread_name = 'Schedule Manager ' . threads->tid;
   

   
   # Continuously poll the shared schedule for observations...
   while ( 1 ) {
      #$log->debug("Checking for pending observations...");

      OBSERVATION:
      foreach my $id ( keys %obs_schedule ) {
         #print "Here with id: $id...\n";
         #print "status = $obs_schedule{$id}->{status}\n";
#         use Data::Dumper;print Dumper %obs_schedule;die;


         # Only consider pending observations...
         next OBSERVATION unless $obs_schedule{$id}->{status} eq 'pending';
      
         $log->debug("Pending obs found. Checking time constraints...");
      
         my $rtml = $obs_schedule{$id}->{rtml};
         # Parse the RTML scalar and store in an object...         
#         $log->debug('Parsing RTML ($tid = ' . threads->tid . ')');
         my $parsed = parse_rtml($rtml);

         my @time_constraints = $parsed->time_constraint;
         my $start_time = str2datetime($time_constraints[0]);
         my $end_time   = str2datetime($time_constraints[1]);
         
         # Counters for the number of observations that did and didn't happen...
         my $succeeded_obs = 0;
         my $failed_obs    = 0;
   
         GROUP:
         foreach ( 0 .. $parsed->group_count ) {
                  
            my $status = check_obs_time($start_time, $end_time);
            # Move on to the next observation if it's not time yet...
            next OBSERVATION unless defined $status;

            # Check we haven't missed the observation window...
            if ( $status ) {
               $log->thread($thread_name, "Observation is eligible to begin..."
                            . "(time is now $status)");
            }
            else {
               $log->warn("Observation end time exceeded - can't complete request...");
               $log->warn("$thread_name: Observation failed.");
               # Send an update indicating failure...
               build_and_send_message('update', $rtml, 'end time exceeded');

               # Note the failure...
               $failed_obs++;

               # Move on to the next observation...
               next GROUP;
            }        
      
            my $object = initialise_coordinates($parsed->ra, $parsed->dec, 
                                                $parsed->equinox);
      
      
            my $current_time = get_network_time();
      
            # Set the horizon to something conservative (matches timn's OBSPLAN)
            my $horizon = new Astro::Coords::Angle(30, units => 'deg');

            # Find the transit times of these coords...
            my $rise_time = $object->rise_time( horizon => $horizon->radians );
            my $set_time  = $object->set_time( horizon => $horizon->radians );


            # Check whether the object is in the observable sky...
            if ( is_within_limits($object->el) ) {
               $log->warn("$thread_name: Observable     (object sets at  $set_time)");
            }
            else {
               $log->warn("$thread_name: Not observable (object rises at $rise_time)");
               $log->warn("$thread_name: Observation failed.");
               # Send an update indicating failure...
               build_and_send_message('update', $rtml, 'object not observable');

               # Note the failure...
               $failed_obs++;

               # Move on to the next observation...
               next GROUP;
            }
      
            # Check whether it's dark or not...
            my @dark_status = is_dark($current_time, $telescope);
            if ( $dark_status[0] ) {
               $log->warn("$thread_name:"
                            . "It is night    (next sunrise at $dark_status[1])");
            }
            else {
               $log->warn("$thread_name:"
                            . "It is day      (next sunset at  $dark_status[1])");
               $log->warn("$thread_name: Observation failed.");
               # Send an update indicating failure...
               build_and_send_message('update', $rtml, 'it is day');

               # Note the failure...
               $failed_obs++;

               # Move on to the next observation...
               next GROUP;      
            }
      
            # If we've got to here then the observation can happen.

            # Simulate a readout delay...
            #sleep 2;

            $log->warn("$thread_name: Observation successful!");

            # Send an update indicating success...
            build_and_send_message('update', $rtml, 'observation successful');

            # Note the success...
            $succeeded_obs++;
         }

         # Send a termination message once the request has reached completion...
         my $msg_type = determine_message_type($succeeded_obs, $failed_obs);
         send_final_message($msg_type, $rtml);
         
         $obs_schedule{$id}->{status} = $msg_type;      
      }

      sleep 1;      
   }

}


# subroutine to handle incoming RTML requests from user_agent(s)

sub handle_rtml {
   my $self = shift;
   my $rtml = shift;

   $log->debug("Called handle_rtml() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data"
   }
   
        
   # Parse the RTML scalar and store in an observation object...
   my $parsed = parse_rtml($rtml);
   
   # RTML response from virtual telescope here

   # Set up simple probabilistic weather...
   my $sunny_factor = 1.0;      
   my $obs_weather = rand;
#   my $obs_weather = 1.0;

   
   my $response;
   # If the message is a score request, return a score...
   if ( $parsed->type eq 'score' ) {

      my @time_constraints = $parsed->time_constraint;
      my $start_time = str2datetime($time_constraints[0]);
      
#      print "ra: " . $parsed->ra . "\n";   
#      print "dec: " . $parsed->dec . "\n";   
#      print "equinox: " . $parsed->equinox . "\n";   

      my $object = initialise_coordinates($parsed->ra, $parsed->dec, 
                                          $parsed->equinox, $start_time);


      # Set the horizon to something conservative (matches timn's OBSPLAN)
      my $horizon = new Astro::Coords::Angle(30, units => 'deg');

      # Find the transit times of these coords...
      my $rise_time = $object->rise_time( horizon => $horizon->radians );
      my $set_time  = $object->set_time( horizon => $horizon->radians );

      my $score;

      # Check whether the object is in the observable sky...
      my @dark_status = is_dark($start_time, $telescope);
      
      if ( is_within_limits($object->el) && $dark_status[0] ) {
         $log->warn("Scoring request: Target will be observable at $start_time.");

         # Generate a random score...
         $score = $sunny_factor - $obs_weather;


      }
      else {
         $log->warn("Scoring request: Target can't be observed at $start_time.");
         $score = 0;
      }




      # For now, completion date is always now + 4 weeks...
      # TODO: Should be based on the requested date.
      my $completion_time = get_network_time();
      $completion_time->add( weeks => 4 );

      # Build the score response...
      $parsed->score( $score );
      $response = $parsed->build( Type           => 'score',
                                  CompletionTime => $completion_time );
                                  
      $log->warn("Received score request. Returning score of $score.");           
            
   }
   # If the message is an observation request, reply (confirm or reject)...
   elsif ( $parsed->type eq 'request' ) {     
      # If the document already has a score, then that implies a previous round
      # of score requesting, so we need to use that - otherwise, we use our 
      # calculated score...
      ######### NOTE: THIS IS POTENTIALLY A SERIOUS SECURITY HOLE! ########
      $obs_weather = $parsed->score if defined $parsed->score;
            
      # Confirm or deny, depending on the weather...
      if ( $obs_weather < $sunny_factor ) {
         $log->warn("Queuing request (weather ok)...");
         $response = $parsed->build( Type => 'confirmation' );
         
         # Start the observation management thread, if this is the first obs...
         my $proc_name = eSTAR::Process::get_reference->get_process();
         my $schedule_lock_file = "$ENV{HOME}/.estar/$proc_name/tmp/sch.dat";


         unless ( -e $schedule_lock_file ) {
            $log->print("Spawning schedule manager thread...");
            my $obs_thread = threads->create( \&manage_schedule);
            #$obs_thread->detach;
            system "touch $schedule_lock_file";
         }         

         # Add the observation to the shared schedule...

#         $semaphore->down;
         $log->error("No id defined for this observation!") unless $parsed->id;
         $log->warn("id is" . $parsed->id);
         
         my %obs_data:shared;
         %obs_data = ( rtml => $response,
                       status => 'pending');                         
         $obs_schedule{$parsed->id} = \%obs_data;
         
#         $semaphore->up;


         # Accepted the request - delegate to a thread for this observation...
#         $log->print("Spawning observation thread...");
#         my $obs_thread = threads->create( \&manage_obs, $response );

         # Instruct perl to free the thread memory when it's done...
#         $obs_thread->detach;



      }
      # Reject the request, and forget about it...   
      else {
         $log->warn("Rejecting score request based on weather.");
         $response = $parsed->build( Type => 'reject' );
      }

   }
   # It's an unknown type of document. Complain...
   else {
      my $error = "Unknown document type '" . $parsed->type . "' detected!";
      $log->error( $error );
      $log->error( "\nRTML File:\n$rtml" );
      throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
   }
   

   # SEND TO USER_AGENT
   # ------------------
   
   # do a find and replace, munging the response, shouldn't need to do it?
   # (hack for some versions of SOAP::Lite)
   #$log->debug( "Returned RTML message\n$response");
   $response =~ s/</&lt;/g;
   
   # return an RTML response to the user_agent
   $log->debug("Returned RTML response");
   return SOAP::Data->name('return', $response )->type('xsd:string');
} 

                             
1;                                
                  
                  
                  
