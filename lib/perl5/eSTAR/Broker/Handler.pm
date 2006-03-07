package eSTAR::Broker::Handler;

# Basic handler class for SOAP requests for the User Agent. It also
# acts as a container class for eSTAR::SOAP::User class which handles
# authentication.

use lib $ENV{"ESTAR_PERL5LIB"};     

use strict;
use subs qw( new set_user ping echo handle_voevent get_option
             set_option kill);

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
use eSTAR::Constants qw/:all/;
use eSTAR::Util;
use eSTAR::Mail;
use eSTAR::Config;
use eSTAR::Broker::Util;
use eSTAR::Broker::Running;

#
# Astro modules
#
use Astro::VO::VOEvent;

my ($log, $process, $ua, $config, $running);

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
  $running = eSTAR::Broker::Running::get_reference();
  
  if( $user and $passwd ) {
    return undef unless $self->set_user( user => $user, password => $passwd );
  }
  
  $log->thread2( "Handler Thread", 
  "Created new eSTAR::Broker::SOAP::Handler object (\$tid = ".threads->tid().")");
        
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

# a kludge
sub kill {
   my $self = shift;

   $log->debug("Called kill() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data"
   }
   
   $log->print("Spawning thread to kill agent...");
   my $kill_thread = threads->create( sub { 
                                       sleep 5; 
                                       main::kill_agent( ESTAR__FATAL ); } );
   $kill_thread->detach();
     
   $log->debug("Returned ACK message");
   return SOAP::Data->name('return', 'ACK')->type('xsd:string');
}


# handle an incoming VOEvent documents
sub handle_voevent {
   my $self = shift;
   my $voevent = shift;

   #print Dumper( $rtml );
   $log->debug("Called handle_voevent() from \$tid = ".threads->tid());
   $config->reread();
   
   # check we have a valid user object            
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data";
   }
   
   # Message Validation
   # ------------------
   
   # validate the incoming message
   my $voevent_message;
   eval { $voevent_message = new Astro::VO::VOEvent( XML => $voevent ) };
   
   if ( $@ ) {
       my $error = "$@";
       
       $log->error( "Error: Problem parsing the VOEvent document" );
       $log->error( "VOEvent Document:\n$voevent" );
       $log->error( "Returned SOAP FAULT message" );
       die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: $error\nVOEvent Document:\n$voevent");
   }      
   
   
   
   $log->debug( "Returning 'ACK' message" );
   return SOAP::Data->name('return', 'ACK')->type('xsd:string');
}

              
1;                                
                  
                  
                  
                  
                  
                  
