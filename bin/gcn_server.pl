#!/software/perl-5.8.6/bin/perl -w

#use strict;
#use warnings;

=head1 NAME

gcn_server - A TCP server which deals with packets from the GCN

=head1 SYNOPSIS

  make_observation

=head1 DESCRIPTION

A simple server which sits and listens for packets from the GCN, and
then hands them on to the user agent if they look important.

=head1 AUTHORS

Alasdair Allan (aa@astro.ex.ac.uk)

=head1 REVISION

$Id: gcn_server.pl,v 1.14 2005/02/15 18:37:40 aa Exp $

=head1 COPYRIGHT

Copyright (C) 2005 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut  

use vars qw / $log $process $config $VERSION  %opt /;

# local status variable
my $status;

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.14 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR Server Software:\n";
      print "GCN Server $VERSION; PERL Version: $]\n";
      exit;
    }
  }
}

# L O A D I N G -------------------------------------------------------------

# Threading code (ithreads)
use threads;
use threads::shared;
  
# eSTAR modules
use lib $ENV{ESTAR_PERL5LIB};
use eSTAR::Logging;
use eSTAR::Error qw /:try/;
use eSTAR::Constants qw /:status/;
use eSTAR::Util;
use eSTAR::Mail;
use eSTAR::Process;
use eSTAR::Config;

# GCN modules
use GCN::Constants qw(:packet_types);
use GCN::Util;

# General modules
use Config;
use IO::Socket;
use Errno qw(EWOULDBLOCK EINPROGRESS);
use Net::Domain qw(hostname hostdomain);
use Time::localtime;
use Getopt::Long;
use Data::Dumper;
use Fcntl qw(:DEFAULT :flock);
#use CfgTie::TieUser;
use SOAP::Lite;
use Digest::MD5 'md5_hex';
use URI;
use HTTP::Cookies;

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process = new eSTAR::Process( "gcn_server" );  

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process->set_version( $VERSION );

# Get date and time
my $date = scalar(localtime);
my $host = hostname;
  
# C A T C H   S I G N A L S -------------------------------------------------

#  Catch as many signals as possible so that the END{} blocks work correctly
use sigtrap qw/die normal-signals error-signals/;

# make unbuffered
#$|=1;					

# signals
#$SIG{'INT'} = exit;
#$SIG{'PIPE'} = 'IGNORE';


# L O G G I N G --------------------------------------------------------------

# Start logging
# -------------

# start the log system
$log = new eSTAR::Logging( $process->get_process() );

# Toggle debugging in the log system, passing ESTAR__QUIET will turn off 
# debugging while ESTAR__DEBUG will turn it on.
$log->set_debug(ESTAR__DEBUG);

# Start of log file
$log->header("Starting GCN Server: Version $VERSION");

# Check for threading
$log->debug("Config: useithreads = " . $Config{'useithreads'});
if($threads::shared::threads_shared) {
    $log->debug("Config: threads::shared loaded");
} 

if ( $Config{'useithreads'} ne "define" ) {
   # Perl isn't threaded, this is NOT good
   my $error = "FatalError: Perl mis-configured, ithreads must be enabled";
   $log->error($error);
   throw eSTAR::Error::FatalError($error, ESTAR__FATAL);      
}

# C O N F I G U R A T I O N --------------------------------------------------

# Load in previously saved options, should be in a file in the users home 
# directory. If not there, we go with the defaults and commit basic defaults 
# to Options file

$config = new eSTAR::Config(  );  

# S T A T E   F I L E -------------------------------------------------------

# HANDLE UNIQUE ID
# ----------------
  
# create a unique ID for each process, increment every time it is
# created and save it immediately to the state file, of course eventually 
# we'll run out of ints, I guess that will be bad...

my ( $number, $string );
$number = $config->get_state( "gcn.unique_process" ); 
unless ( defined $number ) {
  # $number is not defined correctly (first ever run of the program?)
  $number = 0; 
}

# increment ID number
$number = $number + 1;
$config->set_state( "gcn.unique_process", $number );
$log->debug("Setting gcn.unique_process = $number"); 
  
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
$config->set_state( "gcn.pid", getpgrp() );
  
# commit $pid to STATE file
$status = $config->write_state();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Can not read or write to state.dat file";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("GCN Server PID: " . $config->get_state( "gcn.pid" ) );
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

if ( $config->get_state("gcn.unique_process") == 1 ) {
  
   #my %user_id;
   #tie %user_id, "CfgTie::TieUser";
   
   # grab current user
   #my $current_user = $user_id{$ENV{"USER"}};
   #my $real_name = ${$current_user}{"GCOS"};

   # server parameters
   $config->set_option("server.host", $ip );
   $config->set_option("server.port", 5184 ); 
    
   # user defaults
   #$config->set_option("user.user_name", $ENV{"USER"} );
   #$config->set_option("user.real_name", $real_name );
   #$config->set_option("user.email_address", $ENV{"USER"}."@".hostdomain());
   #$config->set_option("user.institution", "eSTAR Project" );

   # user agentrameters
   $config->set_option("ua.host", $ip );
   $config->set_option("ua.port", 8000 );

   # interprocess communication
   $config->set_option("gcn.user", "agent" );
   $config->set_option("gcn.passwd", "InterProcessCommunication" );

   # connection options defaults
   $config->set_option("connection.timeout", 5 );
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

# C O M M A N D   L I N E   A R G U E M E N T S -----------------------------

# grab options from command line
$status = GetOptions( "host=s"     => \$opt{"host"},
                      "port=s"     => \$opt{"port"},
                      "user=s"     => \$opt{"user"},
                      "pass=s"     => \$opt{"pass"},
                      "agent=s"    => \$opt{"agent"} );

# default hostname
unless ( defined $opt{"host"} ) {
   # localhost.localdoamin
   my $ip = inet_ntoa(scalar(gethostbyname(hostname())));
   $opt{"host"} = $config->get_option("server.host");
} else{
   if ( defined $config->get_option("server.host") ) {
      $log->warn("Warning: Resetting host from" . 
              $config->get_option("server.host") . " to $opt{host}");
   }           
   $config->set_option("server.host", $opt{"host"});
}

# default port
unless( defined $opt{"port"} ) {
   # default port for the GCN server
   $opt{"port"} = $config->get_option("server.port");   
} else {
   if ( defined $config->get_option("server.port") ) {
      $log->warn("Warning: Resetting port from " . 
              $config->get_option("server.port") . " to $opt{port}");
   }
   $config->set_option("server.port", $opt{"port"});
}

# default user agent location
unless( defined $opt{"agent"} ) {
   # default host for the user agent we're trying to connect to...
   $opt{"agent"} = $config->get_option("ua.host");   
} else {
   $log->warn("Warning: Resetting port from " .
             $config->get_option("ua.host") . " to $opt{agent}");
   $config->set_option("ua.host", $opt{"agent"});
}

# default user and password location
unless( defined $opt{"user"} ) {
   $opt{"user"} = $config->get_option("gcn.user");
} else{       
   $log->warn("Warning: Resetting username from " .
             $config->get_option("gcn.user") . " to $opt{user}");
   $config->set_option("gcn.user", $opt{"user"} );
}

# default user and password location
unless( defined $opt{"pass"} ) {
   $opt{"user"} = $config->get_option("gcn.passwd");
} else{       
   $log->warn("Warning: Resetting password...");
   $config->set_option("gcn.passwd", $opt{"pass"} );
}

# T C P / I P   S E R V E R   C O D E --------------------------------------
 
# TCP/IP SERVER CALLBACK
# ----------------------

# Conenction callback for the TCP/IP socket, this grabs 
# the incoming message from the GCN and handles it before
# passing filtered observing requests to the user_agent.pl

my $tcp_callback = sub { 
   my $message = shift; 
   $log->print( "TCP/IP Callback (\$tid = ".threads->tid().")" ); 
   
   if ( $$message[0] == TYPE_IM_ALIVE ) {
       $log->print("Recieved a TYPE_IM_ALIVE packet at " . ctime() ); 
                
   } elsif ( $$message[0] >= 60 && $$message[0] <= 83 ) {
       $log->print(
          "Recieved a SWIFT (type $$message[0]) packet at " . ctime() ); 
   
      # TYPE_SWIFT_BAT_GRB_ALERT_SRC (type 60)
      # SWIFT BAT GRB ALERT message
      # --------------------------------------
      if ( $$message[0] == 60 ) {
         $log->warn( "Recieved a TYPE_SWIFT_BAT_GRB_ALERT_SRC message " );       
         $log->warn( "trig_obs_num = " . $$message[4] );       

         
      # TYPE_SWIFT_BAT_GRB_POS_ACK_SRC (type 61)
      # SWIFT BAT GRB Position Acknowledge message
      # ------------------------------------------
      } elsif ( $$message[0] == 61 ) {
         $log->warn( 
           "Recieved a TYPE_SWIFT_BAT_GRB_POS_ACK_SRC message ".
           "(trig_obs_num = " . $$message[4] .")" );       
        
         $log->warn( "Possible GRB detected at $$message[7], $$message[8]" .
                     " +- $$message[11]" );

         # convert to sextuplets
         my ( $ra, $dec, $error) = GCN::Util::convert_to_sextuplets(
                                  $$message[7], $$message[8], $$message[11] );
         $log->warn( "Possible GRB detected at $ra, $dec +- $error acrmin" ); 

   
         # check status flag
         my $soln_status = $$message[18];
         $log->warn("The solution status of this message is $$message[18]" );
        
         $log->debug("Repacking into a big-endian long...");
         my $bit_string = pack("N", $$message[18] );
         $log->debug("Unpacking to bit string...");
         $bit_string = unpack( "B32", $bit_string );

         $log->debug("Chopping up the bit string...");
         my @bits;
         foreach my $i ( 0 ... 5 ) {
            my $bit = chop( $bit_string );
            push @bits, $bit;
         }
         
         if ( $bits[0] == 1 ) {
             $log->warn( "Message: A point source was found..." );
             
         } elsif ( $bits[1] == 1 ) {  
             $log->warn( "Message: THIS TARGET IS A GAMMA RAY BURST" );
          
         } elsif ( $bits[2] == 1 ) { 
             $log->warn( "Message: This is an interesting target..." );
           
         } elsif ( $bits[3] == 1 ) { 
             $log->warn( "Message: This target is in the catalog..." );
           
         } elsif ( $bits[4] == 1 ) { 
             $log->warn( "Message: This target is an image trigger..." );
           
         } elsif ( $bits[5] == 1 ) {   
             $log->warn( "Message: THIS TARET IS NOT A GAMMA RAY BURST" );
             
         }          
                                
      # TYPE_SWIFT_BAT_GRB_POS_NACK_SRC (type 62)
      # SWIFT BAT GRB Position NOT Acknowledge message
      # ----------------------------------------------
      } elsif ( $$message[0] == 62 ) {
         $log->warn( "Recieved a TYPE_SWIFT_BAT_GRB_POS_NACK_SRC message " );
         $log->warn( "trig_obs_num = " . $$message[4] );       


         
      # TYPE_SWIFT_XRT_POSITION_SRC (type 67)
      # SWIFT XRT Position message
      # -------------------------------------
      } elsif ( $$message[0] == 67 ) {
         $log->warn( "Recieved a TYPE_SWIFT_XRT_POSITION_SRC message " );   
         $log->warn( "trig_obs_num = " . $$message[4] );       

         $log->warn( "GRB detected at $$message[7], $$message[8]" .
                     " +- $$message[11]" );

         # convert to sextuplets
         my ( $ra, $dec, $error) = GCN::Util::convert_to_sextuplets(
                                  $$message[7], $$message[8], $$message[11] );
         $log->warn( "GRB detected at $ra, $dec +- $error acrmin" ); 

         # Send a notification
         # -------------------
         
         
         #$log->print( "Sending notification email...");
         
         #my $mail_body = 
         #  "Recieved a TYPE_SWIFT_XRT_POSITION_SRC message\n" .
         #  "Position $ra, $dec +- $error acrmin\n" .
         #  "\n" .
         #  "This message indicates that the eSTAR system has recieved\n" . 
         #  "a postion update alert and is currently attempting to place\n" .
         #  "followup observations into the UKIRT queue. If you do not\n" .
         #  "recieve notification that this has been successful you may\n" .
         #  "wish to attempt manual followup.\n";
         #
         #eSTAR::Mail::send_mail( $opt{email_address}, $opt{real_name},
         #                        'aa@astro.ex.ac.uk',
         #                        'eSTAR ACK SWIFT XPT postion',
         #                        $mail_body );            

         # Make SOAP calls
         # ---------------


         # build endpoint
         my $endpoint = "http://" . $config->get_option("ua.host") . 
                        ":" . $config->get_option("ua.port");
         my $uri = new URI($endpoint);         
         
         $log->debug("Connecting to server at $endpoint");

         # create authentication cookie
         $log->debug("Creating authentication token");
         my $cookie =  eSTAR::Util::make_cookie( 
           $config->get_option("gcn.user"), $config->get_option("gcn.passwd") );
         
                      
         $log->debug("Placing it in the cookie jar...");
         my $cookie_jar = HTTP::Cookies->new();
         $cookie_jar->set_cookie(0, 
                         user => $cookie, '/', $uri->host(), $uri->port()); 
                                   
         $log->print("Building SOAP client...");
 
         # create SOAP connection
         my $soap = new SOAP::Lite();
         $soap->uri('urn:/user_agent'); 
         $soap->proxy($endpoint, cookie_jar => $cookie_jar);

 
         
         # Submit an inital burst followup block
         # -------------------------------------
         $log->print("Making a SOAP conncetion for InitialBurstFollowup...");
         eval { $result = $soap->new_observation( 
                              user     => $config->get_option("gcn.user"),
                              pass     => $config->get_option("gcn.passwd"),
                              type     => 'InitialBurstFollowup',
                              ra       => $ra,
                              dec      => $dec,
                              followup => 0,
                              exposure => 30,
                              passband => "k98" ); };
         if ( $@ ) {
            $log->warn("Warning: Problem connecting to user agent");
            $log->error("Error: $@");
            $log->error("Error: Aborting submission of observations");
            $log->print("Connection closed");      
           
         } else {
            $log->print("Connection closed");      
         
            # Submit an burst followup block
            # -------------------------------------
            $log->print("Making a SOAP conncetion for BurstFollowup...");
            eval { $result = $soap->new_observation( 
                              user     => $config->get_option("gcn.user"),
                              pass     => $config->get_option("gcn.passwd"),
                              type     => 'BurstFollowup',
                              ra       => $ra,
                              dec      => $dec,
                              followup => 0,
                              exposure => 30,
                              passband => "k98" ); };
            if ( $@ ) {
               $log->warn("Warning: Problem connecting to user agent");
               $log->error("Error: $@");
            } else {
               $log->print("Connection closed");      
            } 
         
         }
        
      # TYPE_SWIFT_XRT_CENTROID_SRC (type 71)
      # SWIFT XRT Position NOT Ack message (Centroid Error)
      # ---------------------------------------------------
      } elsif ( $$message[0] == 71 ) {
         $log->warn( "Recieved a TYPE_SWIFT_XRT_CENTROID_SRC message " );  
         $log->warn( "trig_obs_num = " . $$message[4] );       


         
      
      }
   
   } else {
       $log->print( "Recieved a packet of type $$message[0] at " . ctime() ); 
   
   }
   
   
   
};

   
# TCP/IP SERVER
# -------------

# daemon process
my $sock;

# the thread in which we run the server process
my $tcpip_thread;

# anonymous subroutine which starts a SOAP server which will accept
# incoming SOAP requests and route them to the appropriate module
my $tcpip_server = sub {
   my $thread_name = "TCP/IP Thread"; 
  
   $log->thread2($thread_name, "Starting server on " . 
      $config->get_option( "server.host") . ":" .
      $config->get_option( "server.port") . " (\$tid = ".threads->tid().")");  
   
   my $sock = new IO::Socket::INET( 
                  LocalHost => $config->get_option("server.host"),
                  LocalPort => $config->get_option("server.port"),
                  Proto     => 'tcp',
                  Listen    => 1,
                  Reuse     => 1,
                  Timeout   => 300,
                  Type      => SOCK_STREAM ); 
   
   unless ( $sock ) {
      # If we restart the node agent process quickly after a crash the port 
      # will still be blocked by the operating system and we won't be able 
      # to start the daemon. Other than the port being in use I can't see
      # why we're going to end up here.
      my $error = "$@";
      chomp($error);
      return "FatalError: $error";
   };                    

   # wait until socket opens
   $log->thread2( $thread_name,  "Reading unbuffered from TCP/IP socket... " );
   while ( my $listen = $sock->accept() ) {
    
      $listen->blocking(0);
        
       my $status = 1;    
       while( $status ) {
    
          my $length = 160; # GCN packets are 160 bytes long
          my $buffer;  
          my $bytes_read = sysread( $listen, $buffer, $length);
     
          next unless defined $bytes_read;
          
          $log->thread2("\n$thread_name", "Recieved a packet..." );
          if ( $bytes_read > 0 ) {
 
            $log->debug( "Recieved $bytes_read bytes on $opt{port} from " . 
                         $listen->peerhost() );    
                      
             my @message = unpack( "N40", $buffer );
             if ( $message[0] == TYPE_KILL_SOCKET ) {
                $log->print(
                   "Recieved a TYPE_KILL_SOCKET packet at " . ctime() );
                $log->warn("Warning: Killing connection...");
                $status = undef;
             } 
             
             $log->debug( "Echoing $bytes_read bytes to " . 
                       $listen->peerhost() );
             $listen->flush();
             print $listen $buffer;
             $listen->flush();
             
              # callback to handle incoming RTML     
             $log->thread2($thread_name, "Detaching thread..." );
             my $callback_thread = 
                    threads->create ( $tcp_callback, \@message );
             $callback_thread->detach(); 
                             
          } elsif ( $bytes_read == 0 && $! != EWOULDBLOCK ) {
             $log->warn("Recieved an empty packet on $opt{port} from " . 
                         $listen->peerhost() );   
             $listen->flush();
             print $listen $buffer;
             $log->warn( 
                 "Echoing empty packet to " . $listen->peerhost() );
             $listen->flush();
             $log->warn( "Closing socket connection..." );      
             $status = undef;
          }
       
          unless ( $listen->connected() ) {
             $log->warn("\nWarning: Not connected, socket closed...");
             $status = undef;
          }    
    
       }   
       #$log->warn("Warning: Closing socket connection to client");
       #close ($listen);
    
   } 
   
   return $@;

};  

# M A I N   L O O P ---------------------------------------------------------

my $exit_code;
while ( !$exit_code ) {

   # Spawn the inital TCP/IP server thread
   $log->print("Spawning TCP/IP Server thread...");
   $tcpip_thread = threads->create( $tcpip_server );
  
   my $thread_exit_code = $tcpip_thread->join() if defined $tcpip_thread;
   $log->warn( "Warning: Server exiting... ");

   # respawn on timeout
   if ( $thread_exit_code eq "accept: timeout" ) {
      $log->warn( "Warning: The socket has timed out waiting for connection" );
      #$log->warn( "Warning: Respawing server..." );
      
   } else { 
      $exit_code = 1;
      $log->error( "Error: $thread_exit_code" );
   }  
}

$log->print("Exiting...");    
exit; 
