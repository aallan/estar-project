#!/software/perl-5.8.6/bin/perl
  
  #use strict;
  
  use vars qw /$VERSION/;

  $VERSION = '0.1';

  #
  # General modules
  use Getopt::Long;
  use SOAP::Lite;
  use Digest::MD5 'md5_hex';
  use Fcntl qw(:DEFAULT :flock);
  use URI;
  use HTTP::Cookies;
  use Getopt::Long;
  use Net::Domain qw(hostname hostdomain);
  use Socket;
  use Net::FTP;
  use File::Spec;
  use Time::localtime;
  
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

  my $process = new eSTAR::Process( "test_servers" );  
  $process->set_version( $VERSION );
  print "Starting logging...\n\n";
  $log = new eSTAR::Logging( $process->get_process() );
  $log->header("Starting Server Test: Version $VERSION");
  my $config = new eSTAR::Config(  );  
  

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
     $config->set_option("user.user_name", "aa" );
     $config->set_option("user.real_name", "Alasdair Allan" );
     $config->set_option("user.email_address", 'aa@astro.ex.ac.uk');
     $config->set_option("user.institution", "University of Exeter" );
     $config->set_option("user.notify", 1 );

     # node port
     $config->set_option("dn.default_port", 8080 );

     # connection options defaults
     $config->set_option("connection.timeout", 20 );
     $config->set_option("connection.proxy", 'NONE'  );
  
     # mail server
     $config->set_option("mailhost.name", 'butch' );
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

# K N O W N   N O D E S ---------------------------------------------------

  # list of "default" known nodes  
  $config->set_option( "nodes.UKIRT", "estar.ukirt.jach.hawaii.edu:8080" );
  $config->set_option( "nodes.LT", "estar.astro.ex.ac.uk:8078" );
  $config->set_option( "nodes.FTN", "estar.astro.ex.ac.uk:8077" );
  $config->set_option( "nodes.FTS", "estar.astro.ex.ac.uk:8079" );
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
        $content = $content . "$NAMES[$i] $dn_host $dn_port DOWN\n"
     }
  
     if ( defined $result ) {     
        # Check for errors
        $log->debug("Transport Status: " . $soap->transport()->status() );
        unless ($result->fault() ) {
           $log->print( "$NAMES[$i] ($dn_host): " . $result->result() );
           print SERIAL "$NAMES[$i] $dn_host $dn_port UP\n";
           $content = $content . "$NAMES[$i] $dn_host $dn_port UP\n";
        } else {
           $log->error( "Error ($dn_host): ". $result->faultcode() );
           $log->error( "Error ($dn_host): " . $result->faultstring() );
           print SERIAL "$NAMES[$i] $dn_host $dn_port FAULT\n";
           $content = $content ."$NAMES[$i] $dn_host $dn_port FAULT\n";
        }
     }  
  }
  
# K N O W N   A G E N T S  --------------------------------------------------

  # list of "default" known nodes  
  $config->set_option( "useragents.GRB", "estar2.astro.ex.ac.uk:8000" );
  $config->set_option( "useragents.EXO-PLANET", "estar.astro.ex.ac.uk:8000" );
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
        $content = $content . "$UA_NAMES[$i] $ua_host $ua_port DOWN\n";
     }
  
     if ( defined $result ) {     
        # Check for errors
        $log->debug("Transport Status: " . $soap->transport()->status() );
        unless ($result->fault() ) {
           $log->print( "$UA_NAMES[$i] ($ua_host): " . $result->result() );
           print SERIAL "$UA_NAMES[$i] $ua_host $ua_port UP\n";
           $content = $content . "$UA_NAMES[$i] $ua_host $ua_port UP\n";
        } else {
           $log->error( "Error ($ua_host): ". $result->faultcode() );
           $log->error( "Error ($un_host): " . $result->faultstring() );
           print SERIAL "$UA_NAMES[$i] $ua_host $ua_port FAULT\n";
           $content = $content . "$UA_NAMES[$i] $ua_host $ua_port FAULT\n";
        }
     }  
  }  


# K N O W N   B R O K E R S -------------------------------------------------

  # list of "default" known nodes  
  $config->set_option( "brokers.eSTAR", "estar.astro.ex.ac.uk:9099" );
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
        $content = $content . "$BROKER_NAMES[$i] $broker_host $broker_port DOWN\n";
     }
  
     if ( defined $result ) {     
        # Check for errors
        $log->debug("Transport Status: " . $soap->transport()->status() );
        unless ($result->fault() ) {
           $log->print( "$BROKER_NAMES[$i] ($broker_host): " . $result->result() );
           print SERIAL "$BROKER_NAMES[$i] $broker_host $broker_port UP\n";
           $content = $content . "$BROKER_NAMES[$i] $broker_host $broker_port UP\n";
        } else {
           $log->error( "Error ($broker_host): ". $result->faultcode() );
           $log->error( "Error ($un_host): " . $result->faultstring() );
           print SERIAL "$BROKER_NAMES[$i] $broker_host $broker_port FAULT\n";
           $content = $content . "$BROKER_NAMES[$i] $broker_host $broker_port FAULT\n";
        }
     }  
  }  
    

  $content = $content . "\nLatest status at information available at " .
                        "http://www.estar.org.uk/network.status\n";
        
    
# C L E A N   U P -----------------------------------------------------------
  
  $log->debug("\nClosing output file...");  
  close(SERIAL);  
  $log->debug("Freeing flock()...");  
  
# N O T I F Y   P E O P L  E ------------------------------------------------

  $log->print("Opening FTP connection to lion.drogon.net...");  
  my $ftp = Net::FTP->new( "lion.drogon.net", Debug => 0 );
  $log->debug("Logging into estar account...");  
  $ftp->login( "estar", "tibileot" );
  $ftp->cwd( "www.estar.org.uk/docs" );
  $log->debug("Transfering status file...");  
  $ftp->put( $file, "network.status" );
  $ftp->quit();
  
  $log->print( "Sending notification email...");
  
  my $mail_body = $content;
  
  my $cc = undef;
  if ( ctime() =~ "18:00" ) {
     # Cc estar-devel mailing list once per day
     $cc = 'estar-devel@estar.org.uk';
  }   
  
  eSTAR::Mail::send_mail( $config->get_option("user.email_address"), 
                          $config->get_option("user.real_name"),
                          'aa@astro.ex.ac.uk',
                          'eSTAR Network Status',
                          $mail_body, $cc );              
  
  $log->debug("Done.");  
  exit;
