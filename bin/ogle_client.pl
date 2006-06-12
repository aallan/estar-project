#!/software/perl-5.8.6/bin/perl

use strict;
use vars qw / $VERSION $log /;

use threads;
use threads::shared;

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.8 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR OGLE Client Software:\n";
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

use eSTAR::Broker::Util;

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

use Astro::Coords;
use Astro::VO::VOEvent;
use XML::Document::Transport;


# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
my $process = new eSTAR::Process( "ogle_event_client" );  

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
$log->header("Starting OGLE Event Client: Version $VERSION");


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

   # interprocess communication
   $config->set_option("ec.user", "agent" );
   $config->set_option("ec.passwd", "InterProcessCommunication" );
        
   # user agent
   $config->set_option("ua.host", 'exo.astro.ex.ac.uk' );
   $config->set_option("ua.port", 8000 );
     
   # event broker
   $config->set_option("eb.host", $ip );
   $config->set_option("eb.port", 8099 );

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
                         "port=s"     => \$opt{"port"},
                         
                         "user=s"     => \$opt{"user"},
                         "pass=s"     => \$opt{"pass"},,
                         
                         "start=s"    => \$opt{"start"},
                         "end=s"      => \$opt{"end"}
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


# default user and password location
unless( defined $opt{"user"} ) {
   $opt{"user"} = $config->get_option("ec.user");
} else{       
   if ( defined $config->get_option("ec.user") ) {
      $log->warn("Warning: Resetting username from " .
                $config->get_option("ec.user") . " to $opt{user}");
      $config->set_option("ec.user", $opt{"user"} );
   }
}

# default user and password location
unless( defined $opt{"pass"} ) {
   $opt{"pass"} = $config->get_option("ec.passwd");
} else{       
   if ( defined $config->get_option("ec.passwd") ) {
      $log->warn("Warning: Resetting password...");
      $config->set_option("ec.passwd", $opt{"pass"} );
   }
}


# E V E N T   C L I E N T --------------------------------------------------

#my $event_client = threads->new( \&event_process );
#$event_client->detach;

# M A I N  L O O P ---------------------------------------------------------

event_process();
#while(1) { };

exit;

# E V E N T   C L I E N T ###################################################

sub incoming_callback {
   my $message = shift;
   
   $log->thread("Client", "Callback from TCP client at " . ctime() . "...");
   $log->thread("Client", "Handling broadcast message from $opt{host}:$opt{port}");
   my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
   my $alert = File::Spec->catfile( $state_dir, "alert.log" );
     
   # It really, really should be a VOEvent message
   $log->debug( "Testing to see whether we have a VOEvent document..." );
   my $event;
   if ( $message =~ /VOEvent/ ) {
      eval { $event = new Astro::VO::VOEvent( XML => $message ); };
      if ( $@ ) {
         my $error = "$@";
         chomp( $error );
         $log->error( "Error: $error" );
         $log->error( "Warning: Returning ESTAR__FAULT" );
         return ESTAR__FAULT;
      } else {  
         $log->debug( "This looks like a VOEvent document..." );
      }
   }   	 
   
   # Check the ID of current message
   
   my $id;
   eval { $id = $event->id();};
   if ( $@ ) {
      my $error = "$@";
      chomp( $error );
      $log->error( "Error: $error" );
      $log->error( "Warning: Returning ESTAR__FAULT" );
      return ESTAR__FAULT;
   } 

   unless( $id =~ "pl.edu.ogle" ) {
      $log->debug("Event ID is $id");
      $log->print("Discarding event...");
      $log->thread("Client", "Done.");  
      return ESTAR__OK;
   }   
   my ($ivorn, $name ) = split "#", $id;
 
   unless( $name =~ "OGLE" ) {
      $log->warn("Warning: Event ID is $id");
      $log->warn("Warning: Not an OGLE EWS event?");
      $log->warn( $message );
      my $log->thread( "Client", "Done." );
      return ESTAR__OK;
   }
   
   # Check we haven't seen that message before?
   unless ( open ( ALERT, "+>>$alert" )) {
      my $error = "Error: Can not open $alert in read/append access mode"; 
      $log->error( $error );
      my $log->thread( "Client", "Done." );
      return ESTAR__FATAL;   
   } else {
      unless ( flock( ALERT, LOCK_EX ) ) {
   	my $error = "Warning: unable to acquire exclusive lock: $!";
   	$log->error( $error );
        my $log->thread( "Client", "Done." );
        return ESTAR__FATAL; 
      } else {
   	$log->debug("Acquiring exclusive lock...");
      }
        
      $log->debug("Reading from $alert");
      my @ids;
      {
         local $/ = "\n";  # I shouldn't have to do this?
         @ids = <ALERT>;
      }   
      # use Data::Dumper; print "\@ids = " . Dumper( @ids );

      foreach my $i ( 0 ... $#ids ) {
         if( $ids[$i] eq $id ) {
	    $log->warn( "Warning: Found duplicate ID in $alert");
	    $log->warn( "Warning: Not submitting observations...");
            my $log->thread( "Client", "Done." );
            return ESTAR__FAULT; 
	 }
      }
      
      # Commit the ID
      $log->debug("Writing ID to $alert");
      print ALERT "$id\n";
     
      # close ALERT log file
      $log->debug("Closing $alert");
      close(ALERT);  
      
   }	
        
   # Parse the message
   my ( $ra, $dec );
   eval { $ra = event->ra(); };
   if ( $@ ) {
      my $error = "$@";
      chomp( $error );
      $log->error( "Error: $error" );
      $log->error( "Warning: Returning ESTAR__FAULT" );
      my $log->thread( "Client", "Done." );
      return ESTAR__FAULT;
   }   
   eval { $dec = event->dec(); };
   if ( $@ ) {
      my $error = "$@";
      chomp( $error );
      $log->error( "Error: $error" );
      $log->error( "Warning: Returning ESTAR__FAULT" );
      my $log->thread( "Client", "Done." );
      return ESTAR__FAULT;
   }
   my $log->print( "Following up $name at $ra, $dec");
   
   my $coords = new Astro::Coords( ra => $ra, dec => $dec, units => 'degrees' );
   my $ra_sex = $coords->ra->in_format( 'sexagesimal' );
   my $dec_sex = $coords->dec->in_format( 'sexagesimal' );                  
   
   if( $event->role() eq "test" ) {
      $log->print("Recieved an OGLE 'test' message...");
      $log->debug( $message );
      my $log->thread( "Client", "Done." );
      return ESTAR__FAULT;       
   } elsif ( $event->role() eq "observation" ) {
   
      # Submit observations
      # -------------------
      $log->print("Recieved an OGLE 'observation' message...");
   
      # end point
      my $endpoint = "http://" . $config->get_option("ua.host") . 
                     ":" . $config->get_option("ua.port");
      my $uri = new URI($endpoint);
      $log->debug("User Agent end point is " . $endpoint);
  
      # create a user/passwd cookie
      $log->debug( "Building cookie...");
      my $cookie = eSTAR::Util::make_cookie(
              $config->get_option("ec.user"),$config->get_option("ec.passwd"));
      my $cookie_jar = HTTP::Cookies->new();
      $cookie_jar->set_cookie(0,user => $cookie, '/',$uri->host(),$uri->port());

      # create SOAP connection
      $log->debug("Marshalling SOAP connection...");
      my $soap = new SOAP::Lite();
      $soap->uri('urn:/user_agent'); 
      
      $log->debug("Putting cookies in the cookie jar...");
      $soap->proxy($endpoint, cookie_jar => $cookie_jar);

      my @split_name = split "-", $name;
      my $year = $split_name[1];
      $year =~ s/20//;
      my $ob_name = "OB". $year. sprintf("%03d", $split_name[3]);
      $log->debug("Fixing object name from $name to $ob_name" );
    
      $log->debug( "Generating start and end times...");
      my ( $start_time, $end_time ) = get_times();
      
      $log->print( "We have an single observation group of 3 exposures of 30s");
      %observation = ( user          => $config->get_option("ec.user"),
                       pass	     => $config->get_option("ec.passwd"),
                       ra	     => $ra,
                       dec	     => $dec,
                       target	     => $ob_name,
                       exposure      => 30,
                       passband      => "R",
                       type	     => "ExoPlanetMonitor",
                       followup      => 0,
                       groupcount    => 3,
                       starttime     => $start_time,
                       endtime       => $end_time );	  
    
    
      # report
      $log->thread("Client", "Calling new_observation( ) in User Agent");
    
      # grab result 
      my $result;
      eval { $result = $soap->new_observation( %observation ); };
      if ( $@ ) {
         my $error = "$@";
         chomp( $error );
         $log->error( "Error: $error" );
         $log->error( "Warning: Returning ESTAR__FAULT" );
         my $log->thread( "Client", "Done." );
         return ESTAR__FAULT;
      }
  
     # Check for errors
     $log->print("Transport Status: " . $soap->transport()->status() );
  
     unless ($result->fault() ) {
        $log->($result->result());
     } else {
       my $error = $result->faultstring();
       chomp( $error );
       $log->error( "Error( ". $result->faultcode() ."): $error" );
       $log->error( "Warning: Returning ESTAR__FAULT" );
       my $log->thread( "Client", "Done." );
       return ESTAR__FAULT;     
     }     
   } else {
      $log->print("Recieved an unknown OGLE message...");
      $log->debug( $message );
   }
   
   my $log->thread( "Client", "Done." );
   return ESTAR__OK;
}

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
	      my $response;
	      if( $message =~ "Transport" && !( $message =~ "WhereWhen" ) ) {
		 my $object = new XML::Document::Transport();
	         my $transport;
		 eval{$transport = new XML::Document::Transport(XML => $message);};
		 if ( $@ ) {
                    my $error = "$@";
                    chomp( $error );
                    $log->error( "Error: $error" );
                    $log->error( $transport );
		    $log->warn( "Warning: Send 'error' packet...");
		    $response = $object->build(
                           Role      => 'error',
		   	   Origin    => 'ivo:/uk.org.estar/estar.exo#',
                           TimeStamp => eSTAR::Broker::Util::time_iso(),
			   Meta => [{ Name => 'error',UCD => 'meta.error', 
			              Value => "$@" },] );
                 } elsif ( $transport->role() eq "iamalive" ) {
	            $log->debug("Echoing 'iamalive' packet..");
                    $response = $object->build(
                           Role      => 'iamalive',
                           Origin    => $transport->origin(),
		   	   Response  => 'ivo:/uk.org.estar/estar.exo#ack',
                           TimeStamp => eSTAR::Broker::Util::time_iso() );
		 } elsif ( $transport->role() eq "ack" ) {
	            $log->debug("Responding with an 'ack' packet...");
                    $response = $object->build(
                           Role      => 'ack',
                           Origin    => $transport->origin(),
		   	   Response  => 'ivo:/uk.org.estar/estar.exo#ack',
                           TimeStamp => eSTAR::Broker::Util::time_iso() );
	         }
	      
	      }   
	      my $bytes = pack( "N", length($response) ); 
              $log->debug("Sending " . length($response) . " bytes to socket");
              print $sock $bytes;
              $sock->flush();
              print $sock $response;
	      #print "$response\n";
              $sock->flush(); 
	      
              # callback to handle incoming Events     
              $log->print("Detaching callback thread..." );
              my $callback_thread = threads->create ( 
	                              &incoming_callback, $message );
              $callback_thread->detach(); 			  
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

sub get_times{

   my $year = 1900 + localtime->year();
   my $month = localtime->mon() + 1;
   my $day = localtime->mday();

   my $hour = localtime->hour();
   my $min = localtime->min();
   my $sec = localtime->sec();

   # could be last day of the month
   if ( $day >= 28 && $day <= 31 ) {
  
     # Special case for Februry
     if ( $month == 2 ) {
  
        # insert code to handle leap year here
  
        $month = $month + 1;
        $day = 1;
     
     } elsif ( $month == 9 || $month == 4 || $month == 6 || $month == 11 ) {
       if( $day == 30 ) {
          $month = $month + 1;
          $day = 1;
       }
    
     } elsif ( $day == 31 ) {
       $month = $month + 1;
       $day = 1;
     }  
   }

   # fix roll over errors
   my $dayplusone = $day + 1;
   my $hourplustwelve = $hour + 13; # Actually plus 13 hours, not 12 now!
   if( $hourplustwelve > 24 ) {
     $hourplustwelve = $hourplustwelve - 24;
   } 
 
   # fix less than 10 errors
   $month = "0$month" if $month < 10;
   $day = "0$day" if $day < 10;   
   $hour = "0$hour" if $hour < 10;   
   $min = "0$min" if $min < 10;   
   $sec = "0$sec" if $sec < 10;   
   $dayplusone = "0$dayplusone" if $dayplusone < 10;   
   $hourplustwelve = "0$hourplustwelve" if $hourplustwelve < 10;

   # defaults of now till 12 hours later 
   my ( $start_time, $end_time ); 
 
   # modify start time
   unless( defined $opt{"start"} ) {
      $start_time = "$year-$month-$day" . "T". $hour.":".$min.":".$sec . "UTC";
   } else {
      $start_time = $opt{"start"};
   } 

   # modify end time
   unless( defined $opt{"start"} ) {
      $end_time = "$year-$month-$dayplusone" . 
                  "T". $hourplustwelve.":".$min.":".$sec . "UTC"; 
   } else {
      $end_time = $opt{"end"};  
   }    

   return ($start_time, $end_time);
}

