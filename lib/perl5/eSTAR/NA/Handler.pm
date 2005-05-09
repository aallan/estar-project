package eSTAR::NA::Handler;

# Basic handler class for SOAP requests for the Embedded Agent. It also
# acts as a container class for eSTAR::SOAP::User class which handles
# authentication.

use lib $ENV{"ESTAR_PERL5LIB"};     

use strict;
use subs qw( new set_user ping handle_rtml query_ldap 
             query_schedule query_webcam fudge_message );

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
   
   my ( $host, $port, $ident ) = fudge_message( $rtml );  
        
   # stuff it into global lookup hash
   my $line = "<IntelligentAgent host=\"$host\" port=\"$port\">";
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
   eval { my $object = new eSTAR::RTML( Source => $rtml );
          $parsed = new eSTAR::RTML::Parse( RTML => $object ) };
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
   if ( $original_user eq "aa" ) {
      #$new_user = "TEST/estar";
      #$new_project = "TEA01";
      $new_user = "TMC/estar";
      $new_project = "agent_test";
   } else {   
      $new_user = $original_user;
      $new_project = "";
   }   
   
   $rtml = fudge_user( $rtml, $new_user );  
   $rtml = fudge_project( $rtml, $new_project );  
   
   # SEND TO ERS
   # -----------
   
   # pass modified RTML onto the ERS server
   
   $log->print("Passing modified RTML to ERS server..." ) ;
  
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
 
      $log->print("Sending RTML to ERS\n$rtml");
 
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
      $log->debug( "Waiting for response from ERS... " );
      
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

   ( $host, $port, $ident ) = fudge_message( $response );  
   
   # grab the original IntelligentAgent tage from lookup hash
        
   # stuff it into global lookup hash
   my $original = $LOOK->param( "id.$ident" );
   
   # change the hostname and port in the rtml
   $log->debug( "Replacing original <IntelligentAgent> XML tag" ) ;

   my $current = "<IntelligentAgent host=\"$host\" port=\"$port\">";
   $response =~ s/$current/$original/;
        
   #$log->debug( "\n" . $response );   
   
   # SEND TO USER_AGENT
   # ------------------
   
   # do a find and replace, munging the response, shouldn't need to do it?
   $log->debug( "Returned RTML message\n$response");
   $response =~ s/</&lt;/g;
   
   # return an RTML response to the user_agent

   $log->debug("Returned RTML response");
   return SOAP::Data->name('return', $response )->type('xsd:string');

} 

# subroutine to handle incoming LDAP requests from user_agent(s)
sub query_ldap {   
   my $self = shift;

   $log->debug("Called query_ldap() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data"
   }
   
   # LDAP QUERY
   # ----------  

   my $node_query = new eSTAR::LDAP::Search( 
                            host    => $config->get_option( "ldap.host"),
                            port    => $config->get_option( "ldap.port"),
                            filter  => "(objectclass=DiscoveryNode)",
                            branch  => $config->get_option( "ldap.branch"),
                            timeout => $config->get_option( "ldap.timeout") );

  $log->debug(
            "Making LDAP query (objectclass=DiscoveryNode) on port " .
            $config->get_option( "ldap.port") ."...");
  my @node_entries = $node_query->execute();
    
  # Variables
  # ---------
  my ( $LDAP_dn_hn, $LDAP_dn_long, $LDAP_dn_lat, $LDAP_dn_alt, $LDAP_dn_state );
  foreach my $i (0 ... $#node_entries) {

     my @attributes = $node_entries[$i]->attributes();
     foreach my $j (0 ... $#attributes) { 

       # check for required information
       if ( $attributes[$j] eq 'hn' ) {
         # grab attribute value
         $LDAP_dn_hn = $node_entries[$i]->get_value($attributes[$j]) . "  "; 
         $log->debug( " $attributes[$j] = " . $LDAP_dn_hn );
       } elsif ( $attributes[$j] eq 'longitude' ) {
         # grab attribute value
         $LDAP_dn_long = $node_entries[$i]->get_value($attributes[$j]) ."  "; 
         $log->debug( " $attributes[$j] = " . $LDAP_dn_long );
       } elsif ( $attributes[$j] eq 'latitude' ) {
         # grab attribute value
         $LDAP_dn_lat = $node_entries[$i]->get_value($attributes[$j]) ."  "; 
         $log->debug( " $attributes[$j] = " . $LDAP_dn_lat );
       } elsif ( $attributes[$j] eq 'altitude' ) {
         # grab attribute value
         $LDAP_dn_alt = $node_entries[$i]->get_value($attributes[$j]) ."  "; 
         $log->debug( " $attributes[$j] = " . $LDAP_dn_alt );
       } elsif ( $attributes[$j] eq 'state' ) {
         # grab attribute value
         $LDAP_dn_state = $node_entries[$i]->get_value($attributes[$j]) ."  "; 
         $log->debug( " $attributes[$j] = " . $LDAP_dn_state );
       } 
       
     }
  }
  
  # stuff into hash
  my %discovery_node;
  $discovery_node{ "dn.hostname" } = $LDAP_dn_hn;  
  $discovery_node{ "dn.longitude" } = $LDAP_dn_long; 
  $discovery_node{ "dn.latitude" } = $LDAP_dn_lat; 
  $discovery_node{ "dn.altitude" } = $LDAP_dn_alt;
  $discovery_node{ "dn.state" } = $LDAP_dn_state;
  
  
  # Query the telescope LDAP
  my $tele_query = new eSTAR::LDAP::Search(  
                            host    => $config->get_option( "ldap.host"),
                            port    => $config->get_option( "ldap.port"),
                            filter  => "(objectclass=TelescopeSystem)",
                            branch  => $config->get_option( "ldap.branch"),
                            timeout => $config->get_option( "ldap.timeout") );
  
  $log->debug(
            "Making LDAP query (objectclass=TelescopeSystem) on port " .
            $config->get_option( "ldap.port") ."...");                                   
  my @tele_entries = $tele_query->execute();

  # Variables
  # ---------
  my ( $LDAP_tel_man, $LDAP_tel_model, $LDAP_tel_size, $LDAP_tel_focal,
       $LDAP_tel_mount, $LDAP_tel_ra, $LDAP_tel_dec, $LDAP_tel_state );
  foreach my $i (0 ... $#tele_entries) {

     my @attributes = $tele_entries[$i]->attributes();
     foreach my $j (0 ... $#attributes) { 
       
       # check for required information
       if ( $attributes[$j] eq 'manufacturer' ) {
         # grab attribute value
         $LDAP_tel_man = $tele_entries[$i]->get_value($attributes[$j]) . "  "; 
         $log->debug( " $attributes[$j] = " . $LDAP_tel_man );
       } elsif ( $attributes[$j] eq 'model' ) {
         # grab attribute value
         $LDAP_tel_model = $tele_entries[$i]->get_value($attributes[$j]) ."  "; 
         $log->debug( " $attributes[$j] = " . $LDAP_tel_model );
       } elsif ( $attributes[$j] eq 'mirrorsize' ) {
         # grab attribute value
         $LDAP_tel_size = $tele_entries[$i]->get_value($attributes[$j]) ."  "; 
         $log->debug( " $attributes[$j] = " . $LDAP_tel_size );
       } elsif ( $attributes[$j] eq 'focallength' ) {
         # grab attribute value
         $LDAP_tel_focal = $tele_entries[$i]->get_value($attributes[$j]) ."  "; 
         $log->debug( " $attributes[$j] = " . $LDAP_tel_focal );
       } elsif ( $attributes[$j] eq 'mount' ) {
         # grab attribute value
         $LDAP_tel_mount = $tele_entries[$i]->get_value($attributes[$j]) ."  "; 
         $log->debug( " $attributes[$j] = " . $LDAP_tel_mount );
       } elsif ( $attributes[$j] eq 'ra' ) {
         # grab attribute value
         $LDAP_tel_ra = $tele_entries[$i]->get_value($attributes[$j]) ."  "; 
         $log->debug( " $attributes[$j] = " . $LDAP_tel_ra );
       } elsif ( $attributes[$j] eq 'dec' ) {
         # grab attribute value
         $LDAP_tel_dec = $tele_entries[$i]->get_value($attributes[$j]) ."  "; 
         $log->debug( " $attributes[$j] = " . $LDAP_tel_dec );
       } elsif ( $attributes[$j] eq 'state' ) {
         # grab attribute value
         $LDAP_tel_state = $tele_entries[$i]->get_value($attributes[$j]) ."  "; 
         $log->debug( " $attributes[$j] = " . $LDAP_tel_state );
       }
       
     }
  }  
  
  # stuff into lookup hash
  $discovery_node{ "ts.manufacturer" } = $LDAP_tel_man; 
  $discovery_node{ "ts.model" } = $LDAP_tel_model; 
  $discovery_node{ "ts.aperture" } = $LDAP_tel_size; 
  $discovery_node{ "ts.focal_length" } = $LDAP_tel_focal;
  $discovery_node{ "ts.mount" } = $LDAP_tel_mount; 
  $discovery_node{ "ts.ra" } =  $LDAP_tel_ra; 
  $discovery_node{ "ts.dec" } = $LDAP_tel_dec; 
  $discovery_node{ "ts.state" } = $LDAP_tel_state;
       
  # Query the instrument LDAP
  my $inst_query = new eSTAR::LDAP::Search( 
                            host    => $config->get_option( "ldap.host"),
                            port    => $config->get_option( "ldap.port"),
                            filter  => "(objectclass=InstrumentSystem)",
                            branch  => $config->get_option( "ldap.branch"),
                            timeout => $config->get_option( "ldap.timeout") );
  
  $log->debug(
            "Making LDAP query (objectclass=InstrumentSystem) on port " .
            $config->get_option( "ldap.port") ."..." );                                     
  my @inst_entries = $inst_query->execute();  

  # Variables
  # ---------
  my ( $LDAP_inst_man, $LDAP_inst_model, $LDAP_inst_filt, $LDAP_inst_cols,
       $LDAP_inst_rows, $LDAP_inst_length, $LDAP_inst_start, $LDAP_inst_state,
       $LDAP_inst_XbyY );
  foreach my $i (0 ... $#inst_entries) {

     my @attributes = $inst_entries[$i]->attributes();
     foreach my $j (0 ... $#attributes) { 
       
       # check for required information
       if ( $attributes[$j] eq 'manufacturer' ) {
         # grab attribute value
         $LDAP_inst_man = $inst_entries[$i]->get_value($attributes[$j]) . "  "; 
         $log->debug( " $attributes[$j] = " . $LDAP_inst_man );
       } elsif ( $attributes[$j] eq 'model' ) {
         # grab attribute value
         $LDAP_inst_model = $inst_entries[$i]->get_value($attributes[$j])."  ";
         $log->debug( " $attributes[$j] = " . $LDAP_inst_model );
       } elsif ( $attributes[$j] eq 'filter' ) {
         # grab attribute value
         $LDAP_inst_filt = $inst_entries[$i]->get_value($attributes[$j])."  ";
         $log->debug( " $attributes[$j] = " . $LDAP_inst_filt);
       } elsif ( $attributes[$j] eq 'ncols' ) {
         # grab attribute value
         $LDAP_inst_cols = $inst_entries[$i]->get_value($attributes[$j])."  ";
         $log->debug( " $attributes[$j] = " . $LDAP_inst_cols);
       } elsif ( $attributes[$j] eq 'nrows' ) {
         # grab attribute value
         $LDAP_inst_rows = $inst_entries[$i]->get_value($attributes[$j])."  ";
         $log->debug( " $attributes[$j] = " . $LDAP_inst_rows);
       } elsif ( $attributes[$j] eq 'exposurelength' ) {
         # grab attribute value
         $LDAP_inst_length = $inst_entries[$i]->get_value($attributes[$j])."  ";
         $log->debug( " $attributes[$j] = " . $LDAP_inst_length);
       } elsif ( $attributes[$j] eq 'exposurestart' ) {
         # grab attribute value
         $LDAP_inst_start = $inst_entries[$i]->get_value($attributes[$j])."  ";
         $log->debug( " $attributes[$j] = " . $LDAP_inst_start);
       } elsif ( $attributes[$j] eq 'state' ) {
         # grab attribute value
         $LDAP_inst_state = $inst_entries[$i]->get_value($attributes[$j])."  ";
         $log->debug( " $attributes[$j] = " . $LDAP_inst_state);
       }
       
     }
  }
  
  # set the X x Y pixel size of the CCD
  $LDAP_inst_XbyY = " $LDAP_inst_cols x $LDAP_inst_rows ";  
  $log->debug(" ccd_size = ".$LDAP_inst_XbyY) if defined $LDAP_inst_XbyY;
  
  # stuff into lookup hash
  $discovery_node{ "is.manufacturer" } = $LDAP_inst_man;
  $discovery_node{ "is.model" } = $LDAP_inst_model;
  $discovery_node{ "is.filter" } = $LDAP_inst_filt;
  $discovery_node{ "is.exposure_length" } = $LDAP_inst_length;
  $discovery_node{ "is.exposure_start" } = $LDAP_inst_start;
  $discovery_node{ "is.state" } = $LDAP_inst_state;
  $discovery_node{ "is.ccd_size" } = $LDAP_inst_XbyY;

  # return SOAP message
  $log->debug("Returned LDAP hash"); 

  return \%discovery_node;
}

# subroutine to handle incoming schedule requests from user_agent(s)
sub query_schedule {   
   my $self = shift;

   $log->debug("Called query_schedule() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data"
   }
   
   # Scheduler Query
   # ---------------
   
   $log->print("Sending 'list' command to Scheduler..." ) ;
  
   my $sock = new IO::Socket::INET( 
                           PeerAddr => $config->get_option( "scheduler.host" ),
                           PeerPort => $config->get_option( "scheduler.port" ),
                           Proto    => "tcp" );
   my ( $response );                        
   unless ( $sock ) {
      
      # we have an error
      my $error = "$!";
      chomp($error);
      $log->error( "Error: $error") ;
      $log->error("Returned ERROR message");
      return SOAP::Data->name('return', "ERROR: $error" )->type('xsd:string');
   
   } else { 
      # scheduler command
      my $command = 'list';
 
      # work out message length
      my $bytes = pack( "N", length($command) );
       
      # send message                                   
      $log->debug( "Sending " . length($command) . " bytes to " . 
                         $config->get_option( "scheduler.host" ));
      print $sock $bytes;
      $sock->flush();
      print $sock $command;
      $sock->flush();  
          
      # grab response
      $log->debug( "Waiting for response from Scheduler... " );
      
      # get length
      my ( $reply_bytes, $reply_length );
      read $sock, $reply_bytes, 4;
      $reply_length = unpack( "N", $reply_bytes );
      
      # get status
      my $status;
      read $sock, $status, 1;
      if ( $status != 0 ) {
        my $error = "Error: Scheduler returned bad status $status";
        $log->error(  $error );
        $log->error("Returned ERROR message");
        throw eSTAR::Error::FatalError($error, ESTAR__FATAL);            
      }
      
      # get message
      read $sock, $response, $reply_length-1; 

      $log->debug( "Read " . $reply_length . " bytes to " . 
                         $config->get_option( "scheduler.host" ));      
      close($sock);
      
      $log->debug( $response );
  
   }   
     
  $log->debug("Returned node schedule"); 
   return SOAP::Data->name('return', $response )->type('xsd:string');
   
}
 
# subroutine to handle incoming webcam requests from user_agent(s), currently
# crippled as I can't get Video::Capture::V4l to work.
sub query_webcam {   
   my $self = shift;

   $log->debug("Called query_webcam() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data"
   }
   
   # Take image
   # ----------
   #my $grab;
   #$log->debug("Creating Video::Capture::V4l device...");
   #unless ( $grab = new Video::Capture::V4l() ) {
   #   $log->warn("Warning: Unable to open /dev/video0");
   #   return "Unable to open /dev/video0";
   #}
   
   # grab frame
   #$log->debug("Grabbing frame...");
   #my $frame = $grab->capture(0, 352, 288, PALETTE_YUV420P);
   #unless ( $grab->sync(0) ) {
   #   $log->warn("Warning: Unable to sync video device");
   #   return "Unable to sync video device";
   #};

   # save as PPM file
   #my $file = File::Spec->catfile( Config::User->Home(), '.estar', $process,
   #                                'webcam.ppm' );
                                   
   #unless ( open (PPM, "+>$file" )) {
   #   $log->error("Error: Unable to open $file");
   #   return "Unable to open $file";
   #}
   #print PPM "P6 352 288 255\n$rgb";
   #close(PPM);         
   #$log->warn("Warning: Unable to write YUV data to file");


   # build URL for the webcam image 
   $log->debug("Querying webcam...");
   my $image_url = "http://" . $config->get_option( "webcam.host" ) . ":" .
                  $config->get_option( "webcam.port") . "/singleframe";
       
   # make request       
   my $request = new HTTP::Request( 'GET', $image_url );
   my $reply = $ua->get_ua()->request($request);

   # check for valid reply
   if ( ${$reply}{"_rc"} eq 200 ) {
      if ( ${${$reply}{"_headers"}}{"content-type"} eq "image/jpeg" ) {        
         $log->debug("Recieved response from webcam server");
  
         # build a pathname for the agent                
         my $file_name =  File::Spec->catfile( 
               $config->get_option("dn.tmp"), 
               $config->get_option("webcam.host") . "_webcam.jpg");       
         
         my $file = File::Spec->catfile(
                    $config->get_option("webcam.host") . "_webcam.jpg");
                    
         # Open output file
         unless ( open ( IMAGE, "+>$file_name" )) {
           $log->error("Error: Cannot open $file_name for writing");
         } else {  
           # Write to output file
           $log->debug("Saving image: $file_name");
           my $length = length(${$reply}{"_content"});
           syswrite( IMAGE, ${$reply}{"_content"}, $length );
           close(IMAGE);
         }  
                 
         # we have a valid jpeg image hopefully, so create a MIME::Entity
         # and return the JPEG to the user_ugent
         my $package = build MIME::Entity
                       Type        => "image/jpeg",
                       Encoding    => "base64",
                       Path        => $file_name,
                       Filename    => $file,
                       Disposition => "attachment";

         $log->debug("Returned 'ATTACHED' message"); 
         return SOAP::Data->name('return', 'ATTACHED' )->type('xsd:string'), 
                $package;
      
      
      } else {
        # unknown document, not of type octet-stream
        $log->error("Error: Unknown document recieved from remote host "
                  . "(" . ${${$reply}{"_headers"}}{"content-type"} .")");
      
      }
      
   } else {
      # can't connect via network to HTTP server
      $log->error("Error (${$reply}{_rc}): ${$reply}{_msg}");
   }            

   $log->debug("Returned 'FAILED' message"); 
   return SOAP::Data->name('return', 'FAILED' )->type('xsd:string');
   
}
                              
# A S S O C I A T E D   S U B R O U T I N E S ------------------------------

# grabs the origin host, port and identity of the message from the RTML

sub fudge_message {
   my $rtml = shift;
   my @message = split( /\n/, $rtml );
   
   $log->debug("Called fudge_message()...");
   
   my ( $host, $port, $ident );
   foreach my $i ( 0 ... $#message ) {
     if ( $message[$i] =~ "<IntelligentAgent" ) {
        
        # grab host and port number
        $host = $message[$i];
        $port = $message[$i];
        
        # grab hostname
        my $host_index = index( $message[$i], q/host=/ );
        my $host = substr( $message[$i], $host_index, 
                                         length($message[$i])-$host_index );
        my $start_index = index( $host, q/"/ );         
        my $port_index = index( $host, q/port=/ );
        $host = substr( $host, $start_index+1, $port_index-$start_index-1 );
        my $last_index = rindex( $host, q/"/ );         
        $host = substr( $host, 0, $last_index );
        
        # grab port number
        $port_index = index( $message[$i], q/port=/ );
        $last_index = rindex( $message[$i], q/"/ );
        my $port = substr( $message[$i], $port_index, $last_index-$port_index );
        $start_index = index( $port, q/"/ );
        $last_index = rindex( $message[$i], q/"/ );
        $port = substr( $port, $start_index+1, $last_index-$start_index-1 );

        $log->debug("Reply address: " . $host . ":" . $port);

        # grab unique identity
        my $tag_start = index( $rtml, q/<IntelligentAgent/ );
        my $tag_end = index( $rtml, q/<\/IntelligentAgent/ );
        
        $ident = substr( $rtml, $tag_start, $tag_end-$tag_start );
        my $quot_index = index ( $ident, q/>/ );
        $ident = substr( $ident, $quot_index+1, length($ident)-$quot_index);
        $ident =~ s/\n//g;
        $ident =~ s/\s+//g;

        $log->debug("Identifier: $ident");
        return ( $host, $port, $ident );

                    
     }   
   }
   
   return ( undef, undef, undef );
} 


sub fudge_user {
   my $rtml = shift;
   my $user = shift;
   
   my @message = split( /\n/, $rtml );
   
   $log->debug("Called fudge_user( $user )...");
   
   my $new_rtml;
   foreach my $i ( 0 ... $#message ) {
     if ( $message[$i] =~ "<User>" ) {
        if ( $message[$i] =~ "</User>" ) {
           $message[$i] = "<User>$user</User>";
        } else {
           my $error = "Unable to parse <User></User> field from document";
           throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
        }     
     }
     $new_rtml = $new_rtml . $message[$i] . "\n";
     
   }
   return $new_rtml;
}     


sub fudge_project {
   my $rtml = shift;
   my $project_id = shift;
   
   my @message = split( /\n/, $rtml );
   
   $log->debug("Called fudge_project_id( $project_id )...");
   
   my $new_rtml;
   foreach my $i ( 0 ... $#message ) {
     if ( $message[$i] =~ "<Project />" ) {  
        
        $message[$i] = "<Project>$project_id</Project>";
     }
     $new_rtml = $new_rtml . $message[$i] . "\n";
   }
   
   return $new_rtml;
}
                      
                  
1;                                
                  
                  
                  
