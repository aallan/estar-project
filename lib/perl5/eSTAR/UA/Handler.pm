package eSTAR::UA::Handler;

# Basic handler class for SOAP requests for the User Agent. It also
# acts as a container class for eSTAR::SOAP::User class which handles
# authentication.

use lib $ENV{"ESTAR_PERL5LIB"};     

use strict;
use subs qw( new set_user ping echo new_observation handle_rtml get_option
             set_option );

#
# Threading code (ithreads)
# 
use threads;
use threads::shared;

#
# General modules
#
use SOAP::Lite;
use Digest::MD5 'md5_hex';
use Time::localtime;
use Sys::Hostname;
#use Net::Domain qw(hostname hostdomain);
use Config::Simple;
use Config::User;
use Data::Dumper;
use Fcntl qw(:DEFAULT :flock);

# 
# eSTAR modules
#
use eSTAR::SOAP::User;
use eSTAR::Logging;
use eSTAR::Observation;
use eSTAR::RTML;
use eSTAR::RTML::Build;
use eSTAR::RTML::Parse;
use eSTAR::Constants qw/:all/;
use eSTAR::Util;
use eSTAR::Config;

#
# Astro modules
#
use Astro::SIMBAD::Query;
use Astro::FITS::CFITSIO;
use Astro::FITS::Header;
use Astro::Catalog;
use Astro::Catalog::Query::Sesame;
my ($log, $process, $ua, $config);

# ==========================================================================
# U S E R   A U T H E N T I C A T I O N
# ==========================================================================

sub new {
  my ( $class, $user, $passwd ) = @_;
  
  my $self = bless {}, $class;
  $log = eSTAR::Logging::get_reference();
  $process = eSTAR::Process::get_reference();
  $ua = eSTAR::UserAgent::get_reference();
  $config = eSTAR::Config::get_reference();
  
  if( $user and $passwd ) {
    return undef unless $self->set_user( user => $user, password => $passwd );
  }
  
  $log->thread2( "Handler Thread", 
  "Created new eSTAR::UA::SOAP::Handler object (\$tid = ".threads->tid().")");
        
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
   
   $log->print( "SOAP Request: from $args{user} on ". ctime() );
   return $self;             
}

# ==========================================================================
# O P T I O N S  H A N D L E R S 
# ==========================================================================

# option handling
sub get_option {
   my $self = shift;

   $log->debug("Called get_option() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data.");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.")
   }
   
   # grab the arguement telling us what we're looking for...
   my $option = shift;

   my $value = $config->get_option( $option );
   if ( $value == ESTAR__ERROR ) {
      $log->error("Error: Unable to get value from configuration file" );
      die SOAP::Fault
     ->faultcode("Client.FileError")
     ->faultstring("Client Error: Unable to get value from configuration file");          
   }

   $log->debug("Returned RESULT message");
   return SOAP::Data->name('return', $value )->type('xsd:string');
} 

sub set_option {
   my $self = shift;

   $log->debug("Called set_option() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data.");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.")
   }
   
   my $option = shift;
   my $value = shift;

   my $status = $config->set_option( $option, $value );
   if ( $status == ESTAR__ERROR ) {
      $log->error("Error: Unable to set value in configuration file" );
      die SOAP::Fault
      ->faultcode("Client.FileError")
      ->faultstring("Client Error: Unable to set value in configuration file");          
   }

   $log->debug("Returned STATUS message" );
   return SOAP::Data->name('return', ESTAR__OK )->type('xsd:integer');

} 

# ==========================================================================
# D A T A  H A N D L E R S 
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

# test function
sub echo {
   my $self = shift;
   my @args = @_;

   $log->debug("Called echo() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data"
   }
     
   $log->debug("Returned ECHO message");
   return SOAP::Data->name('return', "ECHO @args")->type('xsd:string');
} 

# make a new observation
sub new_observation {
   my $self = shift;
   my %observation = @_;
   
   #use Data::Dumper;
   #print "eSTAR::UA::SOAP::Handler\n";
   #print "eSTAR::SOAP::User = " . Dumper($self->{_user}) . "\n";

   $log->debug("Called new_observation() from \$tid = ".threads->tid());
   
   # check we have a valid user object            
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data"
   }

   # OBSERVING STATE FILE
   # --------------------
   my $obs_file = 
      File::Spec->catfile( Config::User->Home(), '.estar', 
                           $process->get_process(), 'obs.dat' );
   
   $log->debug("Writing state to \$obs_file = $obs_file");
   #my $OBS = eSTAR::Util::open_ini_file( $obs_file );
  
   my $OBS = new Config::Simple( syntax   => 'ini', 
                                 mode     => O_RDWR|O_CREAT );
                                    
   if( open ( FILE, "<$obs_file" ) ) {
      close ( FILE );
      $log->debug("Reading configuration from $obs_file" );
      $OBS->read( $obs_file );
   } else {
      $log->warn("Warning: $obs_file does not exist");
   }                                  
                
   # VALIDATE DATA
   # -------------
   
   # check that RA and Dec are defined, either has been resolved using
   # Sesame, or was passed as part of the %observation hash object
   
   
   if ( defined $observation{'target'}  && $observation{'target'} ne '') {
   
     # resolve using Sesame
     $log->debug("Contacting CDS Sesame...");
     my $target;
     eval { my $sesame = new Astro::Catalog::Query::Sesame( 
                             Target => $observation{'target'} ); 
            my $catalog = $sesame->querydb();
            $target =  $catalog->popstar();  };
     if ( $@ ) {
        $log->warn(
           "Warning: Cannot contact CDS Sesame to resolve target" );
        $log->warn( "Warning: $@ " );   
     }
       
     if ( defined $target ) {        
        $observation{'ra'} =  $target->ra();                              
        $observation{'dec'} =  $target->dec();      
     }
     
     # fallback to SIMBAD      
     unless ( defined $observation{'ra'} && defined $observation{'dec'} ) {
     
       # we don't have an RA or Dec, timed out perhaps?
       $log->warn( 
        "Warning: Target is still unresolved following call to CDS Sesame" );
       $log->warn( "Warning: Falling back to SIMBAD..." );
       
       my @object;
       my $simbad = eSTAR::Util::query_simbad( $observation{'target'} );
       if ( defined $simbad ) {   
          @object = $simbad->objects( );
          if ( defined $object[0] ){
             # print out all the returned object names
             my $string = "";
             foreach my $j ( 0 ... $#object ) {
                $string = $string . " " . $object[$j]->name();
                unless ( $j == $#object ) { print ","; }
             }
             $log->debug( "Returned: $string" );
             $observation{'ra'} = $object[0]->ra();
             $observation{'dec'} = $object[0]->dec();    
          }
       } else {
          $log->warn( 
             "Warning: Cannot contact CDS SIMBAD to resolve target..." );
       };
     
     }
     
     # Must now have resolved the target, surely?                   
     unless ( defined $observation{'ra'} && defined $observation{'dec'} ) {
        $log->error('Error: RA and Dec undefined, target unresolved');
        return SOAP::Data->name('return', 'BAD TARGET')->type('xsd:string');
     }
     $log->debug("Resolved $observation{'target'} to (" .
                       $observation{'ra'} . ", " .  $observation{'dec'} . ")" );     
   }
    
   # check we have valid RA & Dec
   unless ( defined $observation{'ra'} && defined $observation{'dec'} ) {
     $log->error('Error: RA and Dec undefined, target unresolved');
     return SOAP::Data->name('return', 'BAD TARGET')->type('xsd:string');
   }

   # check we have either exposure time _or_ signal-to-noise
   unless ( defined $observation{'exposure'} || 
            defined $observation{'signaltonoise'} ) {
     $log->error('Error: Exposure time or S/N is undefined');
     return SOAP::Data->name('return', 'BAD EXPOSURE')->type('xsd:string');
            
   }
   
   # check we have an observation type, assume 'single' if undef'ed
   $observation{'type'} = 'SingleExposure' unless defined $observation{'type'};
   $observation{'followup'} = 0 unless defined $observation{'followup'};
   
   # check we have a passband, assume V-band if undefined
   $observation{'passband'} = 'V' unless defined $observation{'passband'};
   
   # UNIQUE ID
   # ---------
   
   # generate a unique ID for the observation, increment every time 
   # this routine is called and save immediately, therefore we should 
   # never duplicate ID's, of course we'll eventually run out of int's, 
   # I guess I'll have to modify the IA after that...  
   my $number = $OBS->param( 'obs.unique_number' ); 
 
   if ( $number eq '' ) {
      # $number is not defined correctly (first ever observation?)
      $OBS->param( 'obs.unique_number', 0 );
      $number = 0; 
   } 
   $log->debug("Generating unqiue ID: $number");
  
   # build string portion of identity
   my $version = $process->get_version();
   $version =~ s/\./-/g;
   
   my $string = ':UA:v'    . $version . 
                ':run#'    . $config->get_state( 'ua.unique_process' ) .
                ':user#'   . $observation{'user'};   
             
   # increment ID number
   $number = $number + 1;
   $OBS->param( 'obs.unique_number', $number );
   
   $log->debug('Incrementing observation number to ' . $number);
     
   # commit ID stuff to STATE file
   my $status = $OBS->save( $obs_file );
   
   unless ( defined $status ) {
     # can't read/write to options file, bail out
     my $error = "Error: Can not read/write to $obs_file";
     $log->error(chomp($error));
     return SOAP::Data->name('return', chomp($error))->type('xsd:string');
   } else {    
      $log->debug('Generated observation ID: updated ' . $obs_file );
      undef $OBS;
   }
   
   # Generate IDENTITY STRING
   my $id;   
  
   # format $number
   if ( length($number) == 1 ) {
       $id = '00000' . $number;
   } elsif ( length($number) == 2 ) {
       $id = '0000' . $number;
   } elsif ( length($number) == 3 ) {
       $id = '000' . $number;
   } elsif ( length($number) == 4 ) {
       $id = '00' . $number;
   } elsif ( length($number) == 5 ) {
       $id = '0' . $number;
   } else {
       $id = $number;
   }
   $id = $id . $string;
   $log->debug('ID = ' . $id);
   
   $number = undef;
  
   # OBSERVATION OBJECT
   # ------------------
   
   # create an observation object
   my $observation_object = new eSTAR::Observation( ID => $id );
   $observation_object->id( $id );
   $observation_object->type( $observation{'type'} );
   $observation_object->passband( $observation{'passband'} );
   $observation_object->status('pending');
   $observation_object->followup($observation{"followup"});
   $observation_object->username($observation{"user"});
   $observation_object->password($observation{"pass"});
   
   
   # build a score request
   my $score_message = new eSTAR::RTML::Build( 
             Port        => $config->get_option( "server.port"),
             Host        => $config->get_option( "server.host"),
             ID          => $id,
             User        => $config->get_option("user.user_name"),
             Name        => $config->get_option("user.real_name"),
             Institution => $config->get_option("user.institution"),
             Email       => $config->get_option("user.email_address") );
   
   # if we have no target name, make one up from the RA and Dec    
   unless ( defined $observation{"target"} ) {
      $observation{"target"} = $observation{"ra"} . ";" . $observation{"dec"};
   } 

   if ( defined $observation{'exposure'} ) {
      
      # build a score request
      $score_message->score_observation(
          Target => $observation{'target'},
          TargetType => $observation{'type'},
          RA       => $observation{'ra'},
          Dec      => $observation{'dec'},
          Exposure => $observation{'exposure'},
          Filter   => $observation{'passband'}  );
             
   } elsif ( defined $observation{'signaltonoise'} && 
             defined $observation{'magnitude'} ) {
      
      # build a score request
      $score_message->score_observation(
          Target => $observation{'target'},
          TargetType => $observation{'type'},
          RA     => $observation{'ra'},
          Dec    => $observation{'dec'},
          Snr    => $observation{'signaltonoise'},
          Flux   => $observation{'magnitude'},
          Filter   => $observation{'passband'} );        
   }
   
   $observation_object->score_request( $score_message );      
   
   # SCORE REQUEST
   # -------------
  
   # NODE ARRAY
   my @NODES;   

   # we might not have any nodes! So check!
   my $node_flag = 0;
   @NODES = $config->get_nodes();   
   $node_flag = 1 if defined $NODES[0];
   
   # if there are no nodes add a default menu entry
   if ( $node_flag == 0 ) {
      my $error = "Error: No known Discovery Nodes";
      $log->error( "Error: No known Discovery Nodes" );
      return SOAP::Data->name('return', $error )->type('xsd:string');
   }    
  
   my $dn_port = $config->get_option( "dn.port" );
   foreach my $i ( 0 ... $#NODES ) {
   
      my $score_request = $observation_object->score_request();
      my $score_rtml = $score_request->dump_rtml();
      
      # end point
      my $endpoint = "http://" . $NODES[$i] . ":" . $dn_port;
      my $uri = new URI($endpoint);
   
      # create a user/passwd cookie
      my $cookie = eSTAR::Util::make_cookie( 
                      $observation{"user"}, $observation{"pass"} );
  
      my $cookie_jar = HTTP::Cookies->new();
      $cookie_jar->set_cookie( 0, user => $cookie, '/', 
                              $uri->host(), $uri->port());

      # create SOAP connection
      my $soap = new SOAP::Lite();
  
      $soap->uri('urn:/node_agent'); 
      $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
      # report
      $log->print("Connecting to " . $NODES[$i] . "..." );
    
      # fudge RTML document?
      $score_rtml =~ s/</&lt;/g;

    
      # grab result 
      my $result;
      eval { $result = $soap->handle_rtml( 
               SOAP::Data->name('query', $score_rtml )->type('xsd:string')); };
      if ( $@ ) {
         $log->warn("Warning: Failed to connect to " . $NODES[$i] );
         next;    
      }
   
      # Check for errors
      unless ($result->fault() ) {
        $log->debug("Transport Status: " . $soap->transport()->status() );
      } else {
        $log->error("Fault Code   : " . $result->faultcode() );
        $log->error("Fault String : " . $result->faultstring() );
      }
      
      my $reply = $result->result();
      
      my $ers_reply;
      eval { $ers_reply = new eSTAR::RTML( Source => $reply ); };
      if ( $@ ) {
         $log->error("Error: Unable to parse ERS reply, not XML?" );
         next;    
      }
            
      # check for errors, if none stuff the score reply into the
      # observation object
      unless ( defined $ers_reply->determine_type() )  {
         $log->warn( "Warning: node $NODES[$i] must be down.." );
      } else {

         my $type = $ers_reply->determine_type();       
         $log->debug( "Got a '" . $type . "' message from $NODES[$i]");  
         my $score_reply = new eSTAR::RTML::Parse( RTML => $ers_reply );
         $observation_object->score_reply( $NODES[$i], $score_reply );
      
      }   
        
        
   } # end of "foreach my $i ( 0 ... $#NODES )" 
   
   # GRAB BEST SCORE
   # ---------------
   my ( $best_node, $score_reply ) = $observation_object->highest_score();
   my $score_request = $observation_object->score_request();
   
   # check we have any scores
   unless ( defined $best_node && defined $score_reply ) {
      my $error = "Error: No nodes able to carry out observation";
      $log->error( $error );
      return SOAP::Data->name('return', $error )->type('xsd:string');   
   }

   # grab best score and log it
   my $score_replies = $observation_object->score_reply();
   $score_reply = $$score_replies{$best_node};
   my $best_score = $score_reply->score();
   $log->print("Best score of $best_score from $best_node");

   # check the best score is not zero
   if ( $best_score == 0.0 ) {
      my $error = "Error: best score is $best_score, possible problem?";
      $log->error( $error );
      return SOAP::Data->name('return', $error )->type('xsd:string');   
   }
   
   # BUILD  OBSERVATION REQUEST
   # --------------------------
  
   $log->debug("Building an observation request");
  
   # build a observation request
   my $observe_message = new eSTAR::RTML::Build( 
             Port        => $config->get_option( "server.port"),
             Host        => $config->get_option( "server.host"),
             ID          => $observation_object->id(),
             User        => $score_request->user(),
             Name        => $score_request->name(),
             Institution => $score_request->institution(),
             Email       => $score_request->email() );

   if ( defined $observation{'exposure'} ) {
             
      $observe_message->request_observation(
                Target   => $score_request->target(),
                TargetType => $observation{'type'},
                RA       => $score_request->ra(),
                Dec      => $score_request->dec(),
                Score    => $score_reply->score(),
                Time     => $score_reply->time(),
                Exposure => $score_request->exposure(),
                Filter   => $score_request->filter()  );
                  
   } elsif ( defined $observation{'signaltonoise'} && 
             defined $observation{'magnitude'} ) {
             
      $observe_message->request_observation(
                Target   => $score_request->target(),
                TargetType => $observation{'type'},
                RA       => $score_request->ra(),
                Dec      => $score_request->dec(),
                Score    => $score_reply->score(),
                Time     => $score_reply->time(),
                Snr      => $score_request->snr(),
                Flux     => $score_request->flux(),
                Filter   => $score_request->filter()    );                   
   }
   
   # PUSH IT INTO THE OBSERVATION OBJECT
   # -----------------------------------

   # stuff the observation request into the observation object          
   $observation_object->obs_request( $observe_message );     
                                  
   # QUEUE REQUEST
   # -------------
  
   my $obs_request = $observation_object->obs_request();
   my $obs_rtml = $obs_request->dump_rtml();   
 
   # end point
   my $endpoint = "http://" . $best_node . ":" . $dn_port;
   my $uri = new URI($endpoint); 
   
   # create a user/passwd cookie
   my $cookie = eSTAR::Util::make_cookie( 
                   $observation{"user"}, $observation{"pass"} );
  
   my $cookie_jar = HTTP::Cookies->new();
   $cookie_jar->set_cookie( 0, user => $cookie, '/', 
                              $uri->host(), $uri->port());

   # create SOAP connection
   my $soap = new SOAP::Lite();
  
   $soap->uri('urn:/node_agent'); 
   $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
   # report
   $log->print("Connecting to " . $best_node . "..." );
   
   # fudge RTML document? 
   $obs_rtml =~ s/</&lt;/g;
    
   # grab result 
   my $result;
   eval { $result = $soap->handle_rtml(  
               SOAP::Data->name('query', $obs_rtml )->type('xsd:string') ); };
   if ( $@ ) {
      my $error = "Error: Failed to connect to " . $best_node;
      $log->error( $error );
      return SOAP::Data->name('return', $error )->type('xsd:string'); 
   }
   
   # Check for errors
   unless ($result->fault() ) {
     $log->debug("Transport Status: " . $soap->transport()->status() );
   } else {
     $log->error("Fault Code   : " . $result->faultcode() );
     $log->error("Fault String : " . $result->faultstring() );
   }   
   
   my $reply = $result->result();
      
   my $ers_reply;
   eval { $ers_reply = new eSTAR::RTML( Source => $reply ); };
   if ( $@ ) {
      my $error = "Error: Unable to parse ERS reply, not XML?";
      $log->error( $error );
      return SOAP::Data->name('return', $error )->type('xsd:string');           
   }
            
   # check for errors, if none stuff the score reply into the
   # observation object
   unless ( defined $ers_reply->determine_type() )  {
      $log->warn("Warning: node $best_node has gone down since scoring");
      $log->warn("Warning: discarding observation from queue");
      
      my $error = "Error: node $best_node has gone down since scoring";
      return SOAP::Data->name('return', $error )->type('xsd:string');
  
   } else {
      
      my $type = $ers_reply->determine_type();    
      $log->debug( "Got a '" . $type . "' message from $best_node");  
      my $obs_reply = new eSTAR::RTML::Parse( RTML => $ers_reply );
      $observation_object->obs_reply( $obs_reply );
    
      if ( $type eq 'confirmation' ) {
         $log->debug( $best_node . " confirmed start of observation" );
         $observation_object->status( 'running' );
         
         # SERIALISE OBSERVATION TO STATE DIRECTORY 
         # ========================================
         $log->debug( "Serialising \$observation_object to " .
                       $config->get_state_dir() );
         my $file = File::Spec->catfile(
                       $config->get_state_dir(), $id);
        
         # write the observation object to disk. Lets use a DBM backend next
         # time shall we?
         unless ( open ( SERIAL, "+>$file" )) {
           # check for errors, theoretically if we can't temporarily write to
           # the state directory this is no great loss as we'll create a fresh
           # observation object in the handle_rtml() routine if the unique id
           # of the object isn't known (i.e. it doesn't exist as a file in
           # the state directory
           $log->warn( "Warning: Unable to serialise observation_object");
           $log->warn( "Warning: Can not write to "  .
                            $config->get_state_dir());             
         
         } else {
           unless ( flock( SERIAL, LOCK_EX ) ) {
              $log->warn("Warning: unable to acquire exclusive lock: $!");
              $log->warn("Warning: Possible data loss...");
           } else {
              $log->debug("Acquiring exclusive lock...");
           } 
      
           # serialise the object
           my $dumper = new Data::Dumper([$observation_object],
                                         [qw($observation_object)]  );
           print SERIAL $dumper->Dump( );
           close(SERIAL);  
           $log->debug("Freeing flock()...");
        
         }
         
      } else {
         $log->debug( $best_node . " rejected the observation" );
         my $error = "Error: Observation rejected";
         $log->error( $error );
         return SOAP::Data->name('return', $error )->type('xsd:string'); 
      }
                
   }    
   
   # return sucess code
   $log->debug( "Returning 'QUEUED OK' message" );
   return SOAP::Data->name('return', 'QUEUED OK')->type('xsd:string');
   
}

# handle an incoming RTML document
sub handle_rtml {
   my $self = shift;
   my $rtml = shift;

   #print Dumper( $rtml );
   $log->debug("Called handle_rtml() from \$tid = ".threads->tid());
   
   # check we have a valid user object            
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data"
   }
   
   # Message Validation
   # ------------------
   
   # validate the incoming message
   my $rtml_message = new eSTAR::RTML( Source => $rtml );
   my $type = $rtml_message->determine_type();
   if ( defined $type ) {
     $log->debug( "Got a '" . $type . "' message");  
   } else {
     $log->warn( "Warning: Invalid RTML, attempting to parse it anyway.");
   }
   
   # Parse Message 
   # -------------
   
   # parse the incoming message
   my $message = new eSTAR::RTML::Parse( RTML => $rtml_message );
   my $id = $message->id();
   unless ( defined $id ) {
      $log->error( "Error: Unable to parse the RTML" );
      $log->error( $rtml . "\n" );
      return SOAP::Data->name('return', 'ERROR BAD RTML')->type('xsd:string');
   }   

   # Thaw Serialisation
   # ------------------
   $log->debug( "Thawing serialisation: $id" );  

   # Return any previous data from persistant store in the state directory
   my $observation_object = eSTAR::Util::thaw( $id );
   unless ( defined $observation_object ) {
     $log->warn("Warning: $id does not exist" );
     $log->warn("Warning: Creating new observation object...");
     $observation_object = new eSTAR::Observation( ID => $id );
     $observation_object->id( $id );
     $observation_object->type( $message->type() );
   }      
   $observation_object->status('returned');
     
        
   # UPDATE MESSAGE
   # ==============
   if ( $type eq "update" ) {
   
      # for now I'm going to pretty much ignore these as we can only have one
      # observation per observation request, therefore all the information in
      # this update message will be in the observation message that should
      # follow along in a few seconds
      $log->debug( 
       "Got an 'update' message. Waiting for end of observation marker...");      
      
      # I'm worried about doing anything here as I'm risking blowing away the
      # right version of the $observation_object which I'll thaw and re-freeze
      # when the observation message comes in as well. We could have both
      # this thread and that thread running at the same time, unless I want to
      # spend time doing proper file locking (which I can't be bothered with)
      # lets quickly update the $observation_object and reserialise. Before
      # bad things happen 
      
      # If we ever get manageld serialisations, this is the place we should
      # look to stop things getting mucked up
      $log->debug( "Storing 'update' RTML in \$observation_object");
      $observation_object->update($message);
      
      # re-serialise the object
      my $status = eSTAR::Util::freeze( $id, $observation_object ); 
      if ( $status == ESTAR__ERROR ) {
         $log->warn( 
            "Warning: Problem re-serialising the \$observation_object");
      }  
  
   # REJECT MESSAGE
   # ============== 
   } elsif ( $type eq "reject" ) { 
     
      $log->warn( "Warning: Got an 'reject' message...");      
      $log->warn( "Storing 'reject' RTML in \$observation_object");
     
      # we have a reject at this late stage, replace the obs_reply object
      # with the rejection message, shouldn't happen, but on occasion the
      # DN does do "late rejection", no idea why.
      $observation_object->obs_reply($message); 
      $observation_object->status('reject');        
       
      # re-serialise the object
      my $status = eSTAR::Util::freeze( $id, $observation_object ); 
      if ( $status == ESTAR__ERROR ) {
         $log->warn( 
            "Warning: Problem re-serialising the \$observation_object");
      } 
  
   # ABORT MESSAGE
   # =============
   } elsif ( $type eq "abort" ) { 
     
      $log->warn( "Warning: Got an 'abort' message...");      
      $log->warn( "Storing 'abort' RTML in \$observation_object");
 
      $observation_object->obs_reply($message); 
      $observation_object->status('abort');        
       
      # re-serialise the object
      my $status = eSTAR::Util::freeze( $id, $observation_object ); 
      if ( $status == ESTAR__ERROR ) {
         $log->warn( 
            "Warning: Problem re-serialising the \$observation_object");
      } 

   # OBSERVATION MESSAGE
   # ===================    
   } elsif ( $type eq "observation" ) {   
      $log->debug( "Storing 'observation' RTML in \$observation_object");
      $observation_object->observation($message);
  
      # Parse FITS header block
      # -----------------------
      $log->debug("Reading FITS Header Cards...");
      
      # grab FITS header
      my $hdu = $message->fitsheaders();
      
      # split into separate 80 character FITS cards
      my @cards = split( /\n/, $hdu );
      chomp(@cards);
      $log->debug("Header is " . scalar(@cards) . " lines long");
   
      # FITS File
      # ---------
   
      # grab a filename for the associated FITS image
      my $image_url = $message->dataimage();
      $image_url =~ m/(\w+\W\w+)$/;
      
      $log->debug( "Image URL is $image_url" );
     
      my $data = $1;
      
      my $data_path = $config->get_data_dir();
      $log->debug( "Path is $data_path");
      
      my $fits = File::Spec->catfile( $data_path, $data );
      $log->debug( "Saving file to $fits" );
                        
      # FITS Headers
      # ------------
      
      # parse cards into Header object
      $log->debug("Parsing FITS Headers...");
      my $header = new Astro::FITS::Header( Cards => \@cards );      
      
      # serialise the FITS Header block only if we think it might be valid
      if ( defined $header ) {
         $log->debug(
             "Attaching Astro::FITS::Header object to \$observation_object");  
         $observation_object->fits_header( $header );
      
         # grab date and time of observation from FITS Header
         my $date = $header->itembyname('DATE-OBS');
         unless ( defined $date ) {
            $log->warn("Warning: DATE-OBS FITS header keyword undefined");
         } else {   
            $log->debug("Observation taken at " . $date->value());      
         }
      } else {
         $log->warn("Warning: FITS Headers may be corrupted");
      }
                       
      # Grab Image Data
      # ---------------  
      $log->debug("URL is " . $image_url );
      $observation_object->fits_url( $image_url );
      
      # build request
      $log->debug( "Contacting " . 
                         $observation_object->node() ." host...");
      my $request = new HTTP::Request('GET', $image_url);
      my $reply = $ua->get_ua()->request($request);
    
      # check for valid reply
      if ( ${$reply}{"_rc"} eq 200 ) {
        #if ( ${${$reply}{"_headers"}}{"content-type"} 
        #     eq "application/octet-stream" ) {               
           $log->debug("Recieved image file from " . 
                         $observation_object->node() ." host");
                                
           # Open output file
           $fits =~ s/\W\w+$/.fit/;
           unless ( open ( IMAGE, ">$fits" )) {
              $log->error("Error: Cannot open $fits for writing");
           } else {  

              # Write to output file
              $log->debug("Saving image to $fits");
              $observation_object->fits_file( $fits );
              my $length = length(${$reply}{"_content"});
              syswrite( IMAGE, ${$reply}{"_content"}, $length );
              close(IMAGE);
           }
           
        #} else {
        #
        #   # unknown document, not of type octet-stream
        #   $log->warn(
        #       "Warning: Unknown document type recieved from " . 
        #                 $observation_object->node() ." host");
        #   $log->warn( "Warning: Unknown type is " .
        #       ${${$reply}{"_headers"}}{"content-type"});
        #      
        #}
      
      } else { 
      
        # the network conenction failed      
        $log->error(
          "Error: (${$reply}{_rc}): Failed to establish network connection");
        $log->error( "Error:" . ${$reply}{_msg} );

      }
      
      # Parse Cluster Catalog
      # ---------------------
      $log->debug( "Reading Cluter Catalog from RTML..." );
      my $catalog = $message->catalogue();
 
      # read catalog file        
      my $cluster = new Astro::Catalog( Format => 'Cluster', Data => $catalog );
      $log->debug("Parsed Cluster catalogue (" . 
                        $cluster->sizeof() ." lines)");
 
      # stuffing into observation object
      $observation_object->catalog( $cluster ); 
      
      # re-serialise the object
      my $status = eSTAR::Util::freeze( $id, $observation_object );
      if ( $status == ESTAR__ERROR ) {
         $log->warn( 
            "Warning: Problem re-serialising the \$observation_object");
      } else {
         $log->debug(
       "Inital processing complete, \$observation_object has been serialised.");
      }  
      
      # FOLLOWUP OBSERVATIONS
      # =====================
      
      # If this is an followup observation of type "Automatic $id" then
      # thaw the associated $id and attach this observation $id to the
      # $id of the observation we're following up. NB: This theoretically
      # might be dangerous as we coulsd have another thread also updating 
      # this $is state file, but I can't immediately think of a reason
      # why this might be the case, so lets risk it for now. Just try and
      # remember this be a problem if we're getting trashed state files
      my $obs_type = $observation_object->type();
      if( $obs_type =~ "Automatic" ) {
         $log->print("Identified automatic followup observation...");
         my $old_id = $obs_type;
         my $index = index($old_id, " "); 
         $old_id = substr( $old_id, $index+1, length($old_id)-$index );
         
         my $old_observation = eSTAR::Util::thaw( $old_id );
         
         unless ( defined $old_observation ) {
            $log->warn("Warning: Unable to restore old observation");
         } else {   
            $log->debug("Attaching new \$id to $old_id");
            $old_observation->followup_id( $id );
            
            my $status = eSTAR::Util::freeze( $id, $old_observation);
            if ( $status == ESTAR__ERROR ) {
               $log->warn( 
                  "Warning: Problem re-serialising the old observation");
            }
         }
      }        
      
         
      # HANDLE FOLLOWUP OBSERVATIONS
      # ============================
      
      # if the observation is _not_ of type SingleExposure, we need to
      # do additional followup observations if these are called for, look
      # in the ${ESTAR_PERL5LIB}/eSTAR/UA/Algorithim directory for modules
      # which correspond to the observation type. If present create a new
      # module of that type and call process_data( \$observation_object )
      # on the newly created Algorithm object.
    
      my $dir = File::Spec->catdir( $ENV{ESTAR_PERL5LIB}, 
                                    "eSTAR", "UA", "Algorithm" );
      my ( @files );
      if ( opendir (DIR, $dir )) {
         foreach ( readdir DIR ) {
            push( @files, $_ ); 
         }
         closedir DIR;
      } else {
         $log->error(
            "Error: Can not open algorithm directory ($dir) for reading" );      
      } 

      $log->debug(
        "Scanning algorithm directory for matching types...");

      my $found_flag = ESTAR__FALSE;

      # NB: first 2 entries in a directory listing are '.' and '..'
      foreach my $i ( 2 ... $#files ) {
         
         # grab current file name
         my $algorithm = $files[$i];
         
         # ignore the CVS directory
         next if $algorithm eq "CVS";
         
         # ignore if the file ends in ".bck"
         next if $algorithm =~ ".bck";
 
         # remove .pm from end of files
         $algorithm =~ s/\W\w+$//;
         
         # main check
         if ( $observation_object->type() eq $algorithm ) {
         
            # toggle flag
            $found_flag = ESTAR__TRUE;
         
            # full path
            $algorithm = "eSTAR::UA::Algorithm::" . $algorithm;
            
            # use the algorithim object
            $log->debug("Loading $algorithm");
            eval " use $algorithm; ";
            if ( $@ ) {
               $log->error("Error: Unable to load $algorithm");
               $log->error("Error: $@");
               last;
            }           
            
            # create new alogrithm object
            $log->debug("Creating an $algorithm object");
            my $object;
            eval { $object = $algorithm->new(); };
            if ( $@ ) {
               $log->error("Error: Unable to create $algorithm object");
               $log->error("Error: $@");
               last;
            }
            
            # pass control to that object
            $log->print("Passing control to $algorithm object");
            my $status;
            eval {$status = $object->process_data($observation_object->id());};
            if ( $@ ) {
               $log->error("Error: $@");
            } elsif ( $status != ESTAR__OK ) {
               $log->warn(
                      "Warning: process_data() routine returned bad status");
            } 
                      
            # break out of foreach loop   
            last;
                         
         } else {
            $log->debug("Ignoring $algorithm object...");
         }
      }
       
      unless ( $found_flag == ESTAR__TRUE ) {
         if ( $observation_object->type() =~ "Automatic" ) {
            # ignore if we have an observation of type "Automatic"
            $log->debug("Type is 'Automatic \$id' skipping...");
         } else {
           $log->warn( 
             "Warning: No matching algorithims for observations of type " .
             $observation_object->type() );      
         }
      }

   } # end of elsif ( $type eq "observation" )
   
   $log->debug( "Returning 'ACK' message" );
   return SOAP::Data->name('return', 'ACK')->type('xsd:string');
}

              
1;                                
                  
                  
                  
                  
                  
                  