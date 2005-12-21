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

C<event_broker.pl> - Brokers incoming & outgoing event streams

=head1 SYNOPSIS

   event_broker.pl [-vers]

=head1 DESCRIPTION

C<event_broker.pl> is a persitent component of the the eSTAR Intelligent 
Agent Client Software. The C<event_Broker.pl> is an simple gateway for
incoming alerts from the various systems, which will persistently store
the messages, and forward them to connected clients.

=head1 REVISION

$Id: event_broker.pl,v 1.7 2005/12/21 18:32:25 aa Exp $

=head1 AUTHORS

Alasdair Allan (aa@astro.ex.ac.uk)

=head1 COPYRIGHT

Copyright (C) 2005 University of Exeter. All Rights Reserved.

=cut

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.7 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR Event Broker Software:\n";
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
use Net::FTP;

my $name;
GetOptions( "name=s" => \$name );

my $process_name;
if ( defined $name ) {
  $process_name = "event_broker_" . $name;
} else { 
  $process_name = "event_broker";
}  

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
my $process = new eSTAR::Process( $process_name );  

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process->set_version( $VERSION );

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
$log->header("Starting Event Broker: Version $VERSION");

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
$number = $config->get_state( "broker.unique_process" ); 
unless ( defined $number ) {
  # $number is not defined correctly (first ever run of the program?)
  $number = 0; 
}

# increment ID number
$number = $number + 1;
$config->set_state( "broker.unique_process", $number );
$log->debug("Setting broker.unique_process = $number"); 
  
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
$config->set_state( "broker.pid", getpgrp() );
  
# commit $pid to STATE file
$status = $config->write_state();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Can not read or write to state.dat file";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("Broker PID: " . $config->get_state( "broker.pid" ) );
}

# L A T E  L O A D I N G  M O D U L E S ------------------------------------- 

#
# System modules
#
use POSIX qw/:sys_wait_h/;
use Errno qw/EAGAIN/;
use Digest::MD5 'md5_hex';
use Fcntl qw(:DEFAULT :flock);
use Errno qw(EWOULDBLOCK EINPROGRESS);
use Config::Simple;
use Config::User;
use Time::localtime;
use XML::RSS;

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
use eSTAR::Broker::Util;

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

if ( $config->get_state("broker.unique_process") == 1 ) {
   
   my %user_id;
   tie %user_id, "CfgTie::TieUser";

   $config->set_option( "local.host", $ip );
   
   # grab current user
   my $current_user = $user_id{$ENV{"USER"}};
   my $real_name = ${$current_user}{"GCOS"};
  
   # user defaults
   $config->set_option("user.user_name", $ENV{"USER"} );
   $config->set_option("user.real_name", $real_name );
   $config->set_option("user.email_address", $ENV{"USER"}."@".hostdomain());
   
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

   # server parameters
   # -----------------
   $config->set_option( "raptor.host", "astro.lanl.gov" );
   $config->set_option( "raptor.port", 43002 );
   $config->set_option( "raptor.ack", 5170 );
   $config->set_option( "raptor.iamalive", 60 );

   #$config->set_option( "estar.host", "estar.astro.ex.ac.uk" );
   #$config->set_option( "estar.port", 8099 );
   #$config->set_option( "estar.ack", 8099 );
   #$config->set_option( "estar.iamalive", 60 );
      
   # list of event servers
   $config->set_option("server.RAPTOR", "raptor" );
   #$config->set_option("server.eSTAR", "estar" );
    
        
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
$lwp->agent( "eSTAR Event Broker Daemon /$VERSION (" 
            . hostname() . "." . hostdomain() .")");

my $ua = new eSTAR::UserAgent(  );  
$ua->set_ua( $lwp );

# ===========================================================================
# C A L L B A C K S
# ===========================================================================

# O P E N   I N C O M I N G   C L I E N T  -----------------------------------

# Other port ACK callback

my $other_ack_port_callback = sub {
  my $server = shift;
  my $name = shift;
  my $file = shift;
  my $host = $config->get_option( "$server.host");
  my $port = $config->get_option( "$server.ack");
  
  my $thread_name = "ACK";
  $log->thread($thread_name, "Sending ACK message at " . ctime() . "...");
  $log->thread($thread_name, "Opening socket connection to $host:$port..." ) ;
 
  my $ack_sock = new IO::Socket::INET( 
                   PeerAddr => $host,
                   PeerPort => $port,
                   Proto    => "tcp",
                   Timeout  => $config->get_option( "connection.timeout" ) );

  unless ( $ack_sock ) {
     
     # we have an error
     my $error = "$!";
     chomp($error);
     $log->error( "Error: $error");
     return ESTAR__FAULT;      
  
  } 
 
  $log->thread($thread_name, "Sending ACK message to $host:$port...");
  
  # return an ack message
  my $ack =
   "<?xml version = '1.0' encoding = 'UTF-8'?>\n" .
   '<VOEvent role="ack" version="1.1" id="ivo://estar.ex/ack" >' . "\n" . 
   '<Who>' . "\n" . 
   '   <PublisherID>ivo://estar.ex/</PublisherID>' . "\n" . 
   '   <Date>' . eSTAR::Broker::Util::time_iso() . '</Date>' . "\n" .
   '</Who>' . "\n" . 
   '<What>' . "\n" . 
   '   <Param value="stored" name="'. $file .'" />' . "\n" . 
   '</What>' . "\n" . 
   '</VOEvent>' . "\n";

  # work out message length
  my $header = pack( "N", 7 );                    # RAPTOR specific hack
  my $bytes = pack( "N", length($ack) ); 
   
  # send message                                   
  $log->debug( "Sending " . length($ack) . " bytes to $host:$port" );
                     
  $log->debug( $ack ); 
                     
  print $ack_sock $header if $name eq "RAPTOR";  # RAPTOR specific hack
  print $ack_sock $bytes;
  $ack_sock->flush();
  print $ack_sock $ack;
  $ack_sock->flush();  
  close($ack_sock);
  
  $log->debug( "Closed ACK socket"); 
  $log->thread($thread_name, "Done.");
  return ESTAR__OK;
};

# TCP/IP callback

my $incoming_callback = sub {
  my $server = shift;
  my $name = shift;
  my $message = shift;  
  my $host = $config->get_option( "$server.host");
  my $port = $config->get_option( "$server.port");  
    
  my $thread_name = "Client";
  $log->thread2($thread_name, "Callback from TCP client at " . ctime() . "...");
  $log->thread2($thread_name, "Handling broadcast message from $host:$port");

  $log->debug( "Testing to see whether we have an RTML document..." );
  if ( $message =~ /RTML/ ) {
     my $rtml;
     eval { $rtml = new eSTAR::RTML( Source => $message ) };
     $log->warn( "Warning: Document identified as RTML..." );
     my $type = $rtml->determine_type();
     $log->warn( "Warning: Recieved RTML message of type '$type'" );  
     $log->warn( "$message");       
     $log->warn( "Warning: Returning ESTAR__FAULT, exiting callback...");
     return ESTAR__FAULT; 
         
  } 

  # It really, really should be a VOEvent message
  $log->debug( "Testing to see whether we have a VOEvent document..." );
  my $voevent;
  if ( $message =~ /VOEvent/ ) {
     $log->debug( "This looks like a VOEvent document..." );
     $log->print( $message );
     
     # Ignore ACK and IAMALIVE messages
     # --------------------------------
     my $event = new Astro::VO::VOEvent( XML => $message );
     my $id = $event->id();
     
     if( $event->role() eq "ack" ) {
        $log->thread2( $thread_name, "Recieved ACK message from $host...");
        $log->thread2( $thread_name, "Recieved at " . ctime() );
        $log->debug( $message );
        $log->debug( "Done." );
	
	# THE EVENT BROKER SHOULDN'T GET ACK MESSAGES HERE, IF IT DOES
	# IT SHOULD IGNORE THEM. ONLY THE SERVER SIDE OF THE BROKER NEEDS
	# TO DEAL WITH ACK MESSAGES.
	
        return ESTAR__OK;
        
     } elsif ( $event->role() eq "iamalive" ) {
       $log->thread2($thread_name, "Recieved IAMALIVE message from $host");
       $log->thread2($thread_name, "Recieved at " . ctime() );
       $log->debug( $message );
       $log->debug( "Done.");
       
       # ADD CODE HERE TO SEND IAMALIVE MESSAGES BACK to PUBLISHERS, NEEDS 
       # TO SPAWN AN IAMALIVE_CALLBACK( ) THREAD? NEEDS TO CHECK THE PUBLISHER.
       
       
       return ESTAR__OK;
     }  

     # HANDLE VOEVENT MESSAGE --------------------------------------------
     #
     # At this stage we have a GCN or RAPTOR alert message
       
     # log the event message
     my $file;
     eval { $file = eSTAR::Broker::Util::store_voevent( $name, $message ); };
     if ( $@  ) {
       $log->error( "Error: $@" );
     } 
     
     unless ( defined $file ) {
        $log->warn( "Warning: The message has not been serialised..." );
     }
     
     # Upload the event message to estar.org.uk
     # ----------------------------------------
     
     my @path = split( "/", $id );
     if ( $path[0] eq "ivo:" ) {
        splice @path, 0 , 1;
     }
     if ( $path[0] eq "" ) {
        splice @path, 0 , 1;
     }
     my $path = "www.estar.org.uk/docs/voevent/$name";
     foreach my $i ( 0 ... $#path - 1 ) {
        $path = $path . "/$path[$i]"; 
     }
     $log->debug("Opening FTP connection to lion.drogon.net...");  
     $log->debug("Logging into estar account...");  
     my $ftp = Net::FTP->new( "lion.drogon.net", Debug => 1 );
     $ftp->login( "estar", "tibileot" );
     $log->debug("Changing directory to $path");
     $ftp->cwd( $path );
     $log->debug("Uploading $file");
     $ftp->put( $file, "$id" . ".xml" );
     $ftp->quit();    
     $log->debug("Closing FTP connection"); 
     
     # Writing to alert.log file
     my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
     my $alert = File::Spec->catfile( $state_dir, $name, "alert.log" );
     
     $log->debug("Opening alert log file: $alert"); 
      
     # callback to send ACK message
     # ----------------------------
 
     unless( $config->get_option( "$server.ack") == $port ) {
     
        $log->print("Detaching ack thread..." );
        my $ack_thread =
           threads->create( $other_ack_port_callback, $server, $name, $file );
        $ack_thread->detach();   
     } else {
        $log->debug( "ACK message sent from main loop..." );
     }

     # Writing to alert.log file
     my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
     my $alert = File::Spec->catfile( $state_dir, "alert.log" );
     
     $log->debug("Opening alert log file: $alert");  
           
     # write the observation object to disk.
     # -------------------------------------
     
     unless ( open ( ALERT, "+>>$alert" )) {
        my $error = "Warning: Can not write to "  . $state_dir; 
        $log->error( $error );
        throw eSTAR::Error::FatalError($error, ESTAR__FATAL);   
     } else {
        unless ( flock( ALERT, LOCK_EX ) ) {
          my $error = "Warning: unable to acquire exclusive lock: $!";
          $log->error( $error );
          throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
        } else {
          $log->debug("Acquiring exclusive lock...");
        }
     }        
     
     $log->debug("Writing file path to $alert");
     print ALERT "$file\n";
     
     # close ALERT log file
     $log->debug("Closing alert.log file...");
     close(ALERT);  

     # GENERATE RSS FEED -------------------------------------------------
     
   
     # Reading from alert.log file
     # ---------------------------     
     $log->debug("Opening alert log file: $alert");  
      
     # write the observation object to disk.
     unless ( open ( LOG, "$alert" )) {
        my $error = "Warning: Can not read from "  . $state_dir; 
        $log->error( $error );
        throw eSTAR::Error::FatalError($error, ESTAR__FATAL);   
     } else {
        unless ( flock( LOG, LOCK_EX ) ) {
          my $error = "Warning: unable to acquire exclusive lock: $!";
          $log->error( $error );
          throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
        } else {
          $log->debug("Acquiring exclusive lock...");
        }
     }        
     
     $log->debug("Reading from $alert");
     my @files;
     {
        local $/ = "\n";  # I shouldn't have to do this?
        @files = <LOG>;
     }   
     # use Data::Dumper; print "\@files = " . Dumper( @files );
     
     $log->debug("Closing alert.log file...");
     close(LOG);
          
     # Writing to broker.rdf
     # ---------------------
     my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
     my $rss = File::Spec->catfile( $state_dir, $name, "$name.rdf" );
        
     $log->debug("Creating RSS file: $rss");  
          
     # write the observation object to disk.
     unless ( open ( RSS, ">$rss" )) {
        my $error = "Warning: Can not write to "  . $state_dir; 
        $log->error( $error );
        throw eSTAR::Error::FatalError($error, ESTAR__FATAL);   
     } else {
        unless ( flock( RSS, LOCK_EX ) ) {
          my $error = "Warning: unable to acquire exclusive lock: $!";
          $log->error( $error );
          throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
        } else {
          $log->debug("Acquiring exclusive lock...");
        }
     }                  
     
     $log->print( "Creating RSS feed..." );     
    
     my $timestamp = eSTAR::Broker::Util::time_iso( );
     my $rfc822 = eSTAR::Broker::Util::time_rfc822( );
     
     my $feed = new XML::RSS( version => "2.0" );
     $feed->channel(
        title        => "eSTAR $name Event Feed",
        link         => "http://www.estar.org.uk",
        description  => 
	  'This is an RSS2.0 feed from '.$name.' of VOEvent notices brokered '.
	  'through the eSTAR agent network.Contact Alasdair Allan '.
	  '<aa@estar.org.uk> for information about this and other eSTAR feeds. ' .
	  'More information about the eSTAR Project can be found on our '.
	  '<a href="http://www.estar.org.uk/">website</a>.',
        pubDate        => $rfc822,
        lastBuildDate  => $rfc822,
        language       => 'en-us' );

     $feed->image(title       => 'estar.org.uk',
             url         => 'http://www.estar.org.uk/favicon.png',
             link        => 'http://www.estar.org.uk/',
             width       => 16,
             height      => 16,
             description => 'eSTAR' );
      
     my $num_of_files = $#files;   
     foreach my $i ( 0 ... $num_of_files ) {
        $log->debug( "Reading $i of $num_of_files entries" );
        my $data;
        {
           open( DATA_FILE, "$files[$i]" );
           local ( $/ );
           $data = <DATA_FILE>;
           close( DATA_FILE );

        }  
        
        #  use Data::Dumper; print "\@data = " . Dumper( $data );
   
        $log->debug( "Determing ID of message..." );
        my $object = new Astro::VO::VOEvent( XML => $data );
        my $id;
        eval { $id = $object->id( ); };
        if ( $@ ) {
           $log->error( "Error: $@" );
           $log->error( "\$data = " . $data );
           $log->warn( "Warning: discarding message $i of $num_of_files" );
           next;
        } 
        $log->debug( "ID: $id" );
  
        # grab <What>
        my %what = $object->what();
        my $packet_type = $what{Param}->{PACKET_TYPE}->{value};
 
        my $timestamp = $object->time();
               
        # build url
        my @path = split( "/", $id );
        if ( $path[0] eq "ivo:" ) {
           splice @path, 0 , 1;
        }
        if ( $path[0] eq "" ) {
           splice @path, 0 , 1;
        }
        my $url = "http://www.estar.org.uk/voevent/$name";
        foreach my $i ( 0 ... $#path ) {
           $url = $url . "/$path[$i]"; 
        }
        $url = $url . ".xml";
   
        my $description;
	if ( defined $packet_type ) {
	  $description = "GCN PACKET_TYPE = $packet_type (via $name)<br>\n" .
                         "Time stamp at $name was $timestamp";
	} else {
	  $description = "Received packet (via $name) at $timestamp";
	}  		 
   
        $log->print( "Creating RSS Feed Entry..." );
        $feed->add_item(
           title       => "$id",
           description => "$description",
           link        => "$url",
           enclosure   => { 
             url=>$url, 
             type=>"application/xml+voevent" } );


     }
     $log->debug( "Creating XML representation of feed..." );
     my $xml = $feed->as_string();

     $log->debug( "Writing feed to $rss" );
     print RSS $xml;
       
     # close ALERT log file
     $log->debug("Closing raptor.rdf file...");
     close(RSS);    
     
     $log->debug("Opening FTP connection to lion.drogon.net...");  
     $log->debug("Logging into estar account...");  
     $ftp->login( "estar", "tibileot" );
     $ftp->cwd( "www.estar.org.uk/docs/voevent/$name" );
     $log->debug("Transfering RSS file...");  
     $ftp->put( $rss, "gcn.rdf" );
     $ftp->quit();     
     $log->debug("Closed FTP connection");  

  
  } else {
     $log->warn( "Warning: Document unidentified..." );
     $log->warn( "$message");       
     $log->warn( "Warning: Returning ESTAR__FAULT, exiting callback...");
     return ESTAR__FAULT;      
  }  
  
  $log->debug( "Returning ESTAR__OK, exiting callback..." );
  return ESTAR__OK;
};

# C L I E N T   C O N N E C T I O N S   T O   R E M O T E   H O S T S --------

my $incoming_connection = sub {
   my $server = shift;
   my $name = shift;
   my $host = $config->get_option( "$server.host");
   my $port = $config->get_option( "$server.port");
   SOCKET: { 
       
   $log->print("Opening client connection to $host:$port" );    
   my $sock = new IO::Socket::INET( 
                 PeerAddr => $host,
                 PeerPort => $port,
                 Proto    => "tcp" );

   unless ( $sock ) {
       my $error = "$@";
       chomp($error);
       $log->warn("Warning: $error");
       $log->warn("Warning: Trying to reopen connection to $host...");
       sleep 5;
       redo SOCKET;
   };           


   my $response;
   $log->print( "Socket to $host open, listening..." );
   my $flag = 1;    
   while( $flag ) {

      my $length;  
      my $bytes_read = read( $sock, $length, 4 );
 
      next unless defined $bytes_read;
   
      $log->print("\nRecieved a packet from $host..." );
      if ( $bytes_read > 0 ) {
   
         $log->debug( "Recieved $bytes_read bytes on $port from $host" );    
      
        $length = unpack( "N", $length );
        if ( $length > 512000 ) {
          $log->error( "Error: Message length is > 512000 characters" );
          $log->error( "Error: Message claims to be $length long" );
          $log->warn( "Warning: Discarding bogus message" );
        } else {   
         
           $log->debug( "Message is $length characters" );               
           $bytes_read = read( $sock, $response, $length); 
      
           $log->debug( "Read $bytes_read characters from socket" );
      
           # callback to handle incoming Events     
           $log->print("Detaching callback thread..." );
           my $callback_thread = 
               threads->create ( $incoming_callback, $server, $name, $response );
           $callback_thread->detach(); 
	   
           # send ACK message if we're on same port
           if( $config->get_option( "$server.ack") == $port ) {
              
	       # return an ack message
               my $ack =
            "<?xml version = '1.0' encoding = 'UTF-8'?>\n" .
            '<VOEvent role="ack" version="1.1" id="ivo://estar.ex/ack" >' . "\n" . 
            '<Who>' . "\n" . 
            '   <PublisherID>ivo://estar.ex/</PublisherID>' . "\n" .
            '   <Date>' . eSTAR::Broker::Util::time_iso() . '</Date>' . "\n" .
            '</Who>' . "\n" . 
            '</VOEvent>' . "\n";
              
	      my $bytes = pack( "N", length($ack) ); 
	      
	      # send message                                   
	      $log->debug( "Sending " . length($ack) . " bytes to $host:$port" );
              $log->debug( $ack ); 
                     
              #print $sock $header;     # RAPTOR specific header
              print $sock $bytes;
              $sock->flush();
              print $sock $ack;
              $sock->flush();         
           } else {
	      $log->debug( "Sending ACK from callback thread..." );
	   } 
       
           $log->debug( "Done, listening..." );
        }
                      
     } elsif ( $bytes_read == 0 && $! != EWOULDBLOCK ) {
        $log->warn("Recieved an empty packet on $port from $host" );   
        $log->warn( "Closing socket connection to $host..." );      
        $flag = undef;
     }

     unless ( $sock->connected() ) {
        $log->warn("\nWarning: Not connected, socket to $host closed...");
        $flag = undef;
     }    

  }  
    
  $log->warn( "Warning: Trying to reopen socket connection to $host..." );
  redo SOCKET;

   
  }          
};
  

# ===========================================================================
# M A I N   B L O C K 
# ===========================================================================

$log->debug("Opening client connections...");

# make client connections to all the remote servers we know about
my @servers;
eval { @servers = $config->get_block( "server" ); };
if ( $@ ) {
  $log->error( "Error: $@" );
}  

my @names;
eval { @names = $config->get_block_names( "server" ); };
if ( $@ ) {
  $log->error( "Error: $@" );
}  

foreach my $i ( 0 ... $#servers ) {
   my $server = $servers[$i];
   my $name = $names[$i];
   
   my $host = $config->get_option( "$server.host");
   my $port = $config->get_option( "$server.port");
   
   $log->print( "Connecting to $name at $host:$port");
   my $incoming_thread = 
      threads->create( \&$incoming_connection , $server, $name );
   $incoming_thread->detach();
}
          
	  
while(1) {}	  
# ===========================================================================
# E N D 
# ===========================================================================

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
    
   # close out log files
   $log->debug("Closing log files...");
   $log->closeout();
 
   # close the door behind you!   
    
   # kill the agent process
   $log->print("Killing broker processes...");
   exit;
}                                

# T I M E   A T   T H E   B A R  -------------------------------------------

# $Log: event_broker.pl,v $
# Revision 1.7  2005/12/21 18:32:25  aa
# Big fix
#
# Revision 1.6  2005/12/21 18:31:52  aa
# Big fix
#
# Revision 1.5  2005/12/21 18:31:08  aa
# Big fix
#
# Revision 1.4  2005/12/21 18:30:04  aa
# Big fix?
#
# Revision 1.3  2005/12/21 18:24:33  aa
# Big fix?
#
# Revision 1.2  2005/12/21 17:55:25  aa
# Shipping to estar servers
#
# Revision 1.1  2005/12/21 15:37:30  aa
# Lots of changes, see ChangeLog
#

