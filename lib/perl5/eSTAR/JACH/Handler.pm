package eSTAR::JACH::Handler;

# Basic handler class for SOAP requests for the Embedded Agent. It also
# acts as a container class for eSTAR::SOAP::User class which handles
# authentication.

use strict;
use subs qw( new set_user ping handle_rtml handle_data get_option
             set_option dump_hash );

#
# Threading code (ithreads)
# 
use threads;
use threads::shared;

#
# General modules
#
#use SOAP::Lite +trace =>   
# [transport => sub { print (ref $_[0] eq 'CODE' ? &{$_[0]} : $_[0]) }]; 
use SOAP::Lite;
#use SOAP::MIME;
use MIME::Entity;
use Digest::MD5 'md5_hex';
use Time::localtime;
use Sys::Hostname;
use Net::Domain qw(hostname hostdomain);
use Config::Simple;
use Config::User;
use Fcntl qw(:DEFAULT :flock);
use Data::Dumper;
#use Video::Capture::V4l;
#use Video::RTjpeg;

# 
# eSTAR modules
#
use eSTAR::SOAP::User;
use eSTAR::Logging;
use eSTAR::Observation;
use eSTAR::LDAP::Search;
use eSTAR::RTML;
use eSTAR::RTML::Build;
use eSTAR::RTML::Parse;
use eSTAR::Error qw /:try/;
use eSTAR::Constants qw/:status/;
use eSTAR::Util;
use eSTAR::JACH::Running;

#
# Astro modules
#
use Astro::Coords;
use Astro::WaveBand;
use Astro::FITS::Header;
use Astro::FITS::Header::CFITSIO;

# 
# JACH modules
use lib $ENV{"ESTAR_OMPLIB"};
use OMP::SciProg;
use OMP::SpServer;
my ($log, $run, $ua);

# ==========================================================================
# U S E R   A U T H E N T I C A T I O N
# ==========================================================================

sub new {
  my ( $class, $user, $passwd ) = @_;
  
  my $self = bless {}, $class;
  $log = eSTAR::Logging::get_reference();
  $run = eSTAR::JACH::Running::get_reference();
  $ua = eSTAR::UserAgent::get_reference();
  
  if( $user and $passwd ) {
    return undef unless $self->set_user( user => $user, password => $passwd );
  }
  
  $log->thread2( "Handler Thread", 
    "Created new eSTAR::JACH::Handler object (\$tid = ".threads->tid().")");
        
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
sub dump_hash {
   my $self = shift;

   $log->debug("Called dump_running() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data.");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.")
   }
   
   $log->debug("Returned \%running hash");
   my $string = Dumper( %{ $run->get_hash() } );
   return SOAP::Data->name('return', $string )->type('xsd:string');
} 


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

   my $value = eSTAR::Util::get_option( $option );
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

   my $status = eSTAR::Util::set_option( $option, $value );
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
   my $args = shift;

   $log->debug("Called ping() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.");
   }
     
   $log->debug("Returned ACK message");
   return SOAP::Data->name('return', 'ACK')->type('xsd:string');
} 

# H A N D L E   R T M L ------------------------------------------------------

sub handle_rtml {
   my $self = shift;
   my $document = shift;

   $log->debug("Called handle_rtml() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.");
   }
   
   # Parse Incoming RTML
   # -------------------
     
   my $rtml;
   eval { $rtml = new eSTAR::RTML( Source => $document ); };
   if ( $@ ) {
      print $@;
      my $error = "Error: Unable to parse RTML document";
      $log->error( $error );
      return SOAP::Data->name('return', $error )->type('xsd:string');       
   } 
   
   # determine type
   my $type = $rtml->determine_type();
   $log->debug( "Got a '" . $type . "' message");  
   my $parsed = new eSTAR::RTML::Parse( RTML => $rtml );
   
   # OBSERVATION OBJECT
   # ------------------
   
   # Deserialise the Observation object relating to the unique ID of 
   # the observation if it exists, if not create a new observation object 
   # to stuff all related stuff into...
   
   # grab the id of the incoming request...
   my $id = $parsed->id();

   # see if we can deserialise against this id
   my $observation_object = thaw( $id );   
   #use Data::Dumper; print Dumper( $observation_object );
   
   # if not create a new observation object
   unless ( defined $observation_object ) {
      $log->debug( "Creating a new object for ID = $id");
      $observation_object = new eSTAR::Observation( ID => $id );   
   }
   
   # Handle RTML
   # -----------
   
   # do actions depending on type, incoming documents should be of
   # type "score" or type "request", theoretically we shouldn't have
   # to deal with documents of types other than these
   if ( $type eq "score" ) {
   
      # SCORE REQUESTS
      # --------------
      $observation_object->status('scoring');
      $observation_object->score_request( $parsed );
        
      # grab the coordinates
      my $coords = new Astro::Coords( ra  => $parsed->ra(),
                                      dec => $parsed->dec(),
                                      type => $parsed->equinox() );
      
      my $scope = eSTAR::Util::get_option("dn.telescope");
      $coords->telescope( $scope );
      
      # report the coordinates for the request
      #my $status = $coords->status();
      #chomp($status);
      $log->debug("Astro::Coords object: $coords");
      
      # CO-ORDS OBSERVABLE
      # ------------------
      
      # check to see if the object is observable
      
      my $isobs = $coords->isObservable();         # observable now
      $log->debug($scope->name()." isObservable() returns '".$isobs."'");
      
      my $time;
      if( $isobs ) {
         $time = $coords->set_time();
         $log->debug("Object is above horizon, sets at " . $time);
      } else {
         $time = $coords->datetime();
         $log->debug("Object is below horizon....");
      }   
      my $time_string = $time->datetime();
      
      # HAVE FILTER?
      # ------------
      
      # check to see we have the correct filter, theoretically we should
      # check the telescope, and then the instrument we're specifically
      # using. For now lets just use the is_observable() method.
      
      if( Astro::WaveBand::has_filter( "UIST" => $parsed->filter() ) ) {
      #if ( Astro::WaveBand::is_observable( 
      #    eSTAR::Util::get_option( "dn.telescope") => $parsed->filter() ) ) {
          
          # don't modify an already set $isobs
          $log->debug(  eSTAR::Util::get_option( "dn.telescope") . " has a " . 
                      $parsed->filter() . " filter on an available instrument" );
      } else {
                         
          # $isobs must now be set to bad
          $isobs = 0;
          $log->warn(  eSTAR::Util::get_option( "dn.telescope") . 
                      " doesn't have a " . $parsed->filter() . " filter...");
      }
                          
      # BUILD MESSAGE
      # -------------
      
      # build the score response document
      my $score_message = new eSTAR::RTML::Build( 
             Port        => $parsed->port(),
             Host        => $parsed->host(),
             ID          => $parsed->id(),
             User        => $parsed->user(),
             Name        => $parsed->name(),
             Institution => $parsed->institution(),
             Email       => $parsed->email() );

      if ( defined $parsed->exposure() ) {
         
         # build a score request
         $score_message->score_response(
             Target   => $parsed->target(),
             RA       => $parsed->ra(),
             Dec      => $parsed->dec(),
             Exposure => $parsed->exposure(),
             Score    => $isobs,
             Time     => $time_string  );
             
      } elsif ( defined $parsed->snr() && 
                defined $parsed->flux() ) {

         # build a score request
         $score_message->score_response(
             Target => $parsed->target(),
             RA     => $parsed->ra(),
             Dec    => $parsed->dec(),
             Snr    => $parsed->snr(),
             Flux   => $parsed->flux(),
             Score  => $isobs,
             Time   => $time_string );        
      }

      # push the reply into the observation_object
      $observation_object->score_reply( $score_message );
      my $status = freeze( $observation_object ); 
      if ( $status == ESTAR__ERROR ) {
         $log->warn( 
            "Warning: Problem re-serialising the \$observation_object");
      }
      
      # pritn a warning line if it isn't observable    
      if ( $isobs == 0.0 ) {
        $log->warn( "Warning: score is zero, target unobservable" );
      }  
              
      # dump rtml to scalar
      my $score_response = $score_message->dump_rtml();
      #use Data::Dumper; print Dumper( $score_message );
      
      # do a find and replace, munging the response, shouldn't need to do it?
      #$score_response =~ s/</&lt;/g;
                
      # return the RTML document
      $log->debug("Returned RTML message");
      return SOAP::Data->name('return', $score_response )->type('base64');
      
   } elsif ( $type eq "request" ) {

      # update observation object
      $observation_object->status('running');
      $observation_object->obs_request( $parsed );

      # user information
      # ----------------
      my $user = $self->{_user};
      #use Data::Dumper; print Dumper( $user );

      # check that this user has time on the telescope, if not send an
      # RTML fail message...
      my $username = $user->name();

      # build the reject response document in case we need it
      my $reject_message = new eSTAR::RTML::Build( 
          Port        => $parsed->port(),
          Host        => $parsed->host(),
          ID          => $parsed->id(),
          User        => $parsed->user(),
          Name        => $parsed->name(),
          Institution => $parsed->institution(),
          Email       => $parsed->email() );

      # build a score request
      $reject_message->reject_response( );
      my $reject = $reject_message->dump_rtml();
      
      # do a find and replace, munging the response
      #$reject =~ s/</&lt;/g;
      
      # AUTHENTICATION
      # --------------
      
      # check that the eSTAR user id maps to a JACH project id
      unless (  eSTAR::Util::get_option("user.".$username) ) {
                
         # return the RTML document
         $log->warn("Warning: eSTAR UserID doesn't map to JAC ProjectID");
         $log->debug("Rejecting observation request...");
         $observation_object->obs_reply( $reject_message );
         my $status = freeze( $observation_object ); 
         if ( $status == ESTAR__ERROR ) {
            $log->warn( 
               "Warning: Problem re-serialising the \$observation_object");
         }  
         $log->debug("Returned RTML 'reject' message");
         return SOAP::Data->name('return', $reject)->type('bas64');
      
      }   
   
      $log->debug( "Extracting information from RTML message..." );
      
      # OBSERVING REQUESTS
      # ------------------
            
      # unique id
      # ---------
      my $id = $parsed->id();
      
      #$log->debug( "id          = " . $id );

      # IA information
      # --------------
      my $host = $parsed->host();
      my $port = $parsed->port();

      #$log->debug( "host        = " . $host );
      #$log->debug( "port        = " . $port );
       
      # target
      # ------
      my $target = $parsed->target();
      my $ra = $parsed->ra();
      my $dec = $parsed->dec();
      my $equinox = $parsed->equinox();
      my $exposure = $parsed->exposure();
      my $snr = $parsed->snr();
      my $flux = $parsed->flux();
      my $filter = $parsed->filter();

      #$log->debug( "target      = " . $target );
      #$log->debug( "ra          = " . $ra );
      #$log->debug( "dec         = " . $dec );
      #$log->debug( "equinox     = " . $equinox );
      #$log->debug( "exposure    = $exposure " );
      #$log->debug( "snr         = $snr" );
      #$log->debug( "flux        = $flux" );
      #$log->debug( "filter      = " . $filter );
       
      # scoring
      # -------
      my $score = $parsed->score();
      my $time = $parsed->time();

      #$log->debug( "score       = " . $score );
      #$log->debug( "time        = " . $time );
      
      # user info
      # ---------
      my $name = $parsed->name();
      my $user = $parsed->user();
      my $institution = $parsed->institution();
      my $email = $parsed->email();
      
      #$log->debug( "name        = " . $name );
      #$log->debug( "user        = " . $user );
      #$log->debug( "institution = " . $institution );
      #$log->debug( "email       = " . $email );

      # SCIENCE PROGRAMME
      # -----------------
      
      # create a science programme from the template XML files in
      # $ESTAR_DIR/xml using the $parsed->filter() to figure out 
      # which template to use. Current valid choices are "JHK" and 
      # "K" band.
      
      my $xml_file = File::Spec->catfile( $ENV{"ESTAR_DIR"}, 'xml',
                                          "uist_" . lc($filter) . ".xml" );
          
      $log->debug( "XML Template $xml_file" );
                                          
      # catch non-existant filter errors
      unless( -e $xml_file ) {
         $log->error( "Error: " .  eSTAR::Util::get_option( "dn.telescope") .
                            " does not have a $filter band filter.....");
         $observation_object->obs_reply( $reject_message ); 
         my $status = freeze( $observation_object ); 
         if ( $status == ESTAR__ERROR ) {
            $log->warn( 
               "Warning: Problem re-serialising the \$observation_object");
         }  
         $log->debug("Returned RTML 'reject' message");         
         return SOAP::Data->name('return', $reject)->type('base64');       
      }
      
      # create a new science program  
      my $sp;
      my $flag = undef;
      try {                                  
         $sp = new OMP::SciProg( FILE => $xml_file );
         unless ( $sp ) {
            throw eSTAR::Error::FatalError( "OMP::SciProg() returned undef...") 
         }
      } otherwise {
         my $error = shift;
         $log->error( 
           "Error: Unable to parse template science programme $xml_file");
         $log->error( "Error: $error" );
         $flag = 1;
      }; 
      if ( $flag ) { 
               
         # return the RTML document
         $log->debug("Rejecting observation request...");
         $observation_object->obs_reply( $reject_message );
         my $status = freeze( $observation_object ); 
         if ( $status == ESTAR__ERROR ) {
            $log->warn( 
               "Warning: Problem re-serialising the \$observation_object");
         }  
         $log->debug("Returned RTML 'reject' message");   
         return SOAP::Data->name('return', $reject)->type('base64');
      }
           
      # create a Astro::Coords object to use in MSB creation
      my $position = new Astro::Coords( ra  => $parsed->ra(),
                                        dec => $parsed->dec(),
                                        type => $parsed->equinox(),
                                        name => $parsed->target());
                                                                                
      my $scope =  eSTAR::Util::get_option("dn.telescope");
      $position->telescope( $scope );      
      
      # tag each msb in the science proposal with an expiry time, there
      # seems to be problems inside Astro::Coords that we don't know about
      # yet so lets buffer this with lots of error checking
      my $expire = $position->set_time();
      if ( $expire ) {
         $log->debug( "Expiry time is $expire");
      
         for my $msb ( $sp->msb ) {
            try {
               $msb->setDateMax( $expire );
               $log->debug( "Setting expiry time to $expire" );
            } otherwise {
               my $error = shift;
               $log->warn( "Warning: Unable to set expiry time..." );
               $log->warn( "Warning: $error ");
            }      
         }
      } else {
         $log->warn( 
          "Warning: Problem with Astro::Coords, unable to set expiry time..." );
      }
      
      # generate an MSB from our Astro::Coords object array
      my @messages = $sp->cloneMSBs( $position ); # array of Astro::Coords
      #foreach my $i ( 0 ... $#messages ) {
      #   $log->debug( $messages[$i] );
      #}
      for my $msb ( $sp->msb ) {
        $log->debug( "Cloned MSB with title '" . $msb->msbtitle() . "'");
        $log->debug( "Attaching eSTAR ID $id to MSB");
        $msb->remote_trigger( src => "ESTAR", id => $id );
      }    
 
      # Store the project ID in the XML
      my $project_id =  eSTAR::Util::get_option("user.".$username);
      $sp->projectID(  $project_id );
      $log->debug( "Setting ProjectID to $project_id " );
       
      # Store to DB [there is also a SOAP interface]
      $log->debug( 
      "Dispatching MSB to SpServer (user $username, project $project_id)" );
      my $password =  eSTAR::Util::get_option("project.".$project_id);
      try {
       
         # the ,1 forces overwrite of the existing science program
         # for the project id. Really need to fetch, append and
         # then resubmit (probably need a prune method to remove
         # exipired MSB's).
         $log->debug( "Trying now...." );
         OMP::SpServer->storeProgram( "$sp", $password, 1);
         #$log->warn(
         #   "Warning: OMP::SpServer->storeProgram() commented out");
         #$log->warn( "Warning: MSB will not be sumbitted to SpServer" );
      } otherwise {
         my $error = shift;
         $log->error( "Error: Unable to submit MSB to SpServer" );
         $log->error( "Error: $error");
         $flag = 1;
      };
      
      if ( $flag ) { 
               
         # return the RTML document
         $log->debug("Rejecting observation request...");
         $observation_object->obs_reply( $reject_message );
         my $status = freeze( $observation_object ); 
         if ( $status == ESTAR__ERROR ) {
            $log->warn( 
               "Warning: Problem re-serialising the \$observation_object");
         }  
         $log->debug("Returned RTML 'reject' message");   
         return SOAP::Data->name('return', $reject)->type('base64');
      }      
      $log->debug( "Sucessfully connected to SpServer" );
      $log->debug( "Submitted MSB..." );

      # GARBAGE COLLECTION THREAD
      # -------------------------
      
      # push the $id and $expire to the %running hash so that the garbage
      # collection thread can send out fail messages when the observation
      # has expired, also can retry sending observations that are tagged
      # as unset in need of retrying.
      {
         $log->debug( "Locking \%running in handle_rtml()..." );
         $log->debug( "Adding $id to \%running" );
         lock( %{ $run->get_hash() } );
         my $ref = &share({});
         $ref->{Expire} = "$time";
         $ref->{Status} = "running";
         ${ $run->get_hash() }{$id} = $ref;
         $log->debug( "Unlocking \%running...");
      } # implict unlock() here
      #use Data::Dumper; print Dumper ( %{ $run->get_hash() } );
                         
      # BUILD MESSAGE
      # -------------
      
      # build the score response document
      my $confirm_message = new eSTAR::RTML::Build( 
             Port        => $parsed->port(),
             Host        => $parsed->host(),
             ID          => $parsed->id(),
             User        => $parsed->user(),
             Name        => $parsed->name(),
             Institution => $parsed->institution(),
             Email       => $parsed->email() );

      if ( defined $parsed->exposure() ) {
         
         # build a score request
         $confirm_message->confirm_response(
             Target   => $parsed->target(),
             RA       => $parsed->ra(),
             Dec      => $parsed->dec(),
             Exposure => $parsed->exposure(),
             Score    => $parsed->score(),
             Time     => $parsed->time()  );
             
      } elsif ( defined $parsed->snr() && 
                defined $parsed->flux() ) {

         # build a score request
         $confirm_message->confirm_response(
             Target => $parsed->target(),
             RA     => $parsed->ra(),
             Dec    => $parsed->dec(),
             Snr    => $parsed->snr(),
             Flux   => $parsed->flux(),
             Score  => $parsed->score(),
             Time   => $parsed->time() );        
      }
      
      # drop the reply into the observation object
      $observation_object->obs_reply( $confirm_message );
      my $status = freeze( $observation_object ); 
      if ( $status == ESTAR__ERROR ) {
         $log->warn( 
            "Warning: Problem re-serialising the \$observation_object");
      }  

      # dump rtml to scalar
      my $confirm_response = $confirm_message->dump_rtml();
      #use Data::Dumper; print Dumper( $confirm_message );
      
      # do a find and replace, munging the response, shouldn't need to do it?
      #$confirm_response =~ s/</&lt;/g;
                
      # return the RTML document
      $log->debug("Returned RTML 'confirm' message");
      return SOAP::Data->name('return', $confirm_response )->type('base64');
      
   } else {
   
      # beats me what it is...?
      $log->debug("Returned 'UNKNOWN RTML TYPE' message");
      return SOAP::Data->name('return', "UNKOWN RTML TYPE")->type('xsd:string');
   }
   
   
}
  

# H A N D L E   D A T A ------------------------------------------------------
  
sub handle_data {
   my $self = shift;
   my %data = @_;

   $log->debug("Called handle_data() from \$tid = ".threads->tid());

   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.");
   }


   # check we have everything we need
   unless (   defined $data{ID} && defined $data{Catalog} 
           && defined $data{FITS} && defined $data{AlertType} ){
      $log->error( "Error: Undefined hash values recieved from ORAC-DR");
      $log->debug( "Raised an Exception with ORAC-DR" );
      die SOAP::Fault
            ->faultcode("Client.DataError")
            ->faultstring("Client Error: Undefined hash values")      
   } else {
      $log->debug( "The \%data hash seems to be intact..." );
   }
   
   $log->debug( "ID = $data{ID} ($data{AlertType})" );

   # THAW OBSERVATION
   # ----------------
   
   # see if we can deserialise against this id
   my $observation_object = thaw( $data{ID} );   
   #use Data::Dumper; print Dumper( $observation_object );
   
   # if not throw an exception 
   unless ( defined $observation_object ) {
   
      $log->error( "Error: Unable to deserialise ID = $data{ID}" );
      $log->error( 
        "Error: Data associated with ID may already have been returned" );
      $log->debug( "Raised an Exception with ORAC-DR" );
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: Unkown or already processed ID $data{ID}")
   }

   # In theory $data{ID} eq $observation_object->id(), but for testing
   # purposes we symlink the "fake" ID returned by the pipeline to the
   # currently outstanding ID for the user_agent. This is a kludge which
   # the following line of code fixes for the rest of the routine.
   $log->warn("Warning: Switching ID to ".$observation_object->id() );
   $data{ID} = $observation_object->id();
   
   # grab the Observation Request Document from the observation_object
   # since we have a mirror image or a UA's observation_object the
   # obs_request() function will return an eSTAR::RTML::Parse object.
   my $obs_request = $observation_object->obs_request();
   
   # IA information
   # --------------
   my $host = $obs_request->host();
   my $port = $obs_request->port();

   #$log->debug( "host        = " . $host );
   #$log->debug( "port        = " . $port );
    
   # target
   # ------
   my $target = $obs_request->target();
   my $ra = $obs_request->ra();
   my $dec = $obs_request->dec();
   my $equinox = $obs_request->equinox();
   my $exposure = $obs_request->exposure();
   my $snr = $obs_request->snr();
   my $flux = $obs_request->flux();
   my $filter = $obs_request->filter();

   #$log->debug( "target      = " . $target );
   #$log->debug( "ra          = " . $ra );
   #$log->debug( "dec         = " . $dec );
   #$log->debug( "equinox     = " . $equinox );
   #$log->debug( "exposure    = $exposure " );
   #$log->debug( "snr         = $snr" );
   #$log->debug( "flux        = $flux" );
   #$log->debug( "filter      = " . $filter );
    
   # scoring
   # -------
   my $score = $obs_request->score();
   my $time = $obs_request->time();

   #$log->debug( "score       = " . $score );
   #$log->debug( "time        = " . $time );
   
   # user info
   # ---------
   my $name = $obs_request->name();
   my $user = $obs_request->user();
   my $institution = $obs_request->institution();
   my $email = $obs_request->email();
   
   #$log->debug( "name        = " . $name );
   #$log->debug( "user        = " . $user );
   #$log->debug( "institution = " . $institution );
   #$log->debug( "email       = " . $email );
   
   # PROCESS OBSERVATION
   # -------------------
   
   # Grab Catalog
   # ------------
   $log->debug( "Requesting catalogue: $data{Catalog}");
   my $catalog_request = new HTTP::Request('GET', $data{Catalog});
   my $catalog_reply = $ua->get_ua()->request($catalog_request);   

   # check for valid reply
   if ( ${$catalog_reply}{"_rc"} eq 200 ) {
     if ( ${${$catalog_reply}{"_headers"}}{"content-type"} eq "text/plain" ) {               
        $log->debug("Recieved Catalogue (200 OK)");       
     } else {
   
        # unknown document, not of type octet-stream
        $log->warn( "Warning: Unknown document type recieved...");
        $log->warn( "Warning: Unknown type is " .
                          ${${$catalog_reply}{"_headers"}}{"content-type"});
     }
   
   } else { 
   
     # the network conenction failed      
     $log->error( "Error: (${$catalog_reply}{_rc}): " . 
                        "Failed to establish network connection");
     $log->error( "Error:" . ${$catalog_reply}{_msg} );

   } 
   
   # drop the returned Cluster catalogue into a scalar   
   my $catalog = ${$catalog_reply}{_content};
    
   # Grab FITS File
   # --------------
   $log->debug( "FITS Image: $data{FITS}");  

   # grab a URL for the associated FITS image
   my $image_url = $data{FITS};
      
   # munge ORAC-DR output since we're getting an NDF rather than a FITS file
   #$image_url = $image_url . ".sdf";
   
   # grab the file name
   $image_url =~ m/(\w+\W\w+)$/;
   my $data = $1;
   my $fits = File::Spec->catfile(eSTAR::Util::get_option("jach.data"), $data);
  
   # retrieve the file
   $log->debug( "Requesting FITS file...");
   my $fits_request = new HTTP::Request('GET', $image_url );
   my $fits_reply = $ua->get_ua()->request($fits_request);   
 
   # check for valid reply
   if ( ${$fits_reply}{"_rc"} eq 200 ) {
     #if ( ${${$fits_reply}{"_headers"}}{"content-type"} 
     #     eq "application/octet-stream" ) {               
        $log->debug("Recieved image file (200 OK)");
                             
        # Open output file
        $fits =~ s/\W\w+$/.fit/;
        unless ( open ( IMAGE, ">$fits" )) {
           $log->error("Error: Cannot open $fits for writing");
        } else {  

           # Write to output file
           $log->debug("Saving image to $fits");
           $observation_object->fits_file( $fits );
           my $length = length(${$fits_reply}{"_content"});
           syswrite( IMAGE, ${$fits_reply}{"_content"}, $length );
           close(IMAGE);
        }
        
     #} else {
     #  
     #   # unknown document, not of type octet-stream
     #   $log->warn(
     #       "Warning: Unknown document type recieved...");
     #   $log->warn( "Warning: Unknown type is " .
     #       ${${$fits_reply}{"_headers"}}{"content-type"});
     #   
     #}
   
   } else { 
   
     # the network conenction failed      
     $log->error(
       "Error: (${$fits_reply}{_rc}): Failed to establish network connection");
     $log->error( "Error: " . ${$fits_reply}{_msg} );

   }
                       
   # Grab Headers from FITS File
   # ---------------------------
     
   # parse cards into Header object
   $log->debug("Parsing FITS Headers...");
   my $header = new Astro::FITS::Header::CFITSIO( File => $fits );      
   
   my $fits_headers;
   
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
   
   # temporary debug munging of FITS headers
   my $fits_headers = "$header";
   #$fits_headers =~ s/</&lt;/g;
   #$fits_headers =~ s/>/&gt;/g;
   #$fits_headers =~ s/&/&amp;/g;
    
   # Build Message
   # -------------
 
   # practically identical for 'update' and 'observation' messages  
   my $method;
   if ( $data{AlertType} eq 'update' ) {
      $method = "update_response";
   } elsif ( $data{AlertType} eq 'observation' ) {
      $method = "complete_response";
   } else {
      $method = "failure_response";
   }        

   my $message = new eSTAR::RTML::Build( 
             Port        => $port,
             Host        => $host,
             ID          => $data{ID},
             User        => $user,
             Name        => $name,
             Institution => $institution,
             Email       => $email);
   
   if ( defined $snr && defined $flux ) {       
      $message->$method(
                Target    => $target,
                RA        => $ra,
                Dec       => $dec,
                Score     => $score,
                Time      => $time,
                Snr       => $snr,
                Flux      => $flux,
                Filter    => $filter,
                Catalogue => $catalog,
                Headers   => $fits_headers,
                ImageURI  => $image_url);
                 
   } elsif ( defined $exposure ) {                      
      $message->$method(
                Target   => $target,
                RA       => $ra,
                Dec      => $dec,
                Score    => $score,
                Time     => $time,
                Exposure => $exposure,
                Filter   => $filter,
                Catalogue => $catalog,
                Headers   => $fits_headers,
                ImageURI  => $image_url )   
   }
   
   # Send Message to user_agent
   # --------------------------
   $method = $data{AlertType};
   $observation_object->$method( $message );
   my $reply_rtml = $message->dump_rtml();
   
   # end point
   my $endpoint = "http://" . $host . ":" . $port;
   my $uri = new URI($endpoint);
   
   # create a user/passwd cookie
   my $cookie = make_cookie( "agent", "InterProcessCommunication" );
  
   my $cookie_jar = HTTP::Cookies->new();
   $cookie_jar->set_cookie( 0, user => $cookie, '/', 
                           $uri->host(), $uri->port());

   # create SOAP connection
   my $soap = new SOAP::Lite();
  
   $soap->uri('urn:/user_agent'); 
   $soap->proxy($endpoint, cookie_jar => $cookie_jar);
   
   # report
   $log->print("Connecting to " . $host . "..." );
   
   # fudge RTML document?
   #$reply_rtml =~ s/</&lt;/g;
   #$reply_rtml =~ s/>/&gt;/g;
   
   # grab result 
   my $result;
   eval { $result = $soap->handle_rtml( 
            SOAP::Data->name('reply', $reply_rtml )->type('base64')); };
 
   my $warn_flag;
   if ( defined $result->fault() ) {
      $warn_flag = 1;
   }
      
   # if we have problems
   if ( $@ || $warn_flag ) {
      $log->warn("Warning: Problem connecting to " . $host ); 
          
      if( defined $result && $result->fault() ) {
        $log->error("Fault Code   : " . $result->faultcode() );
        $log->error("Fault String : " . $result->faultstring() );
      } 
      
      # reserialise the observation object
      $log->warn("Warning: Re-serialising the \$observation_object");
      $observation_object->status( 'retry' );
      my $status = freeze( $observation_object ); 
      if ( $status == ESTAR__ERROR ) {
         $log->warn( 
            "Warning: Problem re-serialising the \$observation_object");
      }
            
      # GARBAGE COLLECTION THREAD
      # -------------------------
      
      # push the $id and $expire to the %running hash so that the garbage
      # collection thread can send out fail messages when the observation
      # has expired, also can retry sending observations that are tagged
      # as unset in need of retrying.
      {
         $log->warn( "Warning: Locking \%running in handle_data()..." );
         $log->warn( "Warning: Flagging $data{ID} for 'retry'...");
         lock( %{ $run->get_hash() } ); 
         
         my $ref = &share({});
         $ref->{Expire} = "$time";
         $ref->{Status} = "retry";
         ${ $run->get_hash() }{$data{ID}} = $ref; 
         $log->warn( "Warning: Unlocking \%running...");
      } # implict unlock() here
      #use Data::Dumper; print Dumper ( %{ $run->get_hash() } );
   
      $log->debug("Returned 'RETRY' message to ORAC-DR");
      return SOAP::Data->name('return', "ACK RETRY" )->type('xsd:string');
      
   }
   
   # Check for errors
   unless ($result->fault() ) {
      $log->debug("Transport Status: " . $soap->transport()->status() );

      # DELETE OBJECT IF MESSAGE == 'observation'
      # -----------------------------------------
      # delete the observation object from disk as we've completed
      # the science program it represents
      if ( $data{AlertType} eq 'observation' ) {

         # delete the serialised observation_object
         my $status = melt( $observation_object );        
         if ( $status == ESTAR__ERROR ) {
            $log->warn( 
               "Warning: Problem deleting the \$observation_object");
         }
                  
         # lock the %main::running hash and look through the $id's for expired
         # observations and then remove them from the hash 
         {
            $log->debug( "Locking \%running in handle_data()..." );
            lock( %{ $run->get_hash() } );
            $log->debug( "Removing " . $observation_object->id(). 
                               " from \%running..." );
            delete ${ $run->get_hash() }{ $observation_object->id() };
            $log->debug( "Unlocking \%running...");
         } # implict unlock() here
         #use Data::Dumper; print Dumper ( %{ $run->get_hash() } );         

      }
            
   } else {
      
      # Good stuff has happened...
      my $reply = $result->result();
      $log->debug( "Got an '" . $reply . "' message from the user_agent");
   }
         
   # Send Message to ORAC-DR
   # -----------------------
      
   $log->debug("Returned 'ACK' message to ORAC-DR");
   return SOAP::Data->name('return', "ACK OK" )->type('xsd:string');

}                           



1;                                
                  
                  
                  
