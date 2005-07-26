package eSTAR::RAPTOR::Handler;

# Basic handler class for SOAP requests for the Embedded Agent. It also
# acts as a container class for eSTAR::SOAP::User class which handles
# authentication.

use lib $ENV{"ESTAR_PERL5LIB"};     

use strict;
use subs qw( new set_user ping handle_rtml  );

#
# General modules
#
#use SOAP::Lite +trace =>   
# [transport => sub { print (ref $_[0] eq 'CODE' ? &{$_[0]} : $_[0]) }]; 
use SOAP::Lite;
use MIME::Entity;
use Digest::MD5 'md5_hex';
use Fcntl qw(:DEFAULT :flock);
use Time::localtime;
use Sys::Hostname;
use Net::Domain qw(hostname hostdomain);
use Config::Simple;
use Config::User;
#use Video::Capture::V4l;
#use Video::RTjpeg;
use Data::Dumper;

# 
# eSTAR modules
#
use eSTAR::SOAP::User;
use eSTAR::Logging;
use eSTAR::LDAP::Search;
use eSTAR::Constants qw/:all/;
use eSTAR::Util;
use eSTAR::Mail;
use eSTAR::Config;
use eSTAR::RTML;
use eSTAR::RTML::Parse;

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
  
  $log->thread2( "Handler", 
    "Created new eSTAR::RAPTOR::Handler object...");
        
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
# H A N D L E R S 
# ==========================================================================

# test function
sub ping {
   my $self = shift;

   $log->debug("Called ping()");
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data"
   }
     
   $log->debug("Returned ACK message");
   return SOAP::Data->name('return', 'ACK')->type('xsd:string');
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
  
   # SEND TO ERS
   # -----------
   
   # pass modified RTML onto the RAPTOR server
   
   $log->print("Opening socket connection to RAPTOR server..." ) ;
  
   my $sock = new IO::Socket::INET( 
                    PeerAddr => $config->get_option( "raptor.host" ),
                    PeerPort => $config->get_option( "raptor.port" ),
                    Proto    => "tcp",
                    Timeout => $config->get_option( "connection.timeout" ) );
   my ( $response );                        
   unless ( $sock ) {
      
      # we have an error
      my $error = "$!";
      chomp($error);
      $log->error( "Error: $error") ;
      $log->error("Returned ERROR message");
      return SOAP::Data->name('return', "ERROR: $error" )->type('xsd:string');
   
   } else { 
 
      $log->print("Sending RTML to RAPTOR\n$rtml");
 
      # work out message length
      my $header = pack( "N", 7 );
      my $bytes = pack( "N", length($rtml) );
       
      # send message                                   
      $log->debug( "Sending " . length($rtml) . " bytes to " . 
                         $config->get_option( "raptor.host" ));
      print $sock $header;
      print $sock $bytes;
      $sock->flush();
      print $sock $rtml;
      $sock->flush();  
          
      # grab response
      $log->debug( "Waiting for response from RAPTOR... " );
      
      my ( $reply_bytes, $reply_length );
      read $sock, $reply_bytes, 4;
      $reply_length = unpack( "N", $reply_bytes );
      read $sock, $response, $reply_length; 

      $log->debug( "Read " . $reply_length . " bytes to " . 
                         $config->get_option( "raptor.host" ));      
      close($sock);
      
      #$log->debug( $response );
  
   }
   
   
   # GRAB MESSAGE
   # ------------
   
   # modifiy the response to include the correct IA information
   $log->debug("Verifying the <IntelligentAgent> tag formatting...");   

   my ( $host, $port, $ident ) = eSTAR::Util::fudge_message( $response );  

   # make sure we have quote marks around the host and port numbers
   my $nonvalid = "<IntelligentAgent host=$host port=$port>";
   if ( $response =~ $nonvalid ) {
      $log->debug( "Performing kludge to work round invalid XML" );
      #$log->warn( "Warning: Invalid string in XML, replacing with valid..." );
      #$log->warn( "Warning: $nonvalid" );
      my $validstring = 
        "<IntelligentAgent host=" . '"' . $host . '"' . 
                         " port=" . '"' . $port . '"' . ">";
      $response =~ s/$nonvalid/$validstring/;
   }    
      
   # SEND TO USER_AGENT
   # ------------------
   
   # do a find and replace, munging the response, shouldn't need to do it?
   $log->debug( "Returned RTML message\n$response");
   $response =~ s/</&lt;/g;
   
   # return an RTML response to the user_agent

   $log->debug("Returned RTML response");
   return SOAP::Data->name('return', $response )->type('xsd:string');

} 
                             
1;                                
                  
                  
                  
