#!/software/perl-5.8.6/bin/perl

# Whack, don't do it again!
use strict;

# G L O B A L S -------------------------------------------------------------

# Global variables
#  $VERSION  - CVS Revision Number
#  %OPT      - Options hash for things we don't want to be persistant
#  $log      - Handle for logging object

use vars qw / $VERSION %OPT $log $config /;

# share the lookup hash across threads

# local status variable
my $status;
   
# P O D  D O C U M E N T A T I O N ------------------------------------------

=head1 NAME

C<raptor_gateway.pl> - Embedded Agent for gateway to RAPTOR/TALON

=head1 SYNOPSIS

   raptor_gateway.pl [-vers]

=head1 DESCRIPTION

C<raptor_gateway.pl> is a persitent component of the the eSTAR Intelligent 
Agent Client Software. The C<raptor_gateway.pl> is an embedded SOAP to
TCP/IP socket translation layer, which also handles external phase zero
requests for the RAPTOR/TALON telescopes.

=head1 REVISION

$Id: raptor_gateway.pl,v 1.22 2005/12/19 12:51:57 aa Exp $

=head1 AUTHORS

Alasdair Allan (aa@astro.ex.ac.uk)

=head1 COPYRIGHT

Copyright (C) 2005 University of Exeter. All Rights Reserved.

=cut

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.22 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR RAPTOR Gateway Software:\n";
      print "Agent Version $VERSION; PERL Version: $]\n";
      exit;
    }
  }
}

# ===========================================================================
# S E T U P   B L O C K
# ===========================================================================

# push $VERSION into %OPT
$OPT{"VERSION"} = $VERSION;

# E A R L Y   L O A D I N G ------------------------------------------------- 

#
# Threading code (ithreads)
# 
use threads;
use threads::shared;

#
# DN modules
#
use lib $ENV{"ESTAR_PERL5LIB"};     
use eSTAR::Logging;
use eSTAR::Error qw /:try/;
use eSTAR::Constants qw /:status/;
use eSTAR::Util;
use eSTAR::Process;
use eSTAR::Config;
use eSTAR::UserAgent;
use eSTAR::RTML;
use eSTAR::RTML::Parse;
use eSTAR::RTML::Build;

#
# Config modules
#
use Config;
use Config::Simple;
use Config::User;
use File::Spec;
use CfgTie::TieUser;

#
# General modules
#
use Config;
use Data::Dumper;
use Getopt::Long;
use Time::localtime;

my ( $name, $cmd_soap_port, $cmd_tcp_port );   
GetOptions( "name=s" => \$name,
            "soap=s" => \$cmd_soap_port,
            "tcp=s"  => \$cmd_tcp_port );

my $process_name;
if ( defined $name ) {
  $process_name = "raptor_gateway_" . $name;
} else { 
  $process_name = "raptor_gateway";
}  

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
my $process = new eSTAR::Process( $process_name );  

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process->set_version( $VERSION );

# need to use the generic "node_agent" urn instead of the process
# id in this case...
$process->set_urn( "node_agent" );

# C A T C H   S I G N A L S -------------------------------------------------

#  Catch as many signals as possible so that the END{} blocks work correctly
use sigtrap qw/die normal-signals error-signals/;

# make unbuffered
$|=1;					

# signals
$SIG{'INT'} = \&kill_agent;
$SIG{'PIPE'} = 'IGNORE';

# S T A R T   L O G   S Y S T E M -------------------------------------------

# We want a consistent look and feel to the logging, so now we've identified
# all the config and state files, lets start the logging system.

# start the log system
print "Starting logging...\n\n";
$log = new eSTAR::Logging( $process->get_process() );

# Toggle debugging in the log system, passing ESTAR__QUIET will turn off 
# debugging while ESTAR__DEBUG will turn it on.
$log->set_debug(ESTAR__DEBUG);

# Start of log file
$log->header("Starting RAPTOR Gateway: Version $VERSION");

# Check for threading
$log->debug("Config: useithreads = " . $Config{'useithreads'});
if($threads::shared::threads_shared) {
    $log->debug("Config: threads::shared loaded");
}

if ( $Config{'useithreads'} ne "define" ) {
   my $error = "FatalError: Perl mis-configured, ithreads must be enabled";
   $log->error($error);
   throw eSTAR::Error::FatalError($error, ESTAR__FATAL);      
}

# A G E N T  C O N F I G U R A T I O N ----------------------------------------

# OPTIONS FILE
# ------------

# Load in previously saved options, should be in a file in the users home 
# directory. If not there, we go with the defaults and commit basic defaults 
# to Options file

# STATE FILE
# ----------

# To a certain extent the UA must be persitant state, it needs to know about
# observations previously taken, the current unique ID (this is vital) and
# a bunch of other stuff. This is saved and stored in the users home directory 
# using Config::Simple.

$config = new eSTAR::Config(  );  

# A G E N T   S T A T E   F I L E --------------------------------------------


# HANDLE UNIQUE ID
# ----------------
  
# create a unique ID for each UA process, increment every time an UA is
# created and save it immediately to the state file, of course eventually 
# we'll run out of ints, I guess that will be bad...

my ( $number, $string );
$number = $config->get_state( "gateway.unique_process" ); 
unless ( defined $number ) {
  # $number is not defined correctly (first ever run of the program?)
  $number = 0; 
}

# increment ID number
$number = $number + 1;
$config->set_state( "gateway.unique_process", $number );
$log->debug("Setting gateway.unique_process = $number"); 
  
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

# PID OF USER AGENT
# -----------------

# log the current $pid of the user_agent.pl process to the state 
# file  so we can kill it from the SOAP server.
$config->set_state( "gateway.pid", getpgrp() );
  
# commit $pid to STATE file
$status = $config->write_state();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Can not read or write to state.dat file";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("Gateway PID: " . $config->get_state( "gateway.pid" ) );
}

# L A T E  L O A D I N G  M O D U L E S ------------------------------------- 

#
# System modules
#
use POSIX qw/:sys_wait_h/;
use Errno qw/EAGAIN/;
use Proc::Simple;
use Proc::Killfam;
use Digest::MD5 'md5_hex';
use Fcntl qw(:DEFAULT :flock);
use Errno qw(EWOULDBLOCK EINPROGRESS);
use Config::Simple;
use Config::User;

#
# Networking modules
#
use Net::Domain qw(hostname hostdomain);

#
# IO modules
#
use Socket;
use IO::Socket;
use IO::Socket::INET;
use SOAP::Lite;
use HTTP::Cookies;
use URI;
use LWP::UserAgent;
use Net::FTP;

#
# Astro modules
#
use Astro::VO::VOEvent;

#
# eSTAR modules
#
use eSTAR::RAPTOR::SOAP::Daemon;  
use eSTAR::RAPTOR::SOAP::Handler; # SOAP layer ontop of handler class

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

if ( $config->get_state("gateway.unique_process") == 1 ) {
   
   my %user_id;
   tie %user_id, "CfgTie::TieUser";
   
   # grab current user
   my $current_user = $user_id{$ENV{"USER"}};
   my $real_name = ${$current_user}{"GCOS"};
  
   # user defaults
   $config->set_option("user.user_name", $ENV{"USER"} );
   $config->set_option("user.real_name", $real_name );
   $config->set_option("user.email_address", $ENV{"USER"}."@".hostdomain());
    
   # SOAP server parameters
   $config->set_option( "soap.host", $ip );
   if ( defined $cmd_soap_port ) {
      $config->set_option( "soap.port", $cmd_soap_port );
   } else {
      $config->set_option( "soap.port", 8080 );
   }  
   
   # RAPTOR server parameters
   #$config->set_option( "raptor.host", "144.173.229.16" );
   $config->set_option( "raptor.host", "astro.lanl.gov" );
   $config->set_option( "raptor.port", 5170 );
   $config->set_option( "raptor.iamalive", 60 );
   
   # interprocess communication
   $config->set_option( "ua.user", "agent" );
   $config->set_option( "ua.passwd", "InterProcessCommunication" );

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

# ===========================================================================
# H T T P   U S E R   A G E N T 
# ===========================================================================

$log->debug("Creating an HTTP User Agent...");
 

# Create HTTP User Agent
my $lwp = new LWP::UserAgent( 
                timeout => $config->get_option( "connection.timeout" ));

# Configure User Agent                         
$lwp->env_proxy();
$lwp->agent( "eSTAR RAPTOR Gateway Daemon /$VERSION (" 
            . hostname() . "." . hostdomain() .")");

my $ua = new eSTAR::UserAgent(  );  
$ua->set_ua( $lwp );

# ===========================================================================
# M A I N   B L O C K 
# ===========================================================================

# A N O N Y M O U S   S U B - R O U T I N E S -------------------------------

# TCP/IP callback

my $tcp_callback = sub {
  my $message = shift;  
  my $thread_name = "TCP/IP";
  $log->thread2($thread_name, "Callback from TCP client...");
  $log->thread2($thread_name, "Handling broadcast message from RAPTOR");

  # This should be an RTML message, lets check.
  my $rtml;
  eval { $rtml = new eSTAR::RTML( Source => $message ) };
  if ( $@ ) {
     $log->error( "Error: $@" );
     $log->warn( "Warning: Unable to parse RAPTOR reply...");
     $log->warn( "$message");
     $log->warn( "Warning: Returning ESTAR__FAULT, exiting callback...");
     return ESTAR__FAULT;
  }
  
  unless ( defined $rtml ) {
     $log->warn( "Warning: Unable to parse RAPTOR reply...");
     $log->warn( "$message");       
     $log->warn( "Warning: Returning ESTAR__FAULT, exiting callback...");
     return ESTAR__FAULT;
  }
   
  my $type = $rtml->determine_type();
  $log->debug( "Recieved RTML message of type '$type'" );   

  unless( $type eq 'update' || $type eq 'complete' ||
          $type eq 'incomplete' || $type eq 'fail' ) {
          
     $log->warn( "Warning: Message of type $type not forwarded" );
     $log->debug( "Returning ESTAR__OK, exiting callback..." );
     return ESTAR__OK;
  }
  
  #$log->debug( Dumper( $rtml ) );
  
  # GRAB MESSAGE
  # ------------
  my $parse = new eSTAR::RTML::Parse( RTML => $rtml );
  my $host = $parse->host();
  my $port = $parse->port();
     
  # SEND TO USER_AGENT
  # ------------------
              
  # end point
  my $endpoint = "http://" . $host . ":" . $port;
  my $uri = new URI($endpoint);
  
  # create a user/passwd cookie
  my $cookie = eSTAR::Util::make_cookie( $config->get_option( "ua.user" ), 
                            $config->get_option( "ua.passwd" ) );
   
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
  $message =~ s/</&lt;/g;
      
  # grab result 
  my $result;
  eval { $result = $soap->handle_rtml(  
              SOAP::Data->name('document', $message)->type('xsd:string') ); };
  if ( $@ ) {
     $log->error("Error: Failed to connect to " . $host );
  } else {
    
     # Check for errors
     unless ($result->fault() ) {
       $log->debug("Transport Status: " . $soap->transport()->status() );
     } else {
       $log->error("Fault Code   : " . $result->faultcode() );
       $log->error("Fault String : " . $result->faultstring() );
     }
     
     my $reply = $result->result();   
     $log->debug("Got a '" . $reply . "' message from $host" ); 
  
  }     
     
  $log->debug( "Returning ESTAR__OK, exiting callback..." );
  return ESTAR__OK;
};


# subroutines used by the SOAP server need to be defined here before we 
# attempt to start the server, otherwise we'll get an undefined error 

# SOAP SERVER
# -----------

# daemon process
my $daemon;

# the thread in which we run the server process
my $listener_thread;

# anonymous subroutine which starts a SOAP server which will accept
# incoming SOAP requests and route them to the appropriate module
my $soap_server = sub {
   my $thread_name = "SOAP";
   
   # create SOAP daemon
   $log->thread($thread_name, "Starting server on port " . 
            $config->get_option( "soap.port") . " (\$tid = ".threads->tid().")");  
   $daemon = eval { new eSTAR::RAPTOR::SOAP::Daemon( 
                      LocalPort     => $config->get_option( "soap.port"),
                      Listen        => 5, 
                      Reuse         => 1 ) };   
                    
   if ($@) {
      # If we restart the node agent process quickly after a crash the port 
      # will still be blocked by the operating system and we won't be able 
      # to start the daemon. Other than the port being in use I can't see
      # why we're going to end up here.
      my $error = "$@";
      return "FatalError: $error";
   };
   
   # print some info
   $log->thread($thread_name, "SOAP server at " . $daemon->url() );

   # handlers directory
   my $handler = "eSTAR::RAPTOR::SOAP::Handler";
   
   # defined handlers for the server
   $daemon->dispatch_with({ 'urn:/node_agent' => $handler });
   $daemon->objects_by_reference( $handler );
      
   # handle it!
   $log->thread($thread_name, "Starting handlers..."  );
   $daemon->handle;

};

# S T A R T   S O A P   S E R V E R -----------------------------------------

# Spawn the SOAP server thread
$log->print("Spawning SOAP Server thread...");
$listener_thread = threads->create( $soap_server );

# I A M A L I V E  C A L L B A C K ------------------------------------------

# the thread
my $iamalive_thread;

# anonymous subroutine
my $iamalive = sub {
   my $thread_name = "IAMALIVE Thread";

   # create SOAP daemon
   $log->thread2($thread_name, "Starting IAMALIVE collection...");  
   $log->thread2($thread_name, "Pinging every " .
                 $config->get_option( "raptor.iamalive") . " seconds..." );

   # STATE FILE
   # ----------
   my $ping_file = 
      File::Spec->catfile( Config::User->Home(), '.estar', 
                           $process->get_process(), 'ping.dat' );
   
   $log->debug("Writing state to \$ping_file = $ping_file");
   #my $OBS = eSTAR::Util::open_ini_file( $obs_file );
  
   my $PING = new Config::Simple( syntax   => 'ini', 
                                  mode     => O_RDWR|O_CREAT );
                                    
   if( open ( FILE, "<$ping_file" ) ) {
      close ( FILE );
      $log->debug("Reading configuration from $ping_file" );
      $PING->read( $ping_file );
   } else {
      $log->warn("Warning: $ping_file does not exist");
   }  
   
   while( 1 ) {
      sleep $config->get_option( "raptor.iamalive" );
      $log->print( "Pinging RAPTOR at ". ctime() );
      $log->thread2( $thread_name,
          "Sending IAMALIVE (\$tid = " . threads->tid() . ")");

      $log->thread2($thread_name, 
          "Opening socket connection to RAPTOR server..." ) ;
 
      my $alive_sock = new IO::Socket::INET( 
                   PeerAddr => $config->get_option( "raptor.host" ),
                   PeerPort => $config->get_option( "raptor.port" ),
                   Proto    => "tcp",
                   Timeout  => $config->get_option( "connection.timeout" ) );

      unless ( $alive_sock ) {
     
          # we have an error
          my $error = "$!";
          chomp($error);
          $log->error( "Error: $error");
          $log->error( "Error: Cannot reach RAPTOR..." );
          next;  
      } 
 
      $log->thread2($thread_name, "Sending IAMALIVE message to RAPTOR...");
  
      # unique ID for IAMALIVE message
      $log->debug( "Retreving unique number from state file..." );
      my $number = $PING->param( 'iamalive.unique_number' ); 
 
      if ( $number eq '' ) {
         # $number is not defined correctly (first ever message?)
         $PING->param( 'iamalive.unique_number', 0 );
         $number = 0; 
      } 
      $log->debug("Generating unqiue ID: $number");      
  
      my $year = 1900 + localtime->year();
      my $month = localtime->mon() + 1;
      my $day = localtime->mday();
      my $hour = localtime->hour();
      my $min = localtime->min();
      my $sec = localtime->sec();
      
      my $timestamp = $year ."-". $month ."-". $day ."T". 
                      $hour .":". $min .":". $sec;
      $log->debug( "Generating timestamp: $timestamp");
      
      # increment ID number
      $number = $number + 1;
      $PING->param( 'iamalive.unique_number', $number );
      $log->debug('Incrementing unique number to ' . $number);
     
      my $id = $PING->param( 'soap.host' ) . "." . 
               $PING->param( 'iamalive.unique_number' );
     
      # commit ID stuff to STATE file
      my $status = $PING->save( $ping_file );           
      # build the IAMALIVE message
      my $alive =
         "<?xml version='1.0' encoding='UTF-8'?>\n" .
         '<VOEvent role="iamalive" id="' .
         'ivo://estar.ex/' . $id . '" version="1.1">' . "\n" .
         ' <Who>' . "\n" .
         '   <PublisherID>ivo://estar.ex</PublisherID>' . "\n" .
         '   <Date>' . $timestamp . '</Date>'  . "\n" .
         ' </Who>' . "\n" .
         '</VOEvent>' . "\n";

      # work out message length
      my $header = pack( "N", 7 );
      my $bytes = pack( "N", length($alive) ); 
   
      # send message                                   
      $log->debug( "Sending " . length($alive) . " bytes to " . 
                   $config->get_option( "raptor.host" ) . ":" .
                   $config->get_option( "raptor.port" ) );
                     
      $log->debug( $alive ); 
                     
      print $alive_sock $header;
      print $alive_sock $bytes;
      $alive_sock->flush();
      print $alive_sock $alive;
      $alive_sock->flush();  
  
      # Wait for IAMALIVE response
      $log->debug( "Waiting for response..." );
      my $length;
      my $bytes_read = sysread( $alive_sock, $length, 4 );  
      $length = unpack( "N", $length );
 
      $log->debug( "Message is $length characters" );
      my $response;               
      $bytes_read = sysread( $alive_sock, $response, $length); 

      close($alive_sock);
      $log->debug( "Closed ALIVE socket");
      
      # Do I get an ACK or a IAMALIVE message?
      # --------------------------------------
      my $event = new Astro::VO::VOEvent( XML => $response );
     
      if( $event->role() eq "ack" ) {
        $log->warn( "Warning: Recieved an ACK message in response");
        $log->debug( "Done." );
        
      } elsif ( $event->role() eq "iamalive" ) {
        $log->print( "Recieved a IAMALIVE message in response");
        $log->debug( "Done." );
      }  
         
      # finished ping, loop to while(1) { ]
      $log->thread2( $thread_name, "Done with IAMALIVE..." );
   }
}; 


# S T A R T   I A M A L I V E   T H R E A D ---------------------------------

# Spawn the thread that will send IAMALIVE messages to RAPTOR
$log->print("Spawning IAMAMLIVE thread...");
$iamalive_thread = threads->create( $iamalive );
$iamalive_thread->detach();

# O P E N   I N C O M I N G   C L I E N T  -----------------------------------

SOCKET: { 
       
$log->print("Opening client connection to " . 
            $config->get_option( "raptor.host") . ":" .
            $config->get_option( "raptor.port") );    
my $sock = new IO::Socket::INET( 
              PeerAddr => $config->get_option( "raptor.host" ),
              PeerPort => $config->get_option( "raptor.port" ),
              Proto    => "tcp" );

unless ( $sock ) {
    my $error = "$@";
    chomp($error);
    $log->warn("Warning: $error");
    $log->warn("Warning: Trying to reopen socket connection...");
    sleep 5;
    redo SOCKET;
};           


my $response;
$log->print( "Socket open, listening..." );
my $flag = 1;    
while( $flag ) {

   my $length;  
   my $bytes_read = sysread( $sock, $length, 4 );

   next unless defined $bytes_read;
   
   $log->debug("Recieved a packet from RAPTOR..." );
   if ( $bytes_read > 0 ) {

      $log->debug( "Recieved $bytes_read bytes on " .
                  $config->get_option( "raptor.port" ) . 
                  " from " . $sock->peerhost() );    
      
      $length = unpack( "N", $length );
      if ( $length > 512000 ) {
         $log->error( "Error: Message length is > 512000 characters" );
         $log->error( "Error: Message claims to be $length long" );
         $log->warn( "Warning: Discarding bogus message" );
      } else {   
         
         $log->debug( "Message is $length characters" );               
         $bytes_read = sysread( $sock, $response, $length); 
      
         # Filter incoming messages here, only RTML to callback thread
         if ( $response =~ /RTML/ ) {
            $log->debug( "Incoming message appears to be RMTL" );

            # callback to handle incoming RTML     
            $log->print("Detaching callback thread..." );
            my $callback_thread = 
                threads->create ( $tcp_callback, $response );
            $callback_thread->detach();    
            
         } elsif ( $response =~ /VOEvent/ ) {
            $log->debug( "Ignoring VOEvent message" );
         } else {
            $log->warn( "Warning: Message type is unknown..." );
            $log->warn( $response );
         }
         $log->debug( "Reading from socket..." );
       
      }
                      
   } elsif ( $bytes_read == 0 && $! != EWOULDBLOCK ) {
      $log->warn("Recieved an empty packet on ".
                  $config->get_option( "raptor.port" ) . 
                  " from " . $sock->peerhost() );   
      $log->warn( "Closing socket connection..." );      
      $flag = undef;
   }

   unless ( $sock->connected() ) {
      $log->warn("\nWarning: Not connected, socket closed...");
      $flag = undef;
   }    

}  
  
$log->warn( "Warning: Trying to reopen socket connection..." );
redo SOCKET;

   
}          
             
# ===========================================================================
# E N D 
# ===========================================================================

$status = $listener_thread->join() if defined $listener_thread;
$log->warn( "Warning: SOAP Thread has been terminated abnormally..." );
$log->error( $status );

# tidy up
END {
   # we must have generated an error somewhere to have gotten here,
   # run the exit code to clean(ish)ly shutdown the agent.
   $log->warn("Warning: Terminating from parent process");
   kill_agent( ESTAR__FATAL );
}

# ===========================================================================
# A S S O C I A T E D   S U B R O U T I N E S 
# ===========================================================================



# anonymous subroutine which is called everytime the user agent is
# terminated (ab)normally. Hopefully this will provide a clean exit.
sub kill_agent {
   my $from = shift;
   
   if ( $from eq ESTAR__FATAL ) {  
      $log->debug("Calling kill_agent( ESTAR__FATAL )");
      $log->warn("Warning: Shutting down agent after ESTAR__FATAL error...");
   } else {
      $log->debug("Calling kill_agent( SIGINT )");
      $log->warn("Warning: Process interrupted, possible data loss...");
   }

   # committ CONFIG and STATE changes
   $log->warn("Warning: Committing options and state changes");
   $config->reread();
   $config->write_option( );
   $config->write_state( );  
   
   # flush the error stack
   $log->debug("Flushing error stack...");
   my $error = eSTAR::Error->prior();
   $error->flush() if defined $error;
    
   # kill the agent process
   $log->print("Killing gateway processes...");

   # close out log files
   $log->closeout();
 
   # close the door behind you!   
   exit;
}                                

# T I M E   A T   T H E   B A R  -------------------------------------------

# $Log: raptor_gateway.pl,v $
# Revision 1.22  2005/12/19 12:51:57  aa
# Bug fix to raptor_gateway.pl
#
# Revision 1.21  2005/12/19 12:51:02  aa
# Bug fix to raptor_gateway.pl
#
# Revision 1.20  2005/12/19 12:40:38  aa
# Bug fix to raptor_gateway.pl
#
# Revision 1.19  2005/12/19 12:28:52  aa
# Bug fix to raptor_gateway.pl
#
# Revision 1.18  2005/12/19 12:21:47  aa
# Bug fix to raptor_gateway.pl
#
# Revision 1.17  2005/12/19 12:17:20  aa
# Bug fix to raptor_gateway.pl
#
# Revision 1.16  2005/12/19 12:15:52  aa
# Bug fix to raptor_gateway.pl
#
# Revision 1.15  2005/12/19 12:13:55  aa
# Bug fix to raptor_gateway.pl
#
# Revision 1.14  2005/12/19 12:13:33  aa
# Bug fix to raptor_gateway.pl
#
# Revision 1.13  2005/12/19 12:10:33  aa
# Bug fix to raptor_gateway.pl
#
# Revision 1.12  2005/12/19 12:09:15  aa
# Bug fix to raptor_gateway.pl
#
# Revision 1.11  2005/12/19 12:03:48  aa
# Bug fix to raptor_alert.pl and added IAMALIVE functionality to raptor_gateway.pl
#
# Revision 1.10  2005/11/02 01:23:16  aa
# RAPTOR::Util module with routine to store VOEvents
#
# Revision 1.9  2005/07/26 16:28:01  aa
# Working RAPTOR gateway
#
# Revision 1.8  2005/07/26 11:35:59  aa
# Bug fix
#
# Revision 1.7  2005/07/26 11:06:33  aa
# Bug fix
#
# Revision 1.6  2005/07/26 11:06:21  aa
# Bug fix
#
# Revision 1.5  2005/07/26 11:05:43  aa
# Working RAPTOR Gateway, messages going from eSTAR to RAPTOR transit the gateway. Immediate responses, such as scoring and rejects are pushed back. However the gateway also holds open a continous socket connection to RAPTOR for update and complete messages to transit back on
#
# Revision 1.4  2005/07/26 11:02:51  aa
# Working RAPTOR Gateway, messages going from eSTAR to RAPTOR transit the gateway. Immediate responses, such as scoring and rejects are pushed back. However the gateway also holds open a continous socket connection to RAPTOR for update and complete messages to transit back on
#
# Revision 1.3  2005/07/26 08:48:16  aa
# Updated, now working?
#
# Revision 1.2  2005/07/25 17:30:13  aa
# End of night check-in
#
# Revision 1.1  2005/07/22 17:18:06  aa
# Skeleton for RAPTOR gateway
#
# Revision 1.8  2005/05/12 16:51:56  aa
# Initial default set to LT
#
# Revision 1.7  2005/05/10 20:45:44  aa
# Fixed bogus XML problem? Not actually sure why this was occuring so added a kludge to get round it. Oh dear...
#
# Revision 1.6  2005/05/10 17:56:20  aa
# Checkpoint save, see ChangeLog
#
# Revision 1.5  2005/05/09 12:39:21  aa
# Fixed buffer overflow error in node_agent.pl
#
# Revision 1.4  2005/05/05 13:54:40  aa
# Working node_agent for LT and FTN. Changes to user_agent to support new RTML tags (see ChangeLog)
#
# Revision 1.3  2005/05/03 22:19:44  aa
# Modified node_agent.pl to work with LT only
#
# Revision 1.2  2005/04/29 11:33:46  aa
# Fixed but where the thread was silently dying because it couldn't find make_cookie() in eSTAR::Util::make_cookie() . I had this problem with the user_agent as well, and I still don't know how to fix it so I actually get proper error messages back.
#
# Revision 1.1  2005/04/29 09:29:46  aa
# Added a port of the node_agent.pl and associated modules
#
# Revision 1.27  2003/08/19 18:57:35  aa
# Created eSTAR::Util class, moved general methods to this class. Moved the
# infrastructure to support the new Astro::Catalog V3.* API. Tested user agent
# against the old node agent installed on dn2.astro.ex.ac.uk, but the JAC
# and node agent have not been tested (but should work).
#
# Revision 1.26  2003/06/27 14:23:59  aa
# Modified node_agent to use raw IP addresses rather than hostnames
#
# Revision 1.25  2003/06/24 14:23:03  aa
# Modified query_webcam() to use SOAP::MIME
#
# Revision 1.24  2003/06/11 04:45:18  aa
# Shipping to dn2.astro.ex.ac.uk
#
# Revision 1.23  2003/06/11 04:38:49  aa
# Forgot to detach()
#
# Revision 1.22  2003/06/11 04:37:10  aa
# Multi-trheading the tcp/ip callbacks in node_agent
#
# Revision 1.21  2003/06/09 04:37:48  aa
# End of night(!) check-in, added basic handling of retruned obsverations
#
# Revision 1.20  2003/06/06 15:21:58  aa
# Added quety_schedule() method
#
# Revision 1.19  2003/06/05 17:20:12  aa
# Added ldap_query method
#
# Revision 1.18  2003/06/04 17:41:27  aa
# shipping to dn2.astro.ex.ac.uk
#
# Revision 1.17  2003/06/04 17:11:53  aa
# Shipping dn2.astro.ex.ac.uk
#
# Revision 1.16  2003/06/04 16:39:10  aa
# Added read only access to lookup.dat file
#
# Revision 1.15  2003/06/04 16:30:23  aa
# Still trying to fix the fudge on returned messages
#
# Revision 1.14  2003/06/04 16:26:41  aa
# Fixed node_agent to re-fudge the IA's host and port
#
# Revision 1.13  2003/06/04 16:11:56  aa
# Ongoing HTTP::Cookie problem fixed?
#
# Revision 1.12  2003/06/04 15:47:54  aa
# Shipping to dn2.astro.ex.ac.uk
#
# Revision 1.11  2003/06/04 15:32:59  aa
# Added a use Digest::MD5 'md5_hex'
#
# Revision 1.10  2003/06/04 15:30:04  aa
# Interim checkin, added make_cookie() routine to node_agent
#
# Revision 1.9  2003/06/04 15:03:48  aa
# Moved all handle_rtml() calls to use xsd:string's and manually fudged RTML
#
# Revision 1.8  2003/06/04 07:45:24  aa
# bug fix to node_agent tcp_callback()
#
# Revision 1.7  2003/06/04 07:43:49  aa
# bug fix to node_agent tcp_callback()
#
# Revision 1.6  2003/06/04 07:40:33  aa
# Closed loop?
#
# Revision 1.5  2003/06/04 00:27:32  aa
# Interim update to ship to dn2.astro.ex.ac.uk
#
# Revision 1.4  2003/06/03 23:29:38  aa
# Interim checkin, pre-test on dn2.astro.ex.ac.uk
#
# Revision 1.3  2003/06/03 12:32:01  aa
# Added RTML host and port fudging for incoming SOAP messages
#
# Revision 1.2  2003/06/02 18:32:25  aa
# node_agent.pl now exits cleanly
#
# Revision 1.1  2003/06/02 17:59:40  aa
# Inital DN embedded agent, non-functional, problem with TCP client/server
#

