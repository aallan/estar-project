#!/Software/perl-5.8.8/bin/perl

use strict;
use vars qw / $VERSION $log /;

use threads;
use threads::shared;

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR User Agent Software:\n";
      print "Event Monitor $VERSION; PERL Version: $]\n";
      exit;
    }
  }
}

# L O A D I N G -------------------------------------------------------------

# eSTAR modules
use lib $ENV{ESTAR_PERL5LIB};
use eSTAR::Logging;
use eSTAR::Constants qw /:status/; 
use eSTAR::Config;
use eSTAR::Util;
use eSTAR::Process;
use eSTAR::UserAgent;
use eSTAR::Mail;

# general modules
use SOAP::Lite;
use POSIX qw(:sys_wait_h);
use Errno qw(EAGAIN);
use Errno qw(EWOULDBLOCK EINPROGRESS);
use Net::Domain qw(hostname hostdomain);
use Fcntl qw(:DEFAULT :flock);
use Time::localtime;
use Digest::MD5 'md5_hex';
use URI;
use LWP::UserAgent;
use HTTP::Cookies;
use Sys::Hostname;
use Config::User;
use Getopt::Long;
use Data::Dumper;
use Config;
use Socket;
use Data::Dumper;
use Carp;

use Starlink::AST;
use Starlink::AST::Tk;

use Astro::FITS::CFITSIO;
use Astro::FITS::Header::CFITSIO;

use Astro::VO::VOEvent;
use XMLRPC::Lite;
use XMLRPC::Transport::HTTP;

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
my $process = new eSTAR::Process( "event_client_plastic" );  

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process->set_version( $VERSION );

# turn off buffering
$| = 1;

# Get date and time
my $date = scalar(localtime);
my $host = hostname;

# L O G G I N G --------------------------------------------------------------

# Start logging
# -------------

# start the log system
$log = new eSTAR::Logging( $process->get_process() );

# Toggle debugging in the log system, passing ESTAR__QUIET will turn off 
# debugging while ESTAR__DEBUG will turn it on.
$log->set_debug(ESTAR__DEBUG);

# Start of log file
$log->header("Starting Event Client: Version $VERSION");


# C O N F I G U R A T I O N --------------------------------------------------

# Load in previously saved options, should be in a file in the users home 
# directory. If not there, we go with the defaults and commit basic defaults 
# to Options file

my $config = new eSTAR::Config(  );  


# S T A T E   F I L E -------------------------------------------------------

# HANDLE UNIQUE ID
# ----------------

my ( $number, $string );
$number = $config->get_state( "ec.unique_process" ); 
unless ( defined $number ) {
  # $number is not defined correctly (first ever run of the program?)
  $number = 0; 
}

# increment ID number
$number = $number + 1;
$config->set_state( "ec.unique_process", $number );
$log->debug("Setting ec.unique_process = $number"); 
  
# commit ID stuff to STATE file
my $status = $config->write_state();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Can not read or write to state.dat file";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("Unique process ID: updated state.dat file" );
}

# PID OF PROGRAM
# --------------

# log the current $pid of the user_agent.pl process to the state 
# file  so we can kill it from the SOAP server.
$config->set_state( "ec.pid", getpgrp() );
  
# commit $pid to STATE file
$status = $config->write_state();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Can not read or write to state.dat file";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("Event Client PID: " . $config->get_state( "ec.pid" ) );
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

if ( $config->get_state("ec.unique_process") == 1 ) {
  
   # local XMLRPC server
   $config->set_option("ec.host", $ip );
   $config->set_option("ec.port", 9001 );
     
   # event broker
   $config->set_option("eb.host", "144.173.229.22" );
   $config->set_option("eb.port", 8099 );

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

# H T T P   U S E R   A G E N T ----------------------------------------------

$log->debug("Creating an HTTP User Agent...");
 
# Create HTTP User Agent
my $lwp = new LWP::UserAgent( 
                timeout => $config->get_option( "connection.timeout" ));

# Configure User Agent                         
$lwp->env_proxy();
$lwp->agent( "eSTAR Event Monitor /$VERSION (" . hostname() . ")" );

my $ua = new eSTAR::UserAgent(  );  
$ua->set_ua( $lwp );


# C O M M A N D   L I N E   A R G U E M E N T S -----------------------------

my ( %opt, %observation );

# grab options from command line
my $status = GetOptions( 
                         "host=s"     => \$opt{"host"},
                         "port=s"     => \$opt{"port"}
	               );

# default hostname
unless ( defined $opt{"host"} ) {
   my $ip = inet_ntoa(scalar(gethostbyname(hostname())));
   $opt{"host"} = $config->get_option("eb.host");
} else{
   if ( defined $config->get_option("eb.host") ) {
      $log->warn("Warning: Reseting host from " . 
              $config->get_option("eb.host") . " to $opt{host}");
   }           
   $config->set_option("eb.host", $opt{"host"});
}

# default port
unless( defined $opt{"port"} ) {
   $opt{"port"} = $config->get_option("eb.port");   
} else {
   if ( defined $config->get_option("eb.port") ) {
      $log->warn("Warning: Reseting port from " . 
              $config->get_option("eb.port") . " to $opt{port}");
   }
   $config->set_option("eb.port", $opt{"port"});
}

# D A E M O N -------------------------------------------------------------

$log->print("Starting Plastic Daemon...");
my $daemon = threads->new( \&daemon_process );
$daemon->detach;

# R P C -------------------------------------------------------------------

$log->debug("Getting XMLRPC endpoint from .plastic file...");
# Grab an RPC endpoint for the ACR
my $file = File::Spec->catfile( Config::User->Home(), ".plastic" );
croak( "Unable to open file $file" ) unless open(PREFIX, "<$file" );

$/ = "\n"; # shouldn't be necessary?
my @prefix = <PREFIX>;
close( PREFIX );

my $endpoint;
foreach my $i ( 0 ... $#prefix ) {
  if ( $prefix[$i] =~ "plastic.xmlrpc.url" ) {
     my @line = split "=", $prefix[$i];
     chomp($line[1]);
     $endpoint = $line[1];
     $endpoint =~ s/\\//g;
  }    
}
$log->debug("Plastic Hub Endpoint: $endpoint");
my $rpc = new XMLRPC::Lite();
$rpc->proxy($endpoint);

# R E G I S T E R ----------------------------------------------------------

$log->debug("Waiting for server to start...");
sleep(5);

my @list;
$list[0] = 'ivo://votech.org/test/echo';
$list[1] = 'ivo://votech.org/info/getName';
$list[1] = 'ivo://votech.org/info/getIVORN';
$list[2] = 'ivo://votech.org/info/getVersion';
$list[3] = 'ivo://votech.org/info/getIconURL';
$list[4] = 'ivo://votech.org/hub/event/ApplicationRegistered';
$list[5] = 'ivo://votech.org/hub/event/ApplicationUnregistered';
$list[6] = 'ivo://votech.org/hub/event/HubStopping';
$list[7] = 'ivo://votech.org/hub/Exception';
#$list[8] = 'ivo://votech.org/sky/pointAtCoords';

$log->print("Registering with Plastic hub" );
my $register;
eval{ $register = $rpc->call( 'plastic.hub.registerXMLRPC', 
                              'eSTAR Event Client', \@list, "http://". 
			      $config->get_option("ec.host").":".
			      $config->get_option("ec.port")."/" ); };

if( $@ ) {
   my $error = "$@";
   croak( "Error: $error" );
}   

my $id;
unless( $register->fault() ) {
   $id = $register->result();
   $log->debug("Got Plastic ID of $id");
} else {
   croak( "Error: ". $register->faultstring );
}


# E V E N T   C L I E N T --------------------------------------------------

my $event_client = threads->new( \&event_process );
$event_client->detach;

# M A I N  L O O P ---------------------------------------------------------

while(1) { };

exit;

# E V E N T   C L I E N T ###################################################

sub event_process {

   my $sock;
   SOCKET: { 

     $log->print("Opening client connection to $opt{host}:$opt{port}");    
     my $sock = new IO::Socket::INET( PeerAddr => $opt{host},
                                   PeerPort => $opt{port},
                                   Proto    => "tcp" );

     unless ( $sock ) {
         my $error = "$@";
         chomp($error);
         $log->warn("Warning: $error");
         $log->warn("Warning: Trying to reopen socket connection...");
         sleep 5;
         redo SOCKET;
     }    
              
     my $message;
     $log->print("Socket open, listening...");
     my $flag = 1;    
     while( $flag ) {

        my $length;  
        my $bytes_read = read( $sock, $length, 4 );

        next unless defined $bytes_read;
   
        $log->debug("Recieved a packet from $opt{host}...");
        if ( $bytes_read > 0 ) {

           $log->debug( "Recieved $bytes_read bytes on $opt{port} from ".
	                 $sock->peerhost() );
          
           $length = unpack( "N", $length );
           if ( $length > 512000 ) {
               $log->error("Error: Message length is > 512000 characters");
               $log->error("Error: Message claims to be $length long");
               $log->warn("Warning: Discarding bogus message");
           } else {   
         
              $log->print("Message is $length characters");               
              $bytes_read = read( $sock, $message, $length); 
      
              $log->debug("Read $bytes_read characters from socket");
      
              # callback to handle incoming Events     
	      #print $message . "\n";
       
              my $object = new Astro::VO::VOEvent( XML => $message );
	 
	      my $response;
	      if ( $object->role() eq "iamalive" ) {
	         $log->debug("Echoing 'iamalive' packet..");
	         $response = $message;
              } else {
	         $log->debug("Responding with an 'ack' packet...");
	         $response =
                 "<?xml version='1.0' encoding='UTF-8'?>"."\n".
                 '<VOEvent role="ack" id="ivo://estar.ex/" version="1.1">'."\n".
                 ' <Who>'."\n".
                 '   <PublisherID>ivo://estar.ex</PublisherID>'."\n".
                 ' </Who>'."\n".
                 '</VOEvent>'."\n";
	      }
	 
	      my $bytes = pack( "N", length($response) ); 
              $log->debug("Sending " . length($response) . " bytes to socket");
              print $sock $bytes;
              $sock->flush();
              print $sock $response;
	      #print "$response\n";
              $sock->flush(); 
	      
	      if ( $object->role() eq "observation" ||
	           $object->role() eq "test" ) {
		   
		my $ra = $object->ra();
		my $dec = $object->dec();
		if ( defined $ra && defined $dec ) {
		
                   $log->print("Dispatching event to Plastic hub" );
                   my $status;
		   my @array;
		   push @array, $ra;
		   push @array, $dec;
                   eval{ $status = $rpc->call( 'plastic.hub.request', 
                             "http://". 
			      $config->get_option("ec.host").":".
			      $config->get_option("ec.port")."/",
			      "ivo://votech.org/sky/pointAtCoords",
			      \@array ); };

                   if( $@ ) {
                      my $error = "$@";
                      croak( "Error: $error" );
                   }   
                   unless( $status->fault() ) {
                      my %hash = %{$status->result()};
		      if ( scalar %hash ) {
		        $log->print("Submitted event to hub...");
			print Dumper( %hash );
			foreach my $key ( sort keys %hash ) {
			  $log->debug( "$key => $hash{$key}");
		        }
		      } else {
		         $log->error(
			    "Error: There were no registered applications"); 
		      }	 
                   } else {
                      croak( "Error: ". $status->faultstring );
                   }		  
		

	        } else {
		   $log->warn( "Warning: Unable to understand the RA&Dec" );
		   $log->warn( $message );
		}
		   
              }		
	      $log->print("Done.");
           }
                      
        } elsif ( $bytes_read == 0 && $! != EWOULDBLOCK ) {
          $log->warn( "Warning: Recieved an empty packet on $opt{port} from ".
	              $sock->peerhost() );   
          $log->warn( "Warning: Closing socket connection..." );      
          $flag = undef;
        } elsif ( $bytes_read == 0 ) {
          $log->warn( "Warning: Recieved an empty packet on $opt{port} from ".
	              $sock->peerhost() );   
          $log->warn( "Warning:Closing socket connection..." );      
          $flag = undef;   
        }
   
        unless ( $sock->connected() ) {
         $log->warn( "Warning: Not connected, socket closed...");
         $flag = undef;
        } 
	   
     }  
  
     $log->warn("Warning: Trying to reopen socket connection...");
     redo SOCKET;
   };  

}


# D A E M O N   S E R V E R   T H R E A D ###################################

sub daemon_process {

  my $name = "Daemon";
  $log->thread2($name, "Starting daemon process (\$tid = ".threads->tid().")");
  my $daemon;
  eval { $daemon = XMLRPC::Transport::HTTP::Daemon
   -> new (LocalPort => $config->get_option("ec.port"), 
  	   LocalHost => $config->get_option("ec.host") )
   -> dispatch_to( 'perform' );  };
  if ( $@ ) {
     my $error = "$@";
     croak( "Error: $error" );
  }		
  
  my $url = $daemon->url();   
  $log->thread2($name, "Starting XMLRPC server at $url");

  eval { $daemon->handle; };  
  if ( $@ ) {
    my $error = "$@";
    croak( "Error: $error" );
  }  
  
  $log->thread2($name, "Server started sucessfully, waiting...");
  while(1) { };

}

# P L A S T I C   D A E M O N  C A L L B A C K S ---------------------------

sub perform {
  Plastic::perform( @_ );
}  

package Plastic;

use Data::Dumper;

my $log;

sub perform {
  my @args = @_;
  $log = eSTAR::Logging::get_reference();

  my $name = "Plastic";
  $log->thread($name, "In perform()");
  #print Dumper( @args );
  
  if ($args[2] eq 'ivo://votech.org/test/echo' ) {
     $log->thread($name, 'ivo://votech.org/test/echo' );
     return $args[3];
  }
  if ($args[2] eq 'ivo://votech.org/info/getName' ) {
     $log->thread($name, 'ivo://votech.org/test/getName' );
     return "eSTAR Event Client";
  }
  if ($args[2] eq 'ivo://votech.org/info/getIvorn' ) {
     $log->thread($name, 'ivo://votech.org/test/getIvorn' );
     return "ivo://uk.org.estar";
  }   
  if ($args[2] eq 'ivo://votech.org/info/getVersion' ) {
     $log->thread($name, 'ivo://votech.org/test/getVersion' );
     return "0.4";
  }
  if ($args[2] eq 'ivo://votech.org/info/getIconURL' ) {
     $log->thread($name, 'ivo://votech.org/test/IconURL' );
     return "http://www.estar.org.uk/png/estar-e-trans.png";
  }   
  if ($args[2] eq 'ivo://votech.org/hub/event/ApplicationRegistered' ) {
     $log->thread($name, 'ivo://votech.org/test/ApplicationRegistered' );
     return 1;
  }   
  if ($args[2] eq 'ivo://votech.org/hub/event/ApplicationUnregistered' ) {
     $log->thread($name, 'ivo://votech.org/test/ApplicationUnregistered' );
     return 1;
  }   
  if ($args[2] eq 'ivo://votech.org/hub/event/HubStopping' ) {
     $log->thread($name, 'ivo://votech.org/test/HubStopping' );
     $log->warn("Warning: Hub Stopping Message" );
  }   
  if ($args[2] eq 'ivo://votech.org/hub/Exception' ) {
     $log->thread($name, 'ivo://votech.org/test/Exception' );
     $log->warn("Warning: Hub Exception Message" );
     $log->warn("Warning: $args[3]");
     return 1;
  }   
  
  #if($args[2] eq 'ivo://votech.org/sky/pointAtCoords' ) {
  #   $log->thread($name, 'ivo://votech.org/testpointAtCoords' );
  #   print Dumper( $args[3] );
  #   return 1;
  #}  
  
}
