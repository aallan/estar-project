package eSTAR::Miner::Handler;

# Basic handler class for SOAP requests for the Data Miner. It also
# acts as a container class for eSTAR::SOAP::User class which handles
# authentication.

use lib $ENV{"ESTAR_PERL5LIB"};     

use strict;
use subs qw( new set_user ping echo get_option set_option handle_objects );

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
use Net::Domain qw(hostname hostdomain);
use Config::Simple;
use Config::User;
use Data::Dumper;
use Fcntl qw(:DEFAULT :flock);
use Compress::Zlib;

# 
# eSTAR modules
#
use eSTAR::SOAP::User;
use eSTAR::Logging;
use eSTAR::Constants qw/:all/;
use eSTAR::Util qw//;
use eSTAR::Mail;
use eSTAR::Config;

# 
# Astro modules
#
use Astro::Catalog;
use Astro::Catalog::Query::SIMBAD;
use Astro::SIMBAD::Query;

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
    "Created new eSTAR::Miner::Handler object (\$tid = ".threads->tid().")");
        
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
# C A L L B A C K S 
# ==========================================================================


sub return_datamining {
  croak ( "eSTAR::Miner:Handler::return_datamining() called without arguements" )
     unless defined @_;

  my $catalog = shift;   
     
  my $thread_name = "return_datamining()";
  $log->thread($thread_name, "eSTAR::Miner::Handler::return_datamining()..." );
  $log->thread($thread_name, "Starting client (\$tid = ".threads->tid().")");  
     
  $log->debug( "Calling eSTAR::Util::chill( \$catalog )");
  $catalog->reset_list(); # otherwise we breake the serialisation
  my $chilled = eSTAR::Util::chill( $catalog );
  
  $log->debug( "Compressing \$catalog");
  my $compressed = Compress::Zlib::memGzip( $chilled );
  
  $log->thread( $thread_name, "Connecting to Data Mining Service..." );
  
  my $endpoint = "http://" . $config->get_option( "db.host") . ":" .
              $config->get_option( "db.port");
  my $uri = new URI($endpoint);
  $log->debug("Web service endpoint $endpoint" );
  
  # create a user/passwd cookie
  $log->debug("Creating cookie..." );
  my $cookie = eSTAR::Util::make_cookie( "agent", "InterProcessCommunication" );
  
  $log->debug("Dropping cookie in jar..." );
  my $cookie_jar = HTTP::Cookies->new();
  $cookie_jar->set_cookie(0, user => $cookie, '/', $uri->host(), $uri->port());

  # create SOAP connection
  my $soap = new SOAP::Lite();
  
  my $urn = "urn:/" . $config->get_option( "db.urn" );
  $log->debug( "URN of endpoint service is $urn");
  
  $soap->uri($urn); 
  $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
  #use Data::Dumper;
  #print Dumper( $chilled[0] );  
    
  # report
  $log->thread( $thread_name, "Calling handle_objects() in remote service");
    
  # grab result 
  my $result;
  eval { $result = $soap->handle_objects(  
                             SOAP::Data->type(base64 => $compressed ) ); };
  if ( $@ ) {
    $log->warn( "Warning: Could not connect to $endpoint");
    $log->warn( "Warning: $@" );
      
  }  
  
  $log->debug( "Transport status: " . $soap->transport()->status() );
  unless ( defined $result ) {
    $log->error("Error: No result object is present..." );
    $log->error("Error: Returning ESTAR__FAULT to main thread" );
    return ESTAR__FAULT;
  }
    
  unless ($result->fault() ) {
    if ( $result->result() eq "OK" ) {
       $log->debug( "Recieved an ACK message from WFCAM DB service");
    } else {
       $log->warn( "Warning: Recieved status ".$result->result() .
                   " from WFCAM DB service");
    }   
  } else {
    $log->warn("Warning: recieved fault code (" . $result->faultcode() .")" );
    $log->warn("Warning: " . $result->faultstring() );
    $log->thread( $thread_name, "Returning ESTAR__FAULT to main thread");
    return ESTAR__FAULT;
  }  

  $log->thread( $thread_name, "Returning ESTAR__OK to main thread");
  return ESTAR__OK;       
     
}


# ==========================================================================
# T E S T  H A N D L E R S 
# ==========================================================================

# test function
sub ping {
   my $self = shift;

   $log->debug("Called ping() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data.");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.")
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
      $log->warn("SOAP Request: The object is missing user data.");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.")
   }
     
   $log->debug("Returned ECHO message");
   return SOAP::Data->name('return', "ECHO @args")->type('xsd:string');
} 


# ==========================================================================
# O P T I O N S  H A N D L E R S 
# ==========================================================================

# options handling
sub get_option {
   my $self = shift;

   $log->debug("Called get_option() from \$tid = ".threads->tid());
   $config->reread();
   
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
   $config->reread();
   
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


   $log->debug("Setting $option = $value");
   my $status = $config->set_option( $option, $value );
   if ( $status == ESTAR__ERROR ) {
      $log->error("Error: Unable to set value in configuration file" );
      die SOAP::Fault
      ->faultcode("Client.FileError")
      ->faultstring("Client Error: Unable to set value in configuration file");          
   }   
   
   $log->debug("Writing out options file...");
   my $status = $config->write_option();
   if ( $status == ESTAR__ERROR ) {
      $log->error("Error: Unable to write out to configuration file" );
      die SOAP::Fault
      ->faultcode("Client.FileError")
      ->faultstring("Client Error: Unable to write out to configuration file");          
   }

   $log->debug("Returned STATUS message" );
   return SOAP::Data->name('return', ESTAR__OK )->type('xsd:integer');

} 

# ==========================================================================
# D A T A  H A N D L E R S 
# ==========================================================================

# test function
sub handle_objects {
   my $self = shift;

   $log->debug("Called handle_objects() from \$tid = ".threads->tid());
   $config->reread();
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data.");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.")
   }
   
   # READ ARGUEMENTS
   # ---------------
   # pulls the host & port and serialised catalogue from the wire. The host 
   # & port are those that the data mining process will return the results. 
   #
   # It will acknowledge this request with a simple ACK message. We're doing 
   # an async call here...
   my $host = shift;
   my $port = shift;
   my $string = shift;
   
   # RESPONSE THREAD
   # ---------------
   # we have a seperate thread that goes off and data mines information
   # pertaining to the list of objects we have been given. This is so that
   # an ACK response can be given to teh client immediately.
   my $response_client = sub {
    
      my $thread_name = "Mining Thread"; 
      $log->thread($thread_name, 
        "Called response_client() from \$tid = " . threads->tid());
      
      $log->debug( "Connection from $host:$port");
        
      # Generate Catalogue
      # ------------------
      $log->debug( "Uncompressing \$string...");
      my $catalog = Compress::Zlib::memGunzip( $string ); 
        
      $log->debug( "Calling eSTAR::Util::reheat( \$var_objects )");
      my $var_objects = eSTAR::Util::reheat( $catalog );
   
      # sanity check the passed values
      $log->debug("Doing a sanity check on the integrity of the catalogues");
      
      unless ( UNIVERSAL::isa( $var_objects, "Astro::Catalog" ) ) {
         $log->error(
	   "Error: Failed sanity check \$var_objects is not an Astro::Catalog");
         $log->error( Dumper($var_objects) );
         return undef;
      }
      my $counter = 0;
      foreach my $star ( $var_objects->allstars() ) {
         $log->warn("Warning: Problem deserialising star $counter from ".
          " \$var_objects") unless UNIVERSAL::isa($star, "Astro::Catalog::Star");
         $counter++;
      }  
   
      $log->debug("List of " . $var_objects->sizeof() . 
                  " objects read from SOAP message");
    	      	
      # Check each Star
      # ---------------
      my $radius = $config->get_option( "simbad.error" );
      $log->debug("Searching SIMBAD at at $radius arcsec radius from targets...");
      
      my $catalog = new Astro::Catalog();
      my $sizeof = $var_objects->sizeof() - 1;
      foreach my $i ( 0 ... $sizeof ) {
   
         $log->debug( "Popping star " . ($i+1) . " from catalogue...");
         my $star = $var_objects->starbyindex( $i );
         my $ra = $star->ra();
         my $dec = $star->dec();

         $log->debug( "Building SIMBAD query object...");
	 my $simbad = new Astro::Catalog::Query::SIMBAD( RA     => $ra,
                                                         Dec    => $dec,
                                                         Radius => $radius );         
	 if( $i == 0 ) {
	    $log->debug( 
	        "Making connection " . ($i+1) . " of " . $var_objects->sizeof() );
	 } else {
	    $log->debug( 
	       "Making connection " . ($i+1) . " of " . $var_objects->sizeof()); 
	 }
         my $result = $simbad->querydb();
	 if( $i == $sizeof ) {
            $log->debug( "Made all " . ($i+1) . " connections to SIMABD..." );
         } else {
	    $log->debug( "Retrieved result from SIMBAD..." );
	 }
	 
	 # loop through the returned catalogue and push all stars into the 
	 # result object to return to the WFCAM    
	  
	 my $num_of_stars = $result->sizeof();
	 if( $num_of_stars >= 1 ) {   
	 
	    # we have some records
	    $log->debug( "Pushing $num_of_stars SIMBAD results into catalogue" );
	    my @stars = $result->allstars();
	    $catalog->pushstar( @stars );
  
	 } else {
	   $log->debug( "No matching records");
	 } 
      }
      $log->thread($thread_name, "Completed data mining task");
      
      $log->print( "Creating thread to return data mineing results..." );
      my $dispatch = threads->create( \&return_datamining, $catalog );
  				  
      unless ( defined $dispatch ) {
         $log->error( "Error: Could not spawn a thread to talk to the DB" );
         $log->error( "Error: Returning ESTAR__FATAL to main loop..." );
         return ESTAR__FATAL;  
      }				  
      $log->debug( "Detaching thread...");
      $dispatch->detach();      
      
      return ESTAR__OK;
   };
   
   # SPAWN THREADED PROCESS
   # ----------------------
   # spawn a sub-thread to do our data mining
   $log->thread2("Handler Thread", "Detaching data mining process...");
   my $response_thread = threads->create( $response_client );
   $response_thread->detach();
    
   # RETURN ACK
   # ----------
   # return a simple ACK message to the client for now, we have the context
   # we'll be contacting them with the data mined information later. 
   $log->thread2("Handler Thread", "Returned ACK message");
   return SOAP::Data->name('return', "ACK" )->type('xsd:string');   
}   

1;                                
                  
                  
                  
                  
                  
                  
