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

C<raptor_alert.pl> - Handles incoming events from RAPTOR

=head1 SYNOPSIS

   raptor_alert.pl [-vers]

=head1 DESCRIPTION

C<raptor_alert.pl> is a persitent component of the the eSTAR Intelligent 
Agent Client Software. The C<raptor_alert.pl> is an simple gateway for
incoming alerts from the RAPTOR system.

=head1 REVISION

$Id: raptor_alert.pl,v 1.7 2005/11/28 14:18:39 aa Exp $

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
      print "\neSTAR RAPTOR Alert Software:\n";
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
use Astro::VO::VOEvent;

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
use XML::Atom::Feed;
use XML::Atom::Entry; 
use XML::Atom::Person;
use XML::Atom::Link;
use Net::FTP;

my $name;
GetOptions( "name=s" => \$name );

my $process_name;
if ( defined $name ) {
  $process_name = "raptor_alert_" . $name;
} else { 
  $process_name = "raptor_alert";
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
$log->header("Starting RAPTOR Alert: Version $VERSION");

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
use Time::localtime;

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
use eSTAR::RAPTOR::Util;

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
 
   # RAPTOR server parameters
   #$config->set_option( "raptor.host", "144.173.229.16" );
   $config->set_option( "raptor.host", "astro.lanl.gov" );
   $config->set_option( "raptor.port", 43002 );
   
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
$lwp->agent( "eSTAR RAPTOR Alert Daemon /$VERSION (" 
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
  $log->thread2($thread_name, "Callback from TCP client at " . ctime() . "...");
  $log->thread2($thread_name, "Handling broadcast message from RAPTOR");


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
  } else {
     $log->debug( "Doesn't look like the document is an RTML message..." );
  }   

  # It really, really should be a VOEvent message
  $log->debug( "Testing to see whether we have a VOEvent document..." );
  my $voevent;
  if ( $message =~ /VOEvent/ ) {
     $log->debug( "This looks like a VOEvent document..." );
     $log->print( $message );
     
     # Reading from alert.log file
     # ---------------------------
     my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
     my $alert = File::Spec->catfile( $state_dir, "alert.log" );
     
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
     use Data::Dumper; print "\@files = " . Dumper( @files );
     
     $log->debug("Closing alert.log file...");
     close(LOG);
          
     # Writing to atom.xml
     # -------------------
     my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
     my $atom = File::Spec->catfile( $state_dir, "atom.xml" );
        
     $log->debug("Creating Atom file: $atom");  
          
     # write the observation object to disk.
     unless ( open ( ATOM, ">$atom" )) {
        my $error = "Warning: Can not write to "  . $state_dir; 
        $log->error( $error );
        throw eSTAR::Error::FatalError($error, ESTAR__FATAL);   
     } else {
        unless ( flock( ATOM, LOCK_EX ) ) {
          my $error = "Warning: unable to acquire exclusive lock: $!";
          $log->error( $error );
          throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
        } else {
          $log->debug("Acquiring exclusive lock...");
        }
     }                  
     
     $log->print( "Creating Atom feed..." );     
          
     # Create atom.xml file 
     my $feed = new XML::Atom::Feed( Version => '1.0' );
     $feed->title( "eSTAR/TALONS GCN Feed" );
     my $author = new XML::Atom::Person();
     $author->name( "eSTAR Project" );
     $author->email( 'aa@estar.org.uk' );
     $feed->author( $author );

     my $link = new XML::Atom::Link();
     $link->type( 'application/atom+xml' );
     $link->rel( 'self' );
     $link->href( 'http://www.estar.org.uk/atom.xml' );
     $feed->add_link( $link );
      
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
        
          use Data::Dumper; print "\@data = " . Dumper( $data );
   
        $log->debug( "Determing ID of message..." );
        my $object = new Astro::VO::VOEvent();
        my $id;
        eval { $id = $object->determine_id( XML => $data ); };
        if ( $@ ) {
           $log->error( "Error: $@" );
           $log->error( "\$data = " . $data );
           $log->warn( "Warning: discarding message $i of $num_of_files" );
           next;
        } 
        $log->debug( "ID: $id" );

        $log->print( "Creating Atom Feed Entry..." );
        my $entry = new XML::Atom::Entry();
        $entry->title( $id );
        $entry->content( "<![CDATA[" . $data . "]]>" );

        my $author = new XML::Atom::Person();
        $author->name( "GCN" );
        $author->email( 'scott@milkyway.gsfc.nasa.gov' );
        $entry->author( $author );

        $log->debug( "Adding entry to feed..." );
        $feed->add_entry( $entry );

     }
     $log->debug( "Creating XML representation of feed..." );
     my $xml = $feed->as_xml();

     $log->debug( "Writing feed to $atom" );
     print ATOM $xml;
       
     # close ALERT log file
     $log->debug("Closing atom.xml file...");
     close(ATOM);    
     
     $log->debug("Opening FTP connection to lion.drogon.net...");  
     my $ftp = Net::FTP->new( "lion.drogon.net", Debug => 0 );
     $log->debug("Logging into estar account...");  
     $ftp->login( "estar", "tibileot" );
     $ftp->cwd( "www.estar.org.uk/docs" );
     $log->debug("Transfering Atom file...");  
     $ftp->put( $atom, "atom.xml" );
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
   my $bytes_read = read( $sock, $length, 4 );

   next unless defined $bytes_read;
   
   $log->print("\nRecieved a packet from RAPTOR..." );
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
         $bytes_read = read( $sock, $response, $length); 
      
         $log->debug( "Read $bytes_read characters from socket" );
      
         # callback to handle incoming Events     
         $log->print("Detaching callback thread..." );
         my $callback_thread = 
             threads->create ( $tcp_callback, $response );
         $callback_thread->detach(); 

         # log the event message
         my $file;
         eval { $file = eSTAR::RAPTOR::Util::store_voevent( $response ); };
         if ( $@  ) {
           $log->error( "Error: $@" );
         } 

         unless ( defined $file ) {
            $log->warn( "Warning: The message has not been serialised..." );
         }

         # return an ack message
         my $ack =
          "<?xml version = '1.0' encoding = 'UTF-8'?>\n" .
          '<VOEvent xmlns="http://www.ivoa.net/xml/VOEvent/v1.0' . "\n" .
          'xmlns:schemaLocation="http://www.ivoa.net/xml/STC/stc-v1.20.xsd ' .
          'http://hea-www.harvard.edu/~arots/nvometa/v1.2/stc-v1.20.xsd ' .
          'http://www.ivoa.net/xml/STC/STCcoords/v1.20 ' .
          'http://hea-www.harvard.edu/~arots/nvometa/v1.2/coords-v1.20.xsd ' .
          'http://www.ivoa.net/xml/VOEvent/v1.0 ' .
          'http://www.ivoa.net/internal/IVOA/IvoaVOEvent/VOEvent-v1.0.xsd" ' . "\n" .
          'role="ack"' . "\n" .
          'xmlns:stc="http://www.ivoa.net/xml/STC/stc-v1.20.xsd"' . "\n" .
          'version="1.0"' . "\n" .
          'xmlns:crd="http://www.ivoa.net/xml/STC/STCcoords/v1.20"' . "\n" . 
          'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"' . "\n" . 
          'id="ivo://estar.ex/ack" >' . "\n" . 
          '<Citations/>' . "\n" . 
          '<Who>' . "\n" . 
          '   <PublisherID>ivo://estar.ex/</PublisherID>' . "\n" . 
          '</Who>' . "\n" . 
          '<What>' . "\n" . 
          '   <Param value="stored" name="'. $file .'" />' . "\n" . 
          '</What>' . "\n" . 
          '<WhereWhen/>' . "\n" . 
          '<How/>' . "\n" . 
          '<Why/>' . "\n" . 
          '</VOEvent>' . "\n";

         # work out message length
         my $header = pack( "N", 7 );
         my $bytes = pack( "N", length($ack) );

         # Writing to alert.log file
         my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
         my $alert = File::Spec->catfile( $state_dir, "alert.log" );
        
         $log->debug("Opening alert log file: $alert");  
          
         # write the observation object to disk.
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
          
         # send message                                   
         $log->debug( "Sending " . length($ack) . " bytes to " . 
                      $config->get_option( "raptor.host" ));
         print $sock $header;
         print $sock $bytes;
         $sock->flush();
         print $sock $ack;
         $sock->flush(); 
         $log->debug( $ack ); 
         $log->debug( "Done, listening..." );
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
   $log->print("Killing gateway processes...");
   exit;
}                                

# T I M E   A T   T H E   B A R  -------------------------------------------

# $Log: raptor_alert.pl,v $
# Revision 1.7  2005/11/28 14:18:39  aa
# Bug fixes
#
# Revision 1.6  2005/11/28 14:17:35  aa
# Bug fixes
#
# Revision 1.5  2005/11/24 17:18:35  aa
# Updated eSTAR::Mail and usage
#
# Revision 1.4  2005/11/09 13:12:01  aa
# More debugging for RAPTOR connection, should now store event messages correctly?
#
# Revision 1.3  2005/11/02 01:51:17  aa
# Minor bug fix
#
# Revision 1.2  2005/11/02 01:46:16  aa
# First cut at ACK message back to RAPTOR
#
# Revision 1.1  2005/07/26 16:28:01  aa
# Working RAPTOR gateway
#

