package eSTAR::Miner::Handler;

# Basic handler class for SOAP requests for the Data Miner. It also
# acts as a container class for eSTAR::SOAP::User class which handles
# authentication.

use lib $ENV{"ESTAR3_PERL5LIB"};     

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
use Fcntl ':flock';

# 
# eSTAR modules
#
use eSTAR::SOAP::User;
use eSTAR::Logging;
use eSTAR::Constants qw/:all/;
use eSTAR::Util qw//;

# 
# Astro modules
#
use Astro::Catalog;
use Astro::Catalog::Query::SIMBAD;

use Astro::SIMBAD::Query;

my $log;

# ==========================================================================
# U S E R   A U T H E N T I C A T I O N
# ==========================================================================

sub new {
  my ( $class, $user, $passwd ) = @_;
  
  my $self = bless {}, $class;
  $log = eSTAR::Logging::get_reference();
  
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
sub handle_objects {
   my $self = shift;

   $log->debug("Called handle_objects() from \$tid = ".threads->tid());
   
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
   # arguements, pulls the context, host & port and wrapped XML document
   # from the wire. The host & port are those that the data mining process
   # will return the results. It will acknowledge this request with a simple
   # ACK message. We're doing an async call here...
   my $context = shift;
   my $host = shift;
   my $port = shift;
   my $xml = shift;
   
   # RESPONSE THREAD
   # ---------------
   # we have a seperate thread that goes off and data mines information
   # pertaining to the list of objects we have been given. This is so that
   # an ACK response can be given to teh client immediately.
   my $response_client = sub {
    
      my $thread_name = "Mining Thread"; 
      $log->thread($thread_name, 
        "Called response_client() from \$tid = " . threads->tid());
      
      # generate a unique ID
      #my $id = eSTAR::Util::make_id();

      $log->debug( "Connection from $host:$port");
      $log->debug( "Connection has context '" . $context . "'" );
        
      # Generate Catalogue
      # ------------------
   
      my $catalog = new Astro::Catalog( Format => 'VOTable', Data => $xml );
      $log->debug("List of " . $catalog->sizeof() . 
                  " objects read from SOAP message");
    	
      use Data::Dumper; print Dumper( $catalog );
      	
      # Check each Star
      # ---------------
      my $error = eSTAR::Util::get_option( "simbad.error" );
      $log->debug("Searching SIMBAD at $error arcsec...");
      foreach my $i ( 0 ... $catalog->sizeof()-1 ) {
   
         my $star = $catalog->starbyindex( $i );
         my $ra = $star->ra();
         my $dec = $star->dec();
         #$log->debug( "Star $i - RA $ra, Dec $dec");
      
         my $simbad = new Astro::SIMBAD::Query( 
	           RA => $ra, Dec => $dec, Error => $error,  Unit => "arcsec" );
         
	 if( $i == 0 ) {
	    $log->debug_ncr( 
	        "Making connection " . ($i+1) . " of " . $catalog->sizeof() );
	 } else {
	    $log->debug_overtype_ncr( 
	       "Making connection " . ($i+1) . " of " . $catalog->sizeof()); 
	 }
	 
	 if( $i == $catalog->sizeof()-1 ) {
	    $log->debug_overtype_ncr(""); 
	    $log->debug( "\nMade all " . ($i+1) . " connections to SIMABD..." );
         }
	 	 
	 my $result = $simbad->querydb();	
	 
         #use Data::Dumper; print Dumper( $result );
	 if( $result->objects() >= 1  ) {
	   my @objects = $result->objects();
	   $log->print( "\nStar " . $star->id() );
	   $log->print( "  RA $ra, Dec $dec");
	   
	   my $number = scalar( @objects );
	   $log->debug("  SIMBAD returned ". $number ." matching records");
	   foreach my $j ( 0 ... $#objects ) {
	      $log->print( "  Match ". ($j+1) );
	      $log->print( "  " . $objects[$j]->name() );
	      $log->print( "  RA " . $objects[$j]->ra() . 
	                   ", Dec " . $objects[$j]->dec() );
	      $log->debug( "  Object Class : " . $objects[$j]->long() );
	      $log->debug( "  Spectral Type: " . $objects[$j]->spec() );	       
	   }   
	 } 
      }
      $log->thread($thread_name, "Completed data mining task");
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
   $log->thread2("Handler Thread",
                 "Returned ACK message for context '" . $context . "'");
   return SOAP::Data->name('return', "ACK $context" )->type('xsd:string');   
}   

1;                                
                  
                  
                  
                  
                  
                  
