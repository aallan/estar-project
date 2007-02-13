package eSTAR::NA::Handler;

# Basic handler class for SOAP requests for the Embedded Agent. It also
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
#use eSTAR::RTML;
#use eSTAR::RTML::Parse;
use XML::Document::RTML;

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
    "Created new eSTAR::NA::Handler object (\$tid = ".threads->tid().")");
        
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
     
   # LOOKUP STATE FILE
   # -----------------
   my $file = 
      File::Spec->catfile( Config::User->Home(), '.estar', 
                           $process->get_process(), 'lookup.dat' );
     
   my $LOOK = new Config::Simple( syntax   => 'ini',
                                  mode     => O_RDWR|O_CREAT );

   unless ( defined $LOOK ) {
      # can't read/write to state file, scream and shout!
      my $error = "FatalError: " . $Config::Simple::errstr;
      $log->error(chomp($error));
      return SOAP::Data->name('return', chomp($error))->type('xsd:string');      
   }
   
   # if it exists read the current contents in...
   if ( open ( CONFIG, "$file" ) ) {
      close( CONFIG );
      $LOOK->read( $file );
   }  
   
   #use Data::Dumper; print Dumper( $LOOK ); 
   
   # GRAB MESSAGE
   # ------------
   
   my ( $host, $port, $ident ) = eSTAR::Util::fudge_message( $rtml );  
        
   # stuff it into global lookup hash
   my $line = "<IntelligentAgent host=\"$host\" port=\"$port\">";
   
   #print "LINE: $line";
   $LOOK->param( "id.$ident", $line );

   #use Data::Dumper; print Dumper( $LOOK ); 
   
   # commit ID stuff to STATE file
   my $status = $LOOK->write( $file );
   unless ( defined $status ) {
      # can't read/write to options file, bail out
      my $error = $Config::Simple::errstr;
      $log->error("$error");
      throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
   } else {    
      $log->debug('Lookup table: updated ' . $file ) ;
   }                       
   
   # change the hostname and port in the rtml
   $log->debug( "Replacing $host:$port with ". 
                         $config->get_option( "tcp.host" ) . ":" .
                         $config->get_option( "tcp.port" ) ) ;
                            
   my $current_host = $config->get_option( "tcp.host" );
   my $current_port = $config->get_option( "tcp.port" );
   $rtml =~ s/$host/$current_host/;
   $rtml =~ s/$port/$current_port/;
        
   #$log->debug( "\n" . $rtml );   
   
   # FIX USER AND PROJECT
   # --------------------
   
   my $parsed;
   eval { $parsed = new XML::Document::RTML( XML => $rtml ) };
   if ( $@ ) {
      my $error = "Error: Unable to parse RTML file...";
      $log->error( "$@" );
      $log->error( $error );
      $log->error( "\nRTML File:\n$rtml" );
      throw eSTAR::Error::FatalError($error, ESTAR__FATAL);            
   }   
   
   my $original_user = $parsed->user();
   
   $log->debug( "Original user: $original_user" );
   
   my ( $new_user, $new_project );
   if ( $original_user eq "kdh1" ) {
   
      if ( $process->get_process() =~ "LT" ) {
      
         # KDH Live PATT
         $new_user = "PATT/keith.horne";
         $new_project = "PL04B17";        
      }
      
      if ( $process->get_process() =~ "FTN" ) {
      
         # KDH Live Robonet
         $new_user = "Robonet/keith.horne";
         $new_project = "Planetsearch1";        
      }

      if ( $process->get_process() =~ "FTS" ) {
      
         # KDH Live Robonet
         $new_user = "Robonet/keith.horne";
         $new_project = "Planetsearch1";        
      }
      
   } elsif( $original_user eq "aa" ) {
   
      # Expired Test Project on LT
      $new_user = "TEST/estar";
      $new_project = "TEA01";
      
      # Live Test Project on FTN
      #$new_user = "TMC/estar";
      #$new_project = "agent_test";   
      
      # NOAO ESSENCE Follow-up project
      if ( $process->get_process() =~ "FTS" ) {
         $new_user = "FTS_OPS/iain.steele";
         $new_project = "Essence";
      }
      
   } 
   if ( defined $new_user && defined $new_project ) {
 
     eval { $rtml = eSTAR::Util::fudge_user( $rtml, $new_user ); };
     if ( $@ ) {
        my $error = "Error: Trouble fudging user name";
        $log->error( "$@" );
        $log->error( $error );
        $log->error( "\nRTML File:\n$rtml" );
        throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
     }    
   
     eval { $rtml = eSTAR::Util::fudge_project( $rtml, $new_project ); };  
     if ( $@ ) {
        my $error = "Error: Trouble fudging project name";
        $log->error( "$@" );
        $log->error( $error );
        $log->error( "\nRTML File:\n$rtml" );
        throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
     }
   }
   
   # SEND TO TEA
   # -----------
   
   # pass modified RTML onto the TEA server
   
   $log->print("Passing modified RTML to TEA server..." ) ;
  
   my $sock = new IO::Socket::INET( 
                           PeerAddr => $config->get_option( "ers.host" ),
                           PeerPort => $config->get_option( "ers.port" ),
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
 
      $log->print("Sending RTML to TEA\n$rtml");
 
      # work out message length
      my $bytes = pack( "N", length($rtml) );
       
      # send message                                   
      $log->debug( "Sending " . length($rtml) . " bytes to " . 
                         $config->get_option( "ers.host" ));
      print $sock $bytes;
      $sock->flush();
      print $sock $rtml;
      $sock->flush();  
          
      # grab response
      $log->debug( "Waiting for response from TEA... " );
      
      my ( $reply_bytes, $reply_length );
      read $sock, $reply_bytes, 4;
      $reply_length = unpack( "N", $reply_bytes );
      read $sock, $response, $reply_length; 

      $log->debug( "Read " . $reply_length . " bytes to " . 
                         $config->get_option( "ers.host" ));      
      close($sock);
      
      #$log->debug( $response );
  
   }
   
   
   # GRAB MESSAGE
   # ------------
   
   # modifiy the response to include the correct IA information
   $log->debug("Updating host information...");   

   ( $host, $port, $ident ) = eSTAR::Util::fudge_message( $response );  
   
   # grab the original IntelligentAgent tage from lookup hash
        
   # stuff it into global lookup hash
   my $original = $LOOK->param( "id.$ident" );
     
   # change the hostname and port in the rtml
   $log->debug( "Replacing original <IntelligentAgent> XML tag" ) ;

   my $current = "<IntelligentAgent host=\"$host\" port=\"$port\">";
   $response =~ s/$current/$original/;
 
    
   #print "CURRENT: $current\n";
   #print "ORIGINAL: $original\n";
        
   #$log->debug( "\n" . $response );   
   
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
                  
                  
                  
