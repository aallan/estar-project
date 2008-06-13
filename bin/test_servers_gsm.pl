#!/software/perl-5.8.8/bin/perl
  
  #use strict;
  
  use vars qw /$VERSION %MACHINES %NODE_AGENTS %USER_AGENTS %EVENT_BROKERS/;

  $VERSION = '0.1';

  #
  # General modules
  use Getopt::Long;
  use LWP::UserAgent;
  use SOAP::Lite;
  use Digest::MD5 'md5_hex';
  use Fcntl qw(:DEFAULT :flock);
  use URI;
  use HTTP::Cookies;
  use Getopt::Long;
  use LWP::UserAgent;
  use Net::Domain qw(hostname hostdomain);
  use Socket;
  use Net::FTP;
  use Net::Ping;
  use File::Spec;
  use Time::localtime;
  use Data::Dumper;
  use Net::Twitter;
  
  #
  # eSTAR modules
  use lib $ENV{"ESTAR_PERL5LIB"};     
  use eSTAR::Util;
  use eSTAR::Logging;
  use eSTAR::Process;
  use eSTAR::Config;
  use eSTAR::Error qw /:try/;
  use eSTAR::Constants qw/:status/;
  use eSTAR::Mail;
  use eSTAR::UserAgent;
  use eSTAR::GSM;
  use eSTAR::UserAgent;

  my $process = new eSTAR::Process( "test_servers_gsm" );  
  $process->set_version( $VERSION );
  print "Starting logging...\n\n";
  $log = new eSTAR::Logging( $process->get_process() );
  $log->header("Starting Server Test (with GSM): Version $VERSION");
  my $config = new eSTAR::Config(  );  
  
   
  $log->print( "Twittering start of self-check..." );
  twitter( "eSTAR is starting a self check at ".ctime() );   

# S T A T E   F I L E --------------------------------------------------------


  my ( $number, $string );
  $number = $config->get_state( "test.unique_process" ); 
  unless ( defined $number ) {
    # $number is not defined correctly (first ever run of the program?)
    $number = 0; 
  }

  # increment ID number
  $number = $number + 1;
  $config->set_state( "test.unique_process", $number );
  $log->debug("Setting test.unique_process = $number"); 
  
  # commit ID stuff to STATE file
  $status = $config->write_state();
  unless ( defined $status ) {
    # can't read/write to options file, bail out
    my $error = "FatalError: Can not read or write to state.dat file";
    $log->error( $error );
    throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
  } else {    
    $log->debug("Unique process ID: updated state.dat file" );
  }


  $config->set_state( "test.pid", getpgrp() );
  
  # commit $pid to STATE file
  $status = $config->write_state();
  unless ( defined $status ) {
    # can't read/write to options file, bail out
    my $error = "FatalError: Can not read or write to state.dat file";
    $log->error( $error );
    throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
  } else {    
    $log->debug("Program PID: " . $config->get_state( "test.pid" ) );
  }

# M A K E   D I R E C T O R I E S -------------------------------------------

# create the data, state and tmp directories if needed
$status = $config->make_directories();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Problems creating data directories";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} 
    
# M A I N   O P T I O N S   H A N D L I N G ---------------------------------

  # grab current IP address
  my $ip = inet_ntoa(scalar(gethostbyname(hostname())));
  $log->debug("This machine as an IP address of $ip");

  if ( $config->get_state("test.unique_process") == 1 ) {
   
     # grab current user
     my $current_user = $user_id{$ENV{"USER"}};
     my $real_name = ${$current_user}{"GCOS"};
  
     # user defaults
     $config->set_option("user.user_name", "estar" );
     $config->set_option("user.real_name", "eSTAR Status List" );
     $config->set_option("user.email_address", 'estar-status@estar.org.uk');
     $config->set_option("user.institution", "eSTAR Project at Exeter University" );
     $config->set_option("user.notify", 1 );

     # node port
     $config->set_option("dn.default_port", 8080 );

     # connection options defaults
     $config->set_option("connection.timeout", 20 );
     $config->set_option("connection.proxy", 'NONE'  );
  
     # mail server
     $config->set_option("mailhost.name", 'pinky' );
     $config->set_option("mailhost.domain", 'astro.ex.ac.uk' );
     $config->set_option("mailhost.timeout", 30 );
     $config->set_option("mailhost.debug", 0 );   
        
     # C O M M I T T   O P T I O N S  T O   F I L E S
     # ----------------------------------------------
   
     # committ CONFIG and STATE changes
     $log->warn("Initial default options being generated");
     $log->warn("Committing options and state changes...");
     $status = $config->write_option( );
     $status = $config->write_state();
  }

# H T T P   U S E R   A G E N T ------------------------------------------

$log->debug("Creating an HTTP User Agent...");
 

# Create HTTP User Agent
my $lwp = new LWP::UserAgent( 
                timeout => $config->get_option( "connection.timeout" ));

# Configure User Agent                         
$lwp->env_proxy();
$lwp->agent( "eSTAR Persistent User Agent /$VERSION (" 
            . hostname() . "." . hostdomain() .")");

my $ua = new eSTAR::UserAgent(  );  
$ua->set_ua( $lwp );

# O P E N   O U T P U T   F I L E -----------------------------------------

  my $content = "";

  my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
  my $file = File::Spec->catfile( $state_dir, "check." . 
                      $config->get_state( "test.unique_process" ) );
  $log->debug("\nOpening output file... $file");  
          
  # write the observation object to disk.
  unless ( open ( SERIAL, "+>$file" )) {
     # check for errors, theoretically if we can't temporarily write to
     # the state directory this is no great loss as we'll create a fresh
     # observation object in the handle_rtml() routine if the unique id
     # of the object isn't known (i.e. it doesn't exist as a file in
     # the state directory)
     my $error = "Warning: Can not write to "  . $state_dir; 
     $log->error( $error );
     throw eSTAR::Error::FatalError($error, ESTAR__FATAL);                          
  } else {
     unless ( flock( SERIAL, LOCK_EX ) ) {
        my $error = "Warning: unable to acquire exclusive lock: $!";
        $log->error( $error );
        throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
     } else {
        $log->debug("Acquiring exclusive lock...");
     }
  }
  print SERIAL "# " . ctime() . "\n"; 
  $content = $content . "Network Status at " . ctime() . "\n\n";   

# E S T A R   H O S T S ---------------------------------------------------

  # list of "default" known nodes  
  my @hosts;
  push @hosts, "estar-switch.astro.ex.ac.uk";
  push @hosts, "estar-ups.astro.ex.ac.uk";
  push @hosts, "estar1.astro.ex.ac.uk";
  push @hosts, "estar2.astro.ex.ac.uk";
  push @hosts, "estar3.astro.ex.ac.uk";
  push @hosts, "estar4.astro.ex.ac.uk";
  push @hosts, "estar5.astro.ex.ac.uk";
  push @hosts, "estar6.astro.ex.ac.uk";
  push @hosts, "estar7.astro.ex.ac.uk";
  push @hosts, "estar8.astro.ex.ac.uk";
  push @hosts, "estar9.astro.ex.ac.uk";
  push @hosts, "estar.ukirt.jach.hawaii.edu";
  push @hosts, "www.estar.org.uk";
  push @hosts, "132.160.98.239"; # FTN proxy
  push @hosts, "161.72.57.3"; # LT proxy
  push @hosts, "150.203.153.202"; # FTS proxy
  
  #use Data::Dumper;
  #print Dumper( @hosts);
  
  print SERIAL "# MACHINES\n";
  
  foreach my $i ( 0 ... $#hosts ) {
  
    if( $hosts[$i] eq "www.estar.org.uk" ) {
       $log->header("\n$hosts[$i]");    
       $log->debug( "Checking webhost $hosts[$i]...");

       my $url = "http://www.estar.org.uk/network.status";        
       $log->debug("URL = $url" );
       $log->debug("Fetching page..." );
       my $reply;
       eval { $reply = $ua->get_ua()->get( $url ) };

       if ( $@ || ${$reply}{"_rc"} ne 200 ) {
          print SERIAL "$hosts[$i] NACK\n";
          $content = $content . "$hosts[$i] NACK\n";     
          $log->error( "$hosts[$i]: NACK");         
       } else {  
          print SERIAL "$hosts[$i] PING\n";
          $content = $content . "$hosts[$i] PING\n";  
          $log->print( "$hosts[$i]: ACK");       
       }
       next;
    }  

    $log->header("\n$hosts[$i]");
    $log->debug( "Pinging $hosts[$i]...");
#    my $ping = Net::Ping->new( "icmp" );
    my $ping = Net::Ping->new(  );
    if ( $ping->ping( $hosts[$i] ) ) {
        $MACHINES{$hosts[$i]} = 'PING';
        print SERIAL "$hosts[$i] PING\n";
        $log->print( "$hosts[$i]: ACK");
    } else {	
        $MACHINES{$hosts[$i]} = 'NACK';
        print SERIAL "$hosts[$i] NACK\n";
        $log->error( "$hosts[$i]: NACK");
    } 
    $ping->close();
  }
  $content = $content . "\n";

# K N O W N   N O D E S ---------------------------------------------------

  # list of "default" known nodes  
  $config->set_option( "nodes.UKIRT", "estar.ukirt.jach.hawaii.edu:8080" );
#  $config->set_option( "nodes.LT", "estar3.astro.ex.ac.uk:8078" );
#  $config->set_option( "nodes.FTN", "estar3.astro.ex.ac.uk:8077" );
#  $config->set_option( "nodes.FTS", "estar3.astro.ex.ac.uk:8079" );
#$config->set_option( "nodes.LT", "161.72.57.3:8080/axis/services/NodeAgent" );
$config->set_option( "nodes.LT", "161.72.57.3:8080/org_estar_nodeagent/services/NodeAgent" );
$config->set_option( "nodes.FTN", "132.160.98.239:8080/axis/services/NodeAgent" );
$config->set_option( "nodes.FTS", "150.203.153.202:8080/axis/services/NodeAgent" );
  $config->set_option( "nodes.RAPTOR", "estar2.astro.ex.ac.uk:8080" );
  $status = $config->write_option( );

# L O O P   T H R O U G H   N O D E S ----------------------------------------

  print SERIAL "# NODE AGENTS\n";
  $content = $content . "Node Agents\n-----------\n\n";   

  # NODE ARRAY
  my ( @NODES, @NAMES );   

  # we might not have any nodes! So check!
  my $node_flag = 0;
  @NODES = $config->get_nodes();   
  @NAMES = $config->get_node_names();   
  $node_flag = 1 if defined $NODES[0];
  
  # if there are no nodes add a default menu entry
  if ( $node_flag == 0 ) {
     my $error = "Error: No known Discovery Nodes";
     $log->error( $error );
     throw eSTAR::Error::FatalError( $error );
  }    
  
  foreach my $i ( 0 ... $#NODES ) {
     
     my ($dn_host, $dn_port) = split ":", $NODES[$i];
     $log->header("\n$NAMES[$i] ( $dn_host:$dn_port )");
 
     # end point
     my $endpoint = "http://" . $dn_host . ":" . $dn_port;
     $log->debug( "Endpoint for request is " . $endpoint );
     my $uri = new URI($endpoint);
   
     # create a user/passwd cookie
     my $cookie = eSTAR::Util::make_cookie( "agent", "InterProcessCommunication" );
  
     my $cookie_jar = HTTP::Cookies->new();
     $cookie_jar->set_cookie( 0, user => $cookie, '/', 
                              $uri->host(), $uri->port());
     
     # create SOAP connection
     my $soap = new SOAP::Lite();
  
     $urn = "urn:/node_agent";
     $log->debug( "URN for node is " . $urn );
  
     $soap->uri($urn); 
     $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
     # report
     $log->debug("Calling ping( ) at $dn_host");
    
     # grab result 
     my $result;
     eval { $result = $soap->ping( ); };
     if ( $@ ) {
        my $error = $@;
        chomp ( $error );
        $log->error( "Error ($dn_host): NODE DOWN" );
        print SERIAL "$NAMES[$i] $dn_host $dn_port DOWN\n";
        $NODE_AGENTS{$NAMES[$i]} = 'DOWN';
     }
  
     if ( defined $result ) {     
        # Check for errors
        $log->debug("Transport Status: " . $soap->transport()->status() );
        unless ($result->fault() ) {
           $log->print( "$NAMES[$i] ($dn_host): " . $result->result() );
           print SERIAL "$NAMES[$i] $dn_host $dn_port UP\n";
           $NODE_AGENTS{$NAMES[$i]} = 'UP';
        } else {
           $log->error( "Error ($dn_host): ". $result->faultcode() );
           $log->error( "Error ($dn_host): " . $result->faultstring() );
           print SERIAL "$NAMES[$i] $dn_host $dn_port FAULT\n";
           $NODE_AGENTS{$NAMES[$i]} = 'FAULT';
        }
     }  
  }
  
# K N O W N   A G E N T S  --------------------------------------------------

  # list of "default" known nodes  
  $config->set_option( "useragents.GRB", "estar7.astro.ex.ac.uk:8000" );
  $config->set_option( "useragents.EXO-PLANET", "estar5.astro.ex.ac.uk:8000" );
  $config->set_option( "useragents.ADP", "estar.astro.ex.ac.uk:8000" );
  $status = $config->write_option( );
  
# L O O P   T H R O U G H  A G E N T S  -------------------------------------

  print SERIAL "# USER AGENTS\n";
  $content = $content . "\nUser Agents\n-----------\n\n";   

  # NODE ARRAY
  my ( @UAS, @UA_NAMES );   

  # we might not have any nodes! So check!
  my $ua_flag = 0;
  @UAS = $config->get_useragents();   
  @UA_NAMES = $config->get_useragent_names();   
  $ua_flag = 1 if defined $UAS[0];
  
  # if there are no nodes add a default menu entry
  if ( $ua_flag == 0 ) {
     my $error = "Error: No known User Agents";
     $log->error( $error );
     throw eSTAR::Error::FatalError( $error );
  }    
  
  foreach my $i ( 0 ... $#UAS ) {
     
     my ($ua_host, $ua_port) = split ":", $UAS[$i];
     $log->header("\n$UA_NAMES[$i] ( $ua_host:$ua_port )");
 
     # end point
     my $endpoint = "http://" . $ua_host . ":" . $ua_port;
     $log->debug( "Endpoint for request is " . $endpoint );
     my $uri = new URI($endpoint);
   
     # create a user/passwd cookie
     my $cookie = eSTAR::Util::make_cookie( "agent", "InterProcessCommunication" );
  
     my $cookie_jar = HTTP::Cookies->new();
     $cookie_jar->set_cookie( 0, user => $cookie, '/', 
                              $uri->host(), $uri->port());
     
     # create SOAP connection
     my $soap = new SOAP::Lite();
  
     $urn = "urn:/user_agent";
     $log->debug( "URN for agent is " . $urn );
  
     $soap->uri($urn); 
     $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
     # report
     $log->debug("Calling ping( ) at $ua_host");
    
     # grab result 
     my $result;
     eval { $result = $soap->ping( ); };
     if ( $@ ) {
        my $error = $@;
        chomp ( $error );
        $log->error( "Error ($ua_host): AGENT DOWN" );
        print SERIAL "$UA_NAMES[$i] $ua_host $ua_port DOWN\n";
        $USER_AGENTS{$UA_NAMES[$i]} = 'DOWN';
     }
  
     if ( defined $result ) {     
        # Check for errors
        $log->debug("Transport Status: " . $soap->transport()->status() );
        unless ($result->fault() ) {
           $log->print( "$UA_NAMES[$i] ($ua_host): " . $result->result() );
           print SERIAL "$UA_NAMES[$i] $ua_host $ua_port UP\n";
           $USER_AGENTS{$UA_NAMES[$i]} = 'UP';
        } else {
           $log->error( "Error ($ua_host): ". $result->faultcode() );
           $log->error( "Error ($un_host): " . $result->faultstring() );
           print SERIAL "$UA_NAMES[$i] $ua_host $ua_port FAULT\n";
           $USER_AGENTS{$UA_NAMES[$i]} = 'FAULT';
        }
     }  
  }  


# K N O W N   B R O K E R S -------------------------------------------------

  # list of "default" known nodes  
  $config->set_option( "brokers.eSTAR", "estar6.astro.ex.ac.uk:9099" );
  $status = $config->write_option( );    
    
  
# L O O P   T H R O U G H  A G E N T S  -------------------------------------

  print SERIAL "# EVENT BROKERS\n";
  $content = $content . "\nBrokers\n-------\n\n";   

  # NODE ARRAY
  my ( @BROKERS, @BROKER_NAMES );   

  # we might not have any nodes! So check!
  my $broker_flag = 0;
  @BROKERS = $config->get_brokers();   
  @BROKER_NAMES = $config->get_broker_names();   
  $broker_flag = 1 if defined $BROKERS[0];
  
  # if there are no nodes add a default menu entry
  if ( $broker_flag == 0 ) {
     my $error = "Error: No known Brokers";
     $log->error( $error );
     throw eSTAR::Error::FatalError( $error );
  }    
  
  foreach my $i ( 0 ... $#BROKERS ) {
     
     my ($broker_host, $broker_port) = split ":", $BROKERS[$i];
     $log->header("\n$BROKER_NAMES[$i] ( $broker_host:$broker_port )");
 
     # end point
     my $endpoint = "http://" . $broker_host . ":" . $broker_port;
     $log->debug( "Endpoint for request is " . $endpoint );
     my $uri = new URI($endpoint);
   
     # create a user/passwd cookie
     my $cookie = eSTAR::Util::make_cookie( "agent", "InterProcessCommunication" );
  
     my $cookie_jar = HTTP::Cookies->new();
     $cookie_jar->set_cookie( 0, user => $cookie, '/', 
                              $uri->host(), $uri->port());
     
     # create SOAP connection
     my $soap = new SOAP::Lite();
  
     $urn = "urn:/event_broker";
     $log->debug( "URN for broker is " . $urn );
  
     $soap->uri($urn); 
     $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
     # report
     $log->debug("Calling ping( ) at $broker_host");
    
     # grab result 
     my $result;
     eval { $result = $soap->ping( ); };
     if ( $@ ) {
        my $error = $@;
        chomp ( $error );
        $log->error( "Error ($broker_host): BROKER DOWN" );
        print SERIAL "$BROKER_NAMES[$i] $broker_host $broker_port DOWN\n";
        $EVENT_BROKERS{$BROKER_NAMES[$i]} = 'DOWN';
     }
  
     if ( defined $result ) {     
        # Check for errors
        $log->debug("Transport Status: " . $soap->transport()->status() );
        unless ($result->fault() ) {
           $log->print( "$BROKER_NAMES[$i] ($broker_host): " . $result->result() );
           print SERIAL "$BROKER_NAMES[$i] $broker_host $broker_port UP\n";
           $EVENT_BROKERS{$BROKER_NAMES[$i]} = 'UP';
        } else {
           $log->error( "Error ($broker_host): ". $result->faultcode() );
           $log->error( "Error ($un_host): " . $result->faultstring() );
           print SERIAL "$BROKER_NAMES[$i] $broker_host $broker_port FAULT\n";
           $EVENT_BROKERS{$BROKER_NAMES[$i]} = 'FAULT';
        }
     }  
  }  
 
    
# C L E A N   U P -----------------------------------------------------------
  
  $log->debug("\nClosing output file...");  
  close(SERIAL);  
  $log->debug("Freeing flock()...");  
  
# N O T I F Y   P E O P L  E ------------------------------------------------
   
  $log->print( "Checking for notifiable error states..." );
   
  if ($MACHINES{'estar-switch.astro.ex.ac.uk'} ne 'PING' ) {
  
     my $text = "eSTAR Test: network connection down at ". ctime();
     $log->debug( $text );
     eSTAR::GSM::send_sms( "447973793139", $text );  

  } else {
    
      # We can contact the switch, we should be able to contact the world
      if( $EVENT_BROKERS{eSTAR} ne 'UP' ) {
      
         my $text = "eSTAR Test: Event broker down at ".ctime();
         $log->debug( $text );
    	 eSTAR::GSM::send_sms( "447973793139", $text );
      }
      twitter( "The VOEvent broker in Exeter is $EVENT_BROKERS{eSTAR}." );
      
      if( $USER_AGENTS{GRB} ne 'UP' ) {
          my $text = "eSTAR Test: GRB user agent down at ".ctime();
          $log->debug( $text );	  
    	  eSTAR::GSM::send_sms( "447973793139", $text );
      }      
      twitter( "The GRB programme is $USER_AGENTS{GRB}." );

      if( $USER_AGENTS{'EXO-PLANET'}  ne 'UP' ) {
          my $text = "eSTAR Test: EXO user agent down at ".ctime();
          $log->debug( $text );	  
    	  eSTAR::GSM::send_sms( "447973793139", $text );
      }
      twitter( "The Exo-planet programme is $USER_AGENTS{'EXO-PLANET'}." );
    	    
      if( $NODE_AGENTS{UKIRT} ne 'UP' ) {
          my $text;
	  if( $NODE_AGENTS{UKIRT} eq 'DOWN' ) {
             $text = "eSTAR Test: UKIRT node agent down at ".ctime();
	  } else {
             $text = "eSTAR Test: Fault with UKIRT node agent at ".ctime();
	  }
          $log->debug( $text );	  
    	  eSTAR::GSM::send_sms( "447973793139", $text ); # Alasdair Allan 
          eSTAR::GSM::send_sms( "18087690579", $text ); # Brad Cavanagh
      
      }
      
      if( $NODE_AGENTS{LT} ne 'UP' ) {
          my $text;
	  if( $NODE_AGENTS{LT} eq 'DOWN' ) {
             $text = "eSTAR Test: LT node agent down at ".ctime();
	  } else {
             $text = "eSTAR Test: Fault with LT node agent at ".ctime();
	  }
          $log->debug( $text );	  
    	  eSTAR::GSM::send_sms( "447973793139", $text ); 
	  
	  $log->debug( "Sending notification email...");
          my $mail_body = "The LT node agent is down at ".ctime() . ".\n\n";
	  my $to = 'cjm@astro.livjm.ac.uk';
	  my $cc = 'nrc@astro.livjm.ac.uk';
  
          eSTAR::Mail::send_mail( $to, "Chris Mottram"
                                  'estar@astro.ex.ac.uk',
                                  'eSTAR: LT Node Agent is DOWN',
                                  $mail_body, $cc );     
      
      }      
      if( $NODE_AGENTS{FTN} ne 'UP' ) {
          my $text;
	  if( $NODE_AGENTS{FTN} eq 'DOWN' ) {
             $text = "eSTAR Test: FTN node agent down at ".ctime();
	  } else {
             $text = "eSTAR Test: Fault with FTN node agent at ".ctime();
	  }   
	  $log->debug( $text );
    	  eSTAR::GSM::send_sms( "447973793139", $text );  

	  $log->debug( "Sending notification email...");
          my $mail_body = "The Faulkes North (FTN) node agent is down at ".ctime() . ".\n\n";
	  "********** Restarting the agent ************\n". 
          'Log in as root on the proxy (e.g. root@proxy.ogg.lco.gtn if you are an internal user) and type:'."\n\n".
          '    /etc/rc.d/init.d/tomcat restart'."\n\n".
          'The status of the node agents is polled hourly and can be checked at:'."\n\n".
	  '    http://estar9.astro.ex.ac.uk/estar/cgi-bin/status.cgi'."\n".
	  'or  http://www.estar.org.uk/network.status'."\n\n".
          "********************************************\n";
	  
	  my $to = 'telops@lcogt.net';
	  my $cc = undef;
          eSTAR::Mail::send_mail( $to, "LCO Telescope Operations"
                                  'estar@astro.ex.ac.uk',
                                  'eSTAR: FTN Node Agent is DOWN',
                                  $mail_body, $cc );     
      
      } 
      if( $NODE_AGENTS{FTS} ne 'UP' ) {
          my $text;
	  if( $NODE_AGENTS{FTS} eq 'DOWN' ) {
             $text = "eSTAR Test: FTS node agent down at ".ctime();
	  } else {
             $text = "eSTAR Test: Fault with FTS node agent at ".ctime();
	  }
	  $log->debug( $text );
    	  eSTAR::GSM::send_sms( "447973793139", $text );  
	  
	  $log->debug( "Sending notification email...");
          my $mail_body = "The Faulkes South (FTS) node agent is down at ".ctime() . ".\n\n";
	  "********** Restarting the agent ************\n". 
          'Log in as root on the proxy (e.g. root@proxy.ogg.lco.gtn if you are an internal user) and type:'."\n\n".
          '    /etc/rc.d/init.d/tomcat restart'."\n\n".
          'The status of the node agents is polled hourly and can be checked at:'."\n\n".
	  '    http://estar9.astro.ex.ac.uk/estar/cgi-bin/status.cgi'."\n".
	  'or  http://www.estar.org.uk/network.status'."\n\n".
          "********************************************\n";
	  
	  my $to = 'telops@lcogt.net';
	  my $cc = undef;
          eSTAR::Mail::send_mail( $to, "LCO Telescope Operations"
                                  'estar@astro.ex.ac.uk',
                                  'eSTAR: FTS Node Agent is DOWN',
                                  $mail_body, $cc );     	  
	  
      
      }       
  }

 
  $log->print( "Twittering start of self-check..." );
  twitter( "eSTAR has completed its self check at ".ctime() );   
  
  $log->print("Done.");  
  exit;
  
  sub twitter {
     my $twit_status = shift;
     
     #$log->debug( "Building Net::Twitter object..." );
     my $twit = new Net::Twitter( username => "eSTAR_Project", 
  			  	  password => "twitter*User" );
       
     my $twit_result;
     eval { $twit_result = $twit->update( $twit_status ); };
     if( $@ || !defined $twit_result ) {
       my $error = "$@";
       $log->error( "Error: Problem updating twitter.com with new status" );
       $log->error( "Error: $error" ) if defined $error;
    } else {
       $log->debug( "Updated status on twitter.com" ); 
    }   
    
  }    
