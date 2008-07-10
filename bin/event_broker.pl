#!/software/perl-5.8.6/bin/perl

# Whack, don't do it again!
use strict;

# G L O B A L S -------------------------------------------------------------

# Global variables
#  $VERSION  - CVS Revision Number
#  %OPT      - Options hash for things we don't want to be persistant
#  $log      - Handle for logging object
#  %messages - Shared hash holding the messages being passed between threads
#  %collect  - Shared hash holding the semaphore flags to tell the garabage
#	       collection thread that the message has been picked up
#  @tids     - list of currently active server threads (with live clients)

use vars qw / $VERSION %OPT $log $config %messages %collect %tids $tid_down /;

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

$Id: event_broker.pl,v 1.114 2008/07/10 13:17:05 aa Exp $

=head1 AUTHORS

Alasdair Allan (aa@astro.ex.ac.uk)

=head1 COPYRIGHT

Copyright (C) 2005 University of Exeter. All Rights Reserved.

=cut

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.114 $ =~ /(\d+)\.(\d+)/;
 
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
use eSTAR::Error qw /:try/;

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

# process id in this case...
$process->set_urn( $process_name );

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


# S H A R E   C R O S S - T H R E A D   V A R I A B L E S -------------------

# share the running hashs across threads, I'd love to do this with an proper
# object, but unfortuantely the Perl threading model really sucks rocks. So
# the hashs are shared across the running threads by the object, so part of
# the object data structre is shared and some isn't. At least, I think this
# is how things work... 

$log->debug( "Stuffing the running hashes into an placeholder object..." );
my $run = new eSTAR::Broker::Running( $process->get_process() );
$run->swallow_messages( \%messages ); 
$run->swallow_collected( \%collect ); 
$run->swallow_tids( \%tids ); 

my @closed_sockets;
$tid_down = \@closed_sockets;
share( $tid_down );

# C A T C H   S I G N A L S -------------------------------------------------

#  Catch as many signals as possible so that the END{} blocks work correctly
use sigtrap qw/die normal-signals error-signals/;

# make unbuffered
$|=1;					

# flag to kill server
my $server_flag;

# signals
$SIG{PIPE} = sub { 
              $log->warn( "Client Disconnecting" ); };
$SIG{INT} = sub {  
              $log->error( "Recieved Interrupt" ); 
              $server_flag = 1;
              exit(1); };

$SIG{ALRM} = sub { 
             $log->error( "Socket connection timed out. Trapped globally." );
             #die "Socket connection timed out"; 
	    };

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
use Net::Twitter;
use WWW::Shorten::TinyURL;
use WWW::Shorten 'TinyURL';

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
use eSTAR::Broker::Running;
use eSTAR::Broker::SOAP::Daemon;
use eSTAR::Broker::SOAP::Handler;

use XML::Document::Transport;

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

   # broker
   $config->set_option( "broker.host", $ip );
   $config->set_option( "broker.port", 8099 );
   $config->set_option( "broker.soap", 9099 );
   $config->set_option( "broker.ping", 60 );
   $config->set_option( "broker.garbage", 45 );   
      
   # server parameters
   # -----------------
   #$config->set_option( "raptor.host", "astro.lanl.gov" );
   #$config->set_option( "raptor.port", 43003 );
   #$config->set_option( "raptor.ack", 43003 );
   #$config->set_option( "raptor.iamalive", 60 );

   $config->set_option( "estar.host", "estar3.astro.ex.ac.uk" );
   $config->set_option( "estar.port", 9999 );
   $config->set_option( "estar.ack", 9999 );
   $config->set_option( "estar.iamalive", 60 );
   
   $config->set_option( "caltech.host", "devnoor.cacr.caltech.edu" );
   $config->set_option( "caltech.port", 15003 ); 
   $config->set_option( "caltech.ack", 15003 ); 
   $config->set_option( "caltech.iamalive", 60 ); 
  
   $config->set_option( "noao.host", "voevent.noao.edu" );
   $config->set_option( "noao.port", 30003 );
   $config->set_option( "noao.ack", 30003 );
   $config->set_option( "noao.iamalive", 60 );
 
   # list of event servers
   #$config->set_option("server.RAPTOR", "raptor" );
   $config->set_option("server.eSTAR", "estar" );
   $config->set_option("server.Caltech", "caltech" );
   $config->set_option("server.NOAO", "noao" ); 
        
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
  my $id = shift;
  my $message = shift;
  my $host = $config->get_option( "$server.host");
  my $port = $config->get_option( "$server.ack");
  
  my $thread_name = "ACK";
  $log->thread($thread_name, 
               "Sending ACK/IAMALIVE message at " . ctime() . "...");
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
 
  my $response;
  if ( $response =~ 'role="iamalive"' ) {
    $log->thread($thread_name, "Sending IAMALIVE message to $host:$port...");
    $log->debug( "Echoing IAMALIVE message back to $name..." );
    $response = $message;
  } else {
    # return an ack message
    $log->thread($thread_name, "Sending ACK message to $host:$port...");
    $log->debug( "Building ACK message..." );
    
    my $object = new XML::Document::Transport();
    if ( $file eq "null" ) {
      $response = $object->build(
         Role      => 'ack',
	 Origin    => 'ivo://uk.org.estar/estar.broker#',
	 TimeStamp => eSTAR::Broker::Util::time_iso() );
	     
    } else {
      $response = $object->build(
         Role      => 'ack',
	 Origin    => 'ivo://uk.org.estar/estar.broker#',
	 TimeStamp => eSTAR::Broker::Util::time_iso(),
	 Meta => [{ Name => 'stored',UCD => 'meta.ref.url', Value => $file },]
	 );
    }
	 
  }
  
  # work out message length
  my $header = pack( "N", 7 );  # RAPTOR specific hack, port 5170
  my $bytes = pack( "N", length($response) ); 
   
  # send message                                   
  $log->debug( "Sending " . length($response) . " bytes to $host:$port" );
                     
  $log->debug( $response ); 
                     
  print $ack_sock $header if $name eq "RAPTOR";  
  print $ack_sock $bytes;
  $ack_sock->flush();
  print $ack_sock $response;
  $ack_sock->flush();  
  close($ack_sock);
  
  $log->debug( "Closed ACK socket"); 
  $log->thread($thread_name, "Done.");
  return ESTAR__OK;
};

# TCP/IP client callback

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

  # Transport packets, we ignore those here...
  $log->debug( "Testing to see whether we have a Transport document..." );
  if ( $message =~ /Transport/ ) {
     $log->debug( "This looks like a Transport document..." );
     # Ignore ACK and IAMALIVE messages
     # --------------------------------
     my $transport;
     eval { $transport = new XML::Document::Transport( XML => $message ); };
     if ( $@ ) {
        my $error = "$@";
        chomp( $error );
        $log->error( "Error: $error" );
        $log->error( $transport );
        $log->warn( "Warning: Returning ESTAR__FAULT" );
        return ESTAR__FAULT;
     }   
     
     if( $transport->role() eq "ack" ) {
        # The event broker shouldn't get ack messages here, if it does
	# it should ignore them. Only the server side of the broker needs
	# to deal with ack messages.

        $log->warn( "Warning: Recieved <Transport> ACK message from $host...");
        $log->warn( "Warning: Recieved at " . ctime() );
        $log->warn( $transport );
        $log->warn( "Warning: Returning ESTAR__FAULT" );
        return ESTAR__FAULT;
        
     } elsif ( $transport->role() eq "iamalive" ) {
        $log->debug( "Ignoring <Transport> IAMALIVE message from $host");
        $log->debug( "Done.");
        return ESTAR__OK;
     } elsif ( $transport->role() eq "utility" ) {
        $log->error( "Error: Recieved <Transport> UTILITY message from $host...");
        $log->error( "Error: Recieved at " . ctime() );
        $log->error( $transport );
        $log->error( "Error: Returning ESTAR__FAULT" );
        return ESTAR__FAULT;     
     
     
     }
  }    

  # It really, really should be a VOEvent message
  $log->debug( "Testing to see whether we have a VOEvent document..." );
  my $voevent;
  if ( $message =~ /VOEvent/ ) {
     $log->debug( "This looks like a VOEvent document..." );
     #$log->print( $message );
     
     # Ignore ACK and IAMALIVE messages
     # --------------------------------
     my $event;
     eval { $event = new Astro::VO::VOEvent( XML => $message ); };
     if ( $@ ) {
        my $error = "$@";
        chomp( $error );
        $log->error( "Error: $error" );
        $log->error( "$message" );
        $log->error( "Warning: Returning ESTAR__FAULT" );
        return ESTAR__FAULT;
     }   
     my $id = $event->id();
     
     if( $event->role() eq "ack" ) {
        # The event broker shouldn't get ack messages here, if it does
	# it should ignore them. Only the server side of the broker needs
	# to deal with ack messages.

        $log->warn( "Warning: Recieved <VOEvent> ACK message from $host...");
        $log->warn( "Warning: Recieved at " . ctime() );
        $log->warn( $message );
        $log->warn( "Warning: Returning ESTAR__FAULT" );
        return ESTAR__FAULT;
        
     } elsif ( $event->role() eq "iamalive" ) {
        $log->debug( "Ignoring <VOEvent> IAMALIVE message from $host");
        $log->debug( "Done.");
        return ESTAR__OK;
     }  

     # HANDLE VOEVENT MESSAGE --------------------------------------------
     #
     # At this stage we have a valid alert message
     
     # DROP ROLE="UTILITY" MESSAGES
     # ----------------------------
     
     if ( $event->role() eq "utility" ) {  
        $log->print( "Ignoring <VOEvent> UTILITY message from $host");
        unless( $config->get_option( "$server.ack") == $port ) {
     
           $log->print("Detaching ack thread..." );
           my $file = "null";
	   my $ack_thread =
                threads->create( $other_ack_port_callback, 
                                 $server, $name, $file, $id, $message );
           $ack_thread->detach();   
        } else {
           $log->debug( "ACK message sent from main loop..." );
        }
        $log->debug( "Returning ESTAR__OK, exiting callback..." );
        return ESTAR__OK;     
     }
     
     # Push message onto running hash via the object we've set up for that
     # purpose...
     eval { $run->add_message( $id, $message ); };
     if ( $@ ) {
        my $error = "$@";
	chomp( $error );
	$log->error( "Error: Can't add message $id to new message hash");
	$log->error( "Error: $error" );
     }	
            
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
     $log->debug("Opening FTP connection to estar.org.uk...");  
     $log->debug("Logging into estar account...");  
     my $ftp = Net::FTP->new( "estar.org.uk", Debug => 1 );
     $ftp->login( "estar", "tibileot" );
    
     my $idpath = $id; 
     $idpath =~ s/#/\//;     
     my @path = split( "/", $idpath );
     if ( $path[0] eq "ivo:" ) {
        splice @path, 0 , 1;
     }
     if ( $path[0] eq "" ) {
        splice @path, 0 , 1;
     }
     my $path = "www.estar.org.uk/docs/voevent/$name";  
     foreach my $i ( 0 ... $#path - 1 ) {
        if ( $path[$i] eq "" ) {
          next;
        }
        $path = $path . "/$path[$i]";        
     }
     $log->debug("Changing directory to $path");
     unless ( $ftp->cwd( $path ) ) {
        $log->warn( "Warning: Recursively creating directories..." );
	$log->warn( "Warning: Path is $path");
	$ftp->mkdir( $path, 1 );
        $ftp->cwd( $path );
	$log->debug("Changing directory to $path");
     }
     $log->debug("Uploading $file");
     $ftp->put( $file, "$path[$#path].xml" );
     $ftp->quit();    
     $log->debug("Closing FTP connection"); 
     
     # Writing to alert.log file
     my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
     my $alert = File::Spec->catfile( $state_dir, $name, "alert.log" );
           
     # callback to send ACK message
     # ----------------------------
 
     unless( $config->get_option( "$server.ack") == $port ) {
     
        $log->print("Detaching ack thread..." );
        my $ack_thread =
             threads->create( $other_ack_port_callback, 
                              $server, $name, $file, $id, $message );
        $ack_thread->detach();   
     } else {
        $log->debug( "ACK message sent from main loop..." );
     }

     # Writing to alert.log file
     my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
     my $alert = File::Spec->catfile( $state_dir, $name, "alert.log" );
     
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
        title        => "$name Event Feed",
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

     $feed->image(
             title       => 'estar.org.uk',
             url         => 'http://www.estar.org.uk/favicon.png',
             link        => 'http://www.estar.org.uk/',
             width       => 16,
             height      => 16,
             description => 'eSTAR' );
      
     my $num_of_files = $#files;
     my $start = 0;
     if ( $num_of_files >= 20 ) {
        $start = $num_of_files - 20;
     }	   
 
     my @not_present;
     for ( my $i = $num_of_files; $i >= $start; $i-- ) {
        $log->debug( "Reading $i of $num_of_files entries" );
        my $data;
        {
           open( DATA_FILE, "$files[$i]" );
           local ( $/ );
           $data = <DATA_FILE>;
           close( DATA_FILE );

        }  
        
        #  use Data::Dumper; print "\@data = " . Dumper( $data );
        
        #$log->debug( "Opening: $files[$i]" );
        $log->debug( "Determing ID of message..." );
        my $object;
        eval { $object = new Astro::VO::VOEvent( XML => $data ); };
        if ( $@ ) {
           my $error = "$@";
           chomp( $error );
           $log->error( "Error: $error" );
           $log->error( "Error: Can't open ". $files[$i] );
           $log->warn( "Warning: discarding message $i of $num_of_files" );
           push @not_present, $i;
           next;
        } 
        my $id;
        eval { $id = $object->id( ); };
        if ( $@ ) {
           my $error = "$@";
           chomp( $error );
           $log->error( "Error: $error" );
           $log->error( "\$data = " . $data );
           $log->warn( "Warning: discarding message $i of $num_of_files" );
           next;
        } 
        $log->debug( "ID: $id" );
  
        # grab <What>
        my %what = $object->what();
        my $packet_type = $what{Param}->{PACKET_TYPE}->{value};
 
        my $packet_timestamp = $object->time();
	my $packet_rfc822;
	eval { $packet_rfc822 = 
	           eSTAR::Broker::Util::iso_to_rfc822( $packet_timestamp ); };
	if ( $@ ) {
	   $log->warn( 
	      "Warning: Unable to parse $packet_timestamp as valid ISO8601");
	}   
              
	# grab role
	my $packet_role = $object->role();
	       
        # build url
        my $idpath = $id;
        $idpath =~ s/#/\//;
        my @path = split( "/", $idpath );
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
	if ( defined $packet_type && lc($id) =~ "gcn" ) {
	  $description = "GCN PACKET_TYPE = $packet_type (via $name)<br>\n" .
                         "Time stamp at $name was $packet_timestamp<br>\n".
	                 "Packet role was '".$packet_role."'";
	} else {
	  $description = "Received packet (via $name) at $packet_timestamp<br>\n".
	                 "Packet role was '".$packet_role."'";
	}  		 
   
        $log->print( "Creating RSS Feed Entry..." );
        if ( defined $packet_rfc822 ) {
	   $feed->add_item(
           title       => "$id",
           description => "$description",
           link        => "$url",
	   pubDate     => "$packet_rfc822",
           enclosure   => { 
             url    => $url, 
             type   => "application/xml+voevent",
             length => length($data) } );
        } else {
	   $feed->add_item(
           title       => "$id",
           description => "$description",
           link        => "$url",
           enclosure   => { 
             url    => $url, 
             type   => "application/xml+voevent",
             length => length($data) } );
	}     
     }
     $log->debug( "Creating XML representation of feed..." );
     my $xml = $feed->as_string();

     $log->debug( "Writing feed to $rss" );
     print RSS $xml;
       
     # close ALERT log file
     $log->debug("Closing $name.rdf file...");
     close(RSS);    
     
     $log->debug("Opening FTP connection to estar.org.uk...");  
     my $ftp2 = Net::FTP->new( "estar.org.uk", Debug => 1 );
     $log->debug("Logging into estar account...");  
     $ftp2->login( "estar", "tibileot" );
     $ftp2->cwd( "www.estar.org.uk/docs/voevent/$name" );
     $log->debug("Transfering RSS file...");  
     $ftp2->put( $rss, "$name.rdf" );
     $ftp2->quit();     
     $log->debug("Closed FTP connection");  


     # Tweet to Twitter
     # ----------------
     
    $log->debug( "Twittering event to twitter.com" );
    my $twit = new Net::Twitter( username => "eSTAR_Project", 
   				 password => "twitter*User" );

    my $url = "http://$path/$path[$#path].xml";
    $url =~ s/\/docs//;
    my $short_url;
    $log->debug( "Passing $url to tinyurl.com" );
    eval { $short_url = makeashorterlink($url); };
    if ( $@ || !defined $short_url ) {
       $short_url = $url;
       my $error = "$@";
       $log->error( "Error: Call to tinyurl.com failed" );
       $log->error( "Error: $error" ) if defined $error;
    } else {
      $log->debug( "Got $short_url back from tinyurl.com" );
    }  
    my $twit_status = "Event message $id at $short_url";  
    my $twit_result;
    eval { $twit_result = $twit->update( $twit_status ); };
    if( $@ || !defined $twit_result ) {
      my $error = "$@";
      $log->error( "Error: Problem updating twitter.com with new status" );
      $log->error( "Error: $error" ) if defined $error;
   } else {
      $log->debug( "Updated status on twitter.com" ); 
   }
     
     # Clean up the alert.log file
     # ---------------------------
     if ( defined $not_present[0] ) {
       $log->warn( "Cleaning up $name alert.log file" );
  
       $log->warn( "Warning: Opening $alert" );
       unless ( open ( ALERT, "+>$alert" )) {
          my $error = "Error: Can not write to "  . $state_dir; 
          $log->error( $error );
          throw eSTAR::Error::FatalError($error, ESTAR__FATAL);   
       } else {
          unless ( flock( ALERT, LOCK_EX ) ) {
            my $error = "Error: unable to acquire exclusive lock: $!";
            $log->error( $error );
            throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
         } else {
           $log->warn("Warning: Acquiring exclusive lock...");
         }
       }        
     
      $log->warn( "Warning: Writing to $alert" );
      foreach my $k ( 0 ... $#files ) {
          
          my $flag = 0;
          foreach my $l ( 0 ... $#not_present ) {
             $flag = 1 if $k == $not_present[$l];
          }
          
          unless ( $flag ) {   
             $log->warn("$files[$k] (line $k of $#files)");
             print ALERT "$files[$k]";
          } else {
             $log->error("$files[$k] (DELETED)");
          }         
       }
       
       # close ALERT log file
       $log->warn("Warning: Closing alert.log file...");
       close(ALERT);       
       
     } # end clenaup of alert.log file
     
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
                 Proto    => "tcp",
		 Timeout  => $config->get_option( "connection.timeout" ) );

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
        $log->debug( "Message is $length characters" );               
        if ( $length > 512000 ) {
          $log->error( "Error: Message length is > 512000 characters" );
          $log->error( "Error: Message claims to be $length long" );
          $log->warn( "Warning: Discarding bogus message" );
        } else {   
 
           # Whenever possible TCP sends data in the largest possible segments. 
	   # The MSS (maximum segment size) is computed by deducting TCP/IP 
	   # header sizes from the MTU (maximum transmission unit) of the 
	   # network interfaces along the path. Today the typical TCP MSS is 
	   # 1448 bytes, due to the 1500 Byte Ethernet MTU.
	   # 
	   # http://www-didc.lbl.gov/papers/net100.sc02.final.pdf
	   #
	   # So we do a continous read until we reach $length bytes
           $bytes_read = read( $sock, $response, $length); 
      
           $log->debug( "Read $bytes_read characters from socket" );
	   
           # send ACK message if we're on same port
           if( $config->get_option( "$server.ack") == $port ) {    
                      
               my $message;
               if ( $response =~ 'role="iamalive"' ) {
	       
	         # return an iamalive message
 	         $log->debug( "Echoing IAMALIVE message back to $name..." );
		 $message = $response;
	       } else {
	       
	          # return an ack message
 	          $log->debug( "Building ACK message..." );
                  my $object = new XML::Document::Transport();
		  my $event;
                  eval { $event = new Astro::VO::VOEvent( XML => $response ); };
                  if ( $@ ) {
                     $message = $object->build(
                        Role      => 'ack',
	                Origin    => 'ivo://uk.org.estar/estar.broker#',
	                TimeStamp => eSTAR::Broker::Util::time_iso() );

                  } else {   
                     my $id = $event->id();
                     $id =~ s/#/\//;
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
		     	       
	             $message = $object->build(
                        Role      => 'ack',
	                Origin    => 'ivo://uk.org.estar/estar.broker#',
	                TimeStamp => eSTAR::Broker::Util::time_iso(),
	 Meta => [{ Name => 'stored',UCD => 'meta.ref.url', Value => $url } ] );

                  }
		  
                  # callback to handle incoming Events     
                  $log->print("Detaching callback thread..." );
                  my $callback_thread = threads->create ( 
		      $incoming_callback, $server, $name, $response );
                  $callback_thread->detach(); 
		  
               }

	       my $bytes = pack( "N", length($message) ); 
	      
	       # send message                                   
	       $log->debug("Sending ".length($message)." bytes to $host:$port");
               $log->debug( $message ); 
                   
               print $sock $bytes;
               $sock->flush();
               print $sock $message;
               $sock->flush();  
                      
           } else {
	      $log->debug( "Sending ACK/IAMALIVE from callback thread..." );
	   } 
       
           $log->debug( "Done, listening..." );
        }
                      
     } elsif ( $bytes_read == 0 && $! != EWOULDBLOCK ) {
        $log->error( "Error: $!" );
        $log->warn( "Recieved an empty packet on $port from $host" );
        $log->warn( "Closing socket connection to $host..." );      
        $flag = undef;
     } elsif ($bytes_read == 0 ) {
        $log->warn( "Recieved a zero length packet on $port from $host" );   
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
  
# BROKER SERVER STARTUP AND CALLBACKS ---------------------------------------

# I A M A L I V E  C A L L B A C K ------------------------------------------

# anonymous subroutine
my $iamalive = sub {
   my $c = shift;
   my $server = shift;

   # STATE FILE
   # ----------
   my $ping_file = 
      File::Spec->catfile( Config::User->Home(), '.estar', 
                           $process->get_process(), "ping_$server.dat" );
   
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
      sleep $config->get_option( "broker.ping" );
      
      my $connect = $c->connected();
      unless( defined $connect ) {
         $log->warn( "Closing socket to $server (IAMALIVE)" );
	 close( $c );
	 last;
      }
      
      # check to see that the thread pushing event messages has died?
      my @connected = $run->list_connections( );
      my $connected_flag;
      $log->debug( "Checking connectd servers (we are $server)...");
      foreach my $i ( 0 ... $#connected ) {
        $log->debug( "Found event thread for $connected[$i]");
	if ( $connected[$i] eq $server ) {
           $connected_flag = 1 
	}   
      }
      unless( defined $connected_flag ) {	
         $log->error( "Error: $server has no corresponding event thread" );
	 $log->error( "Error: Zombie IAMALIVE connection to $server" );
	 {
            lock( @$tid_down );
            foreach my $i ( 0 ... $#$tid_down ) {
	       $log->warn( "Cleaning up \@\$tid_down" );
	       delete $$tid_down[$i] if $$tid_down[$i] eq $server;
            }
	 }
         $log->warn( "Closing socket to $server (IAMALIVE)" );
	 close( $c );
	 last;
      } else {
      	 $log->debug( "We are still connected...");
      }
      
      $log->print( "Pinging $server at ". ctime() . " from " .
                   "(\$tid = " . threads->tid() . ")");
      $log->print ("Sending IAMALIVE message to $server...");
  
      # unique ID for IAMALIVE message
      $log->debug( "Retreving unique number from state file..." );
      my $number = $PING->param( 'iamalive.unique_number' ); 
 
      if ( $number eq '' ) {
         # $number is not defined correctly (first ever message?)
         $PING->param( 'iamalive.unique_number', 0 );
         $number = 0; 
      } 
      $log->debug("Generating unqiue ID: $number");      
  
      my $timestamp = eSTAR::Broker::Util::time_iso();
      $log->debug( "Generating timestamp: $timestamp");
      
      # increment ID number
      $number = $number + 1;
      $PING->param( 'iamalive.unique_number', $number );
      $log->debug('Incrementing unique number to ' . $number);
     
      my $id = $config->get_option( 'local.host' ) . "." . 
               $PING->param( 'iamalive.unique_number' );
     
      # commit ID stuff to STATE file
      my $status = $PING->save( $ping_file );           
      # build the IAMALIVE message
      my $alive;
#      unless ( $server =~ "131.215"  ) {  # VOEvents for Caltech
         my $object = new XML::Document::Transport();
         $alive = $object->build(
         Role      => 'iamalive',
	 Origin    => 'ivo://uk.org.estar/estar.broker#',
	 TimeStamp => $timestamp );
#      } else {
#        my $object = new Astro::VO::VOEvent();
#        $alive = $object->build( 
#           Role => 'iamalive',
#	   ID   => 'ivo://uk.org.estar/estar.broker#' . $id ,
#	   Who  => { AuthorIVORN => 'ivo://uk.org.estar/estar.broker#',
#	             Date        => $timestamp,
#	  	   } );	
#      }
      
      # work out message length
      #my $header = pack( "N", 7 );
      my $bytes = pack( "N", length($alive) ); 
   
      # send message                                   
      $log->debug( "Sending " . length($alive) . " bytes to $server" );
      $log->debug( $alive ); 
                     
      #print $c $header if $server =~ /lanl\.gov/; # RAPTOR specific hack
      print $c $bytes;
      $c->flush();
      print $c $alive;
      $c->flush();  
  
      # Wait for IAMALIVE response
      $log->debug( "Waiting for response..." );
      my $length;
      my $bytes_read;

      eval {
        local $SIG{ALRM} = sub {die "Socket connection timed out waiting for IAMALIVE response";};
        alarm $config->get_option( "connection.timeout" );
        $bytes_read = sysread( $c, $length, 4 ); 
	alarm 0;
      };
      alarm 0;

      # The semaphore is a possible race condition if the other thread
      # has dropped first, it'll go into the @$tid_down array and then
      # when the client reconnects from that IP it'll immediately get
      # disconnected. This may cause "zombie" IAMALIVE processes to
      # hang around. Ouch!
      if ($@) {
        my $error = "$@";
	chomp $error;
	$log->error( "Error: $error" );
        $log->warn( "Dropping connection to $server" );
        $log->warn( "Closing socket to $server (IAMALIVE)" );
	close( $c );
	lock( @$tid_down );
	$log->warn( "Sempahoring other threads via \@\$tid_down..");
	push @$tid_down, $server; 
        return ESTAR__FAULT;
        
      }        
      $length = unpack( "N", $length );
      
      if ( $bytes_read == 0 ) {
        $log->warn( "Recieved an empty packet..." );
        $log->warn( "Dropping connection to $server" );
        $log->warn( "Closing socket to $server (IAMALIVE)" );
	close( $c );
        return ESTAR__FAULT;
        
      }  
             
      $log->debug( "Message is $length characters" );
      if ( $length > 512000 ) {
         $log->error( "Error: Message length is > 512000 characters" );
         $log->error( "Error: Message claims to be $length long" );
         $log->warn( "Warning: Discarding bogus message" );
      } else {   
  
         my $response;               
         $bytes_read = sysread( $c, $response, $length); 
                  
         # Do I get an ACK or a IAMALIVE message? (Expecting IAMALIVE)
         # --------------------------------------
         my $message;
	 if ( $response =~ /Transport/ ) {
            $log->debug( "This looks like a Transport document..." );
            eval {$message = new XML::Document::Transport(XML => $response);};
            if ( $@ ) {
               my $error = "$@";
               chomp( $error );
               $log->error( "Error: $error" );
               $log->error( $message );
            }   
         } elsif ( $response =~ /VOEvent/ ) {
            $log->error("Error: Message appears to be a <VOEvent>");
            eval { $message = new Astro::VO::VOEvent( XML => $response ); };	 
            if ( $@ ) {
               my $error = "$@";
	       chomp ( $error );
	       $log->error( "Error: Cannot parse VOEvent message" );
	       $log->error( "Error: $error" );
	       $log->error( $response );
	    }
	 } else {
	    $log->error( "Error: Cannot indentify message type" );
	    $log->error( $response );	      
	 }
	 if ( defined $message ) {
	    
            if( $message->role() eq "ack" ) {
              $log->warn( "Warning: Recieved an ACK message from $server");
              $log->warn( "Warning: This should have been an IAMALIVE message"); 
	      my $timestamp = eSTAR::Broker::Util::time_iso(); 
              $log->debug( "Reply timestamp: $timestamp");
	      $log->debug( $response );
              $log->debug( "Done." );
        
            } elsif ( $message->role() eq "iamalive" ) {       
              $log->print( "Recieved an IAMALIVE message from $server");
              my $timestamp = eSTAR::Broker::Util::time_iso(); 
              $log->debug( "Reply timestamp: $timestamp");
              $log->debug( $response );
              $log->debug( "Done." );
            }  
         } else {
	 
	    # we don't seem to have a message. That's bad
	    $log->error( "Error: Have not been able to parse message" );
	    $log->error( $response );	
	 }   	 
         $log->warn("Warning: $response");


      }
       
            
      # finished ping, loop to while(1) { ]
      $log->debug( "Done sending IAMALIVE to $server, next message in " .
                      $config->get_option( "broker.ping" ) . " seconds" );
   }
   
   $log->warn( "Warning: Shutting down IAMALIVE connection to $server");
   
}; 

my $broker_callback = sub {
   my $c = shift;
   my $server = shift;
   
   my $tid = threads->tid();
   $run->register_tid( $tid, $server );
   
   # create IAMALIVE thread
   $log->debug( "Starting IAMALIVE callback...");  
   $log->debug( "Pinging $server every " .
                 $config->get_option( "broker.ping") . " seconds..." );

   # Spawn the thread that will send IAMALIVE messages to the client
   $log->print("Spawning IAMAMLIVE thread...");
   my $iamalive_thread = threads->create( \&$iamalive, $c, $server );
   $iamalive_thread->detach();
      
   # DROP INTO LOOP HERE LOOKING FOR NEW EVENT MESSAGES TO PASS ON
   while ( 1 ) { 
     sleep(5);  # REMOVE BEFORE FLIGHT TAG
   
     my $connect = $c->connected();
     unless( defined $connect ) {
        $log->warn( "Closing socket to $server (tid = $tid)" );
	$run->deregister_tid( $tid );
	close( $c );
	last;
     }
     
     {
        lock( @$tid_down );
        foreach my $i ( 0 ... $#$tid_down ) {
	   if ( $$tid_down[$i] eq $server ) {
	      delete $$tid_down[$i];
              my $error = "Socket closed from another thread";
              chomp $error;
              $log->error( "Error: $error" );
              $log->warn( "Dropping connection to $server" );
              $log->warn( "De-registering thread (tid = $tid)" );
              $run->deregister_tid( $tid );
              $log->warn( "Closing socket to $server (tid = $tid)" );
              close( $c );
              return ESTAR__FAULT;
	   }    
        }
     }      
       
     # 1) Check to see if there are any event messages in %messages
     # 2) Check %collected to see whether we've picked this one up before
     # 3) If new, and not collected, set collected, and forward it
     
     # (1) & (2)
     $log->debug("(tid = $tid) Checking for uncollected messages..." );
     my @uncollected = $run->list_messages();
     my $id;
     my $have_message;
     foreach my $i ( 0 ... $#uncollected ) {
	 $id = $uncollected[$i];
         unless( $run->is_collected( $tid, $uncollected[$i] ) ) {
	    
            # Can't set it collected here, it might get garbage
            # collected before we dispatch it to our client
            $log->debug( "(tid = $tid) Forwarding $id..." );
	    $have_message = 1;
	    last;
	 } else {
            $log->debug( "(tid = $tid) Already collected $id..."); 
            
         }    
     } 
     
     # loop if we don't have a message to forward
     next unless $have_message;
     
     # we have a message, but we need to reset the $have_message
     # flag so we don't go here again until we have another
     $have_message = undef;
  
     # (3) Send the messages to the client
     my $xml = $run->get_message( $id );

     # Set it as collected, we don't need to access the Running object
     # from this thread anymore.
     $run->set_collected( $tid, $id );
     $log->debug( "(tid = $tid) Setting $id as collected..." );
          
     # work out message length
     #my $header = pack( "N", 7 );
     my $bytes = pack( "N", length($xml) ); 
  
     # send message				      
     $log->debug( "Sending " . length($xml) . " bytes to $server" );
     $log->debug( $xml ); 
		    
     #print $c $header if $server =~ /lanl\.gov/; # RAPTOR specific hack
     print $c $bytes;
     $c->flush();
     print $c $xml;
     $c->flush();   

     # Wait for ACK response
     $log->debug( "Waiting for response..." );
     my $length;
     my $bytes_read;

     eval {
       local $SIG{ALRM} = sub {die "Socket connection timed out waiting for ACK response";};
       alarm $config->get_option( "connection.timeout" );
       $bytes_read = sysread( $c, $length, 4 ); 
       alarm 0;
     };
     alarm 0;

#     $SIG{ALRM} = sub { 
#        my $error = "socket connection timed out";
#        throw eSTAR::Error::FatalError($error, ESTAR__FATAL); };
#     eval {
#       alarm $config->get_option( "connection.timeout" );
#       $bytes_read = sysread( $c, $length, 4 );  
#       alarm 0
#     };
#     alarm 0;
     
     if ($@) {
       my $error = "$@";
       chomp $error;
       $log->error( "Error: $error" );
       $log->warn( "Dropping connection to $server" );
       $log->warn( "De-registering thread (tid = $tid)" );
       $run->deregister_tid( $tid );
       $log->warn( "Closing socket to $server (tid = $tid)" );
       close( $c );
       return ESTAR__FAULT;
       
     }      
     
     $length = unpack( "N", $length );

     if ( $bytes_read == 0 ) {
        $log->warn( "Recieved an empty packet..." );
        $log->warn( "Dropping connection to $server" );
        $log->warn( "De-registering thread (tid = $tid)" );
	$run->deregister_tid( $tid );
        $log->warn( "Closing socket to $server (tid = $tid)" );
	close( $c );
        return ESTAR__FAULT;
        
     }  
      
     $log->debug( "Message is $length characters" );
     if ( $length > 512000 ) {
         $log->error( "Error: Message length is > 512000 characters" );
         $log->error( "Error: Message claims to be $length long" );
         $log->warn( "Warning: Discarding bogus message" );
     } else {   

       my $response;		 
       $bytes_read = sysread( $c, $response, $length);                  

       # Do I get an ACK or a IAMALIVE message? (Expecting ACK)
       # --------------------------------------
       my $message;
       if ( $response =~ /Transport/ ) {
          $log->debug( "This looks like a Transport document..." );
          eval {$message = new XML::Document::Transport(XML => $response);};
          if ( $@ ) {
             my $error = "$@";
             chomp( $error );
             $log->error( "Error: $error" );
             $log->error( $message );
          }   
       } elsif ( $response =~ /VOEvent/ ) {
          $log->error("Error: Message appears to be a <VOEvent>");
          eval { $message = new Astro::VO::VOEvent( XML => $response ); };     
          if ( $@ ) {
             my $error = "$@";
             chomp ( $error );
             $log->error( "Error: Cannot parse VOEvent message" );
             $log->error( "Error: $error" );
             $log->error( $response );
          }
       } else {
          $log->error( "Error: Cannot indentify message type" );
          $log->error( $response );	    
       }
       if ( defined $message ) {
          
            if( $message->role() eq "ack" ) {
              $log->print( "Recieved an ACK message from $server"); 
	      my $timestamp = eSTAR::Broker::Util::time_iso(); 
              $log->debug( "Reply timestamp: $timestamp");
	      $log->debug( $response );
              $log->debug( "Done." );
        
            } elsif ( $message->role() eq "iamalive" ) {       
              $log->warn( "Warning: Recieved an IAMALIVE message from $server");
              $log->warn( "Warning: This should have been an ACK message");
	      my $timestamp = eSTAR::Broker::Util::time_iso(); 
              $log->debug( "Reply timestamp: $timestamp");
              $log->debug( $response );
              $log->debug( "Done." );
            }
       }  
     }
     
     # finished ping, loop to while(1) { ]
     $log->debug( "Done sending IAMALIVE to $server, next message in " .
		  $config->get_option( "broker.ping" ) . " seconds" );     
     
          
          
   }


};

my $broker = sub { 
  
  my $server_sock;
  SERVER: {
   $log->print( "Starting TCP/IP server..." );
   $server_sock = new IO::Socket::INET( 
		  LocalHost => $config->get_option( "broker.host" ),
		  LocalPort => $config->get_option( "broker.port" ),
		  Proto     => 'tcp',
		  Listen    => 2,
		  Reuse     => 1,
		  Timeout  => $config->get_option( "connection.timeout" ) ); 

   unless ( $server_sock ) {	           
       my $error = "$@";
       chomp($error);
       $log->warn("Warning: $error");
       $log->warn("Warning: Trying to restart TCP server on port " .
                  $config->get_option( "broker.port" ) );
       sleep 5;
       redo SERVER;
   };        
   $log->print( "Server started on port ".$config->get_option( "broker.port" ) );
  
  }

  while( !$server_flag ) {
     next unless my $c = $server_sock->accept();
     
     my $server = $c->peerhost();
     	
     $log->print("Accepted connection from $server" ); 
     $log->debug("Spawning server thread to handle the connection..." ); 
     my $thread = threads->new( \&$broker_callback, $c, $server );
     $thread->detach();
     $log->debug("Closing socket in main thread..." ); 
     close( $c );
     
  
  } 
  $log->error( "Error: Shutting down broker on port " .
               $config->get_option( "broker.port" ) );
  $log->error( "Error: Stopping server..." );
  return ESTAR__FAULT;
};  

# ===========================================================================
# M A I N   B L O C K 
# ===========================================================================

# OPENING CLIENT CONNECTIONS ------------------------------------------------

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

# TCP SERVER ----------------------------------------------------------------

my $server_thread =  threads->create( \&$broker );
$server_thread->detach();

# SOAP SERVER ---------------------------------------------------------------

# anonymous subroutine which starts a SOAP server which will accept
# incoming SOAP requests and route them to the appropriate module
my $soap_server = sub {
   my $thread_name = "SOAP Thread";
   
   # create SOAP daemon
   $log->thread($thread_name,"Starting SOAP server (\$tid = ".threads->tid().")");  
   my $daemon = eval{ new eSTAR::UA::SOAP::Daemon( 
                      LocalPort     => $config->get_option( "broker.soap"),
                      Listen        => 5, 
                      Reuse         => 1 ) };   
                    
   if ($@) {
      # If we restart the user agent process quickly after a crash the port 
      # will still be blocked by the operating system and we won't be able 
      # to start the daemon. Other than the port being in use I can't see
      # why we're going to end up here.
      my $error = "$@";
      chomp($error);
      return "FatalError: $error";
   };
   
   # print some info
   $log->thread($thread_name, "SOAP server at " . $daemon->url() );
   #$log->thread($thread_name, "Certificate ".$CONFIG->param("ssl.cert_file"));
   #$log->thread($thread_name, "Key File ".$CONFIG->param("ssl.cert_key")  );     
    
   # handlers directory
   my $handler = "eSTAR::Broker::SOAP::Handler";
   
   # defined handlers for the server
   $daemon->dispatch_with({ 'urn:/event_broker' => $handler });
   $daemon->objects_by_reference( $handler );
      
   # handle it!
   $log->thread($thread_name, "Starting handlers..."  );
   $daemon->handle;

};

# S T A R T   S O A P   S E R V E R -----------------------------------------

# Spawn the SOAP server thread
$log->print("Spawning SOAP Server thread...");
my $listener_thread = threads->create( \&$soap_server );
$listener_thread->detach();

# MAIN LOOP -----------------------------------------------------------------	  

$log->print( "Entering main garbage collection loop..." );
while(1) {
    sleep $config->get_option( "broker.garbage" );
    $log->print( "Garbage collection at " . ctime() );
    
    my %tids = $run->dump_tids();
    my @tids = keys %tids;
    my @servers = values %tids;

    unless ( scalar( @servers ) > 0 ) {
       $log->debug( "There are no active client connections...");
    } else {
       foreach my $key ( sort keys %tids ) {
          $log->debug ( "Handler \$tid = $key: connected to $tids{$key}" );
       }   
    
       my %messages = $run->list_messages();
       my @ids = keys %messages;
       my $num = scalar( @ids );
       if ( $num == 0 ) {
          $log->debug( "There are no queued messages from these machines");
       } else {
          $log->debug( "There are $num messages in the queue" );
       }
    }
    
    # Remove message id off %messages when all @tids have collected it
    # Also need to remove all mention of the message id from the
    # %collected hash. No point running this if we don't have any
    # live connections though.
    unless( scalar( @servers ) == 0 ) {
       $log->debug( "Running garabage_collect( ) routine");
       $run->garbage_collect();
    } else {
       $log->debug( "Running delete_messages( ) routine");
       my $messages = $run->delete_messages();
       unless ( defined $messages ) {
          $log->warn( "Warning: The message hash was not garbage collected");
          $log->warn( "Warning: There may be currently connected clients");
       } else { 
          if ( $messages == 0 ) {
             $log->debug( "The message hash was empty...");
          } elsif ( $messages == 1 ) {  
             $log->debug( "Deleted $messages message from the message hash");
          } else {
             $log->debug( "Deleted $messages messages from the message hash");
          }             
       }
    }   
    $log->debug( $run->dump_self() );
    $log->print( "Done with garbage collection" );
}	
  
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
# Revision 1.114  2008/07/10 13:17:05  aa
# rogue role='utiltiy' messages
#
# Revision 1.113  2008/04/06 21:57:25  aa
# Added tinyurl.com encoding
#
# Revision 1.112  2008/04/05 21:45:31  aa
# bug fixes
#
# Revision 1.111  2008/04/05 19:07:08  aa
# bug fix
#
# Revision 1.110  2008/04/05 19:06:10  aa
# bug fix
#
# Revision 1.109  2008/04/05 19:05:02  aa
# bug fix
#
# Revision 1.108  2008/04/05 18:53:33  aa
# Added twittering
#
# Revision 1.107  2008/03/25 14:42:50  aa
# Updated lion.drogon.net to estar.org.uk
#
# Revision 1.106  2008/03/14 16:11:15  aa
# Bug fix and commented out LANL
#
# Revision 1.105  2007/04/02 14:31:53  aa
# Added NOAO server to default list
#
# Revision 1.104  2006/07/05 23:46:56  aa
# Now ignoes role='utility' messages
#
# Revision 1.103  2006/07/05 21:40:32  aa
# bug fix
#
# Revision 1.102  2006/07/05 21:37:13  aa
# bug fix
#
# Revision 1.101  2006/07/05 21:35:24  aa
# Write param in ACK for location stored even if not using other port callback
#
# Revision 1.100  2006/06/14 20:45:08  aa
# bug fix
#
# Revision 1.99  2006/06/14 19:57:42  aa
# bug fix
#
# Revision 1.98  2006/06/14 19:54:25  aa
# bug fix
#
# Revision 1.97  2006/06/14 19:48:16  aa
# bug fix
#
# Revision 1.96  2006/06/14 07:29:41  aa
# Added some comments
#
# Revision 1.95  2006/06/14 07:13:08  aa
# Added a chek in the IAMALIVE callback to check tha the thread sending event messages is actually still connected to the server. If it dies for whatever reason we kill the IAMALIVE socket
#
# Revision 1.94  2006/06/14 00:38:50  aa
# bug fix
#
# Revision 1.93  2006/06/14 00:29:12  aa
# bug fix
#
# Revision 1.92  2006/06/14 00:25:30  aa
# bug fix
#
# Revision 1.91  2006/06/14 00:22:56  aa
# bug fix
#
# Revision 1.90  2006/06/14 00:19:47  aa
# fixed bug in parsing ACK and IAMALIVE messages
#
# Revision 1.89  2006/06/13 01:10:01  aa
# Fixed alarm clock error this time?
#
# Revision 1.88  2006/06/13 01:07:07  aa
# Fixed alarm clock error this time?
#
# Revision 1.87  2006/06/13 00:48:10  aa
# Fixed alarm clock error this time?
#
# Revision 1.86  2006/06/13 00:44:08  aa
# Fixed alarm clock error this time?
#
# Revision 1.85  2006/06/13 00:40:45  aa
# Fixed alarm clock error this time?
#
# Revision 1.84  2006/06/13 00:31:18  aa
# Fixed alarm clock error this time?
#
# Revision 1.83  2006/06/13 00:29:27  aa
# Fixed alarm clock error this time?
#
# Revision 1.82  2006/06/13 00:20:21  aa
# Fixed alarm clock error this time?
#
# Revision 1.81  2006/06/13 00:17:36  aa
# Fixed alarm clock error this time?
#
# Revision 1.80  2006/06/12 20:46:55  aa
# more debugging
#
# Revision 1.79  2006/06/09 23:13:27  aa
# Removed Caltech special case (again)
#
# Revision 1.78  2006/06/09 00:35:06  aa
# Re-added special case for Caltech, ho hum!
#
# Revision 1.77  2006/06/09 00:15:08  aa
# Turned off VOEvent response for Caltech, turned on Transport
#
# Revision 1.76  2006/06/08 21:44:20  aa
# bug fix
#
# Revision 1.75  2006/06/08 21:24:02  aa
# bug fix
#
# Revision 1.74  2006/06/08 20:56:57  aa
# bug fix
#
# Revision 1.73  2006/06/08 20:04:16  aa
# Bug Fix, more Alarm Clock issues??
#
# Revision 1.72  2006/06/08 19:18:12  aa
# bug fix for Alarm Clock issues?
#
# Revision 1.71  2006/06/07 22:53:05  aa
# Moved to <Transport> documents for everyone connecting, except for Caltech
#
# Revision 1.70  2006/06/07 22:02:35  aa
# use of the new XML::Document::Transport class
#
# Revision 1.69  2006/06/07 20:11:50  aa
# bug fix
#
# Revision 1.68  2006/06/07 19:25:41  aa
# bug fix
#
# Revision 1.67  2006/06/07 18:01:00  aa
# Initial move to <Transport>
#
# Revision 1.66  2006/06/06 19:54:30  aa
# Updated end points
#
# Revision 1.65  2006/05/19 22:15:12  aa
# Added more debug
#
# Revision 1.64  2006/05/19 21:58:52  aa
# Moved to VOEvent v1.1
#
# Revision 1.63  2006/05/11 15:36:52  aa
# Event related changes
#
# Revision 1.62  2006/03/21 09:50:49  aa
# Changed RAPTOR port to use STC
#
# Revision 1.61  2006/03/08 09:52:33  aa
# Added sysread wrapping for timeouts and ack messages to SOAP interface
#
# Revision 1.60  2006/03/07 09:59:54  aa
# Added skeleton SOAP daemon to event_broker.pl
#
# Revision 1.59  2006/02/16 22:56:47  aa
# Fixed bug where it would actually read bogus length messages before discarding them, ooops! Now discards the messages before filling the entire memory of the machine iwth junk.
#
# Revision 1.58  2006/01/20 10:05:11  aa
# Fixed ACK bug
#
# Revision 1.57  2006/01/20 09:46:25  aa
# Added Caltech relay to default configuration
#
# Revision 1.56  2006/01/20 09:24:18  aa
# big fix
#
# Revision 1.55  2006/01/20 09:19:03  aa
# Fixed IVORNs
#
# Revision 1.54  2006/01/19 11:15:31  aa
# bug fixes
#
# Revision 1.53  2006/01/19 10:40:43  aa
# bug fix
#
# Revision 1.52  2006/01/19 10:36:46  aa
# Added a pubDate attribute to each RSS feed item
#
# Revision 1.51  2006/01/19 10:34:56  aa
# Fixed RAPTOR specific hacks
#
# Revision 1.50  2006/01/12 15:35:11  aa
# Added other port response IAMALIVE echoing, I think
#
# Revision 1.49  2006/01/12 15:26:00  aa
# Major big fix to event broker
#
# Revision 1.48  2005/12/28 16:25:24  aa
# Bug fixes
#
# Revision 1.47  2005/12/28 16:15:54  aa
# Bug fix, will clean out the messages hash if there are no connected clients during the garbage connection phase
#
# Revision 1.46  2005/12/28 15:29:30  aa
# Bug fixes
#
# Revision 1.45  2005/12/28 14:22:05  aa
# Added test server and some minor bug fixes
#
# Revision 1.44  2005/12/26 10:28:41  aa
# Bug fix
#
# Revision 1.43  2005/12/26 10:26:35  aa
# Bug fix
#
# Revision 1.42  2005/12/26 10:25:41  aa
# Bug fix
#
# Revision 1.41  2005/12/26 10:21:39  aa
# Working event_broker.pl
#
# Revision 1.40  2005/12/23 19:04:42  aa
# Bug fix
#
# Revision 1.39  2005/12/23 18:57:16  aa
# Bug fix
#
# Revision 1.38  2005/12/23 18:55:51  aa
# Bug fix
#
# Revision 1.37  2005/12/23 18:44:02  aa
# Bug fix
#
# Revision 1.36  2005/12/23 18:43:17  aa
# Bug fix
#
# Revision 1.35  2005/12/23 18:42:22  aa
# Added forwarding, but no garbage collection yet
#
# Revision 1.34  2005/12/23 17:57:49  aa
# functionality?
#
# Revision 1.33  2005/12/23 17:16:46  aa
# Bug fix
#
# Revision 1.32  2005/12/23 17:15:11  aa
# Bug fix
#
# Revision 1.31  2005/12/23 17:14:49  aa
# Bug fix
#
# Revision 1.30  2005/12/23 17:14:14  aa
# removed debuggging code
#
# Revision 1.29  2005/12/23 17:13:48  aa
# Bug fix, handed test code to see if we're sharing the running hashes correctly between threads
#
# Revision 1.28  2005/12/23 17:07:17  aa
# Bug fix
#
# Revision 1.27  2005/12/23 17:04:03  aa
# Bug fix
#
# Revision 1.26  2005/12/23 16:54:06  aa
# Bug fix
#
# Revision 1.25  2005/12/23 16:47:31  aa
# Bug fix
#
# Revision 1.24  2005/12/23 16:45:03  aa
# Bug fix
#
# Revision 1.23  2005/12/23 16:44:27  aa
# Bug fix
#
# Revision 1.22  2005/12/23 16:38:32  aa
# Bug fix
#
# Revision 1.21  2005/12/23 16:17:45  aa
# Added test harness code
#
# Revision 1.20  2005/12/23 15:49:39  aa
# More work on shared hashes
#
# Revision 1.19  2005/12/23 15:30:30  aa
# Bug fix
#
# Revision 1.18  2005/12/23 15:30:00  aa
# Bug fix
#
# Revision 1.17  2005/12/23 15:29:27  aa
# Added shared messages and collected hashes in preparation for pasing messages between the client and server threads.
#
# Revision 1.16  2005/12/23 14:43:19  aa
# Bug fix
#
# Revision 1.15  2005/12/23 14:42:29  aa
# Bug fix
#
# Revision 1.14  2005/12/23 14:02:53  aa
# Bug fix
#
# Revision 1.13  2005/12/23 14:02:20  aa
# Bug fix
#
# Revision 1.12  2005/12/23 14:00:33  aa
# Bug fix
#
# Revision 1.11  2005/12/23 14:00:03  aa
# Bug fix
#
# Revision 1.10  2005/12/23 13:50:34  aa
# Bug fix
#
# Revision 1.9  2005/12/23 13:48:55  aa
# Added server thread to event_broker.pl
#
# Revision 1.8  2005/12/21 20:36:00  aa
# Bug fixes to Event Broker and startup script
#
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


