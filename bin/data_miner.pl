#!/software/perl-5.8.6/bin/perl

# D O C U M E N T I O N ------------------------------------------------------

#+ 
#  Name:
#    data_miner.pl

#  Purposes:
#    Data mining process for the JAC 5th pipeline backend database

#  Language:
#    Perl script

#  Invocation:
#    Invoked by source ${ESTAR_DIR}/etc/data_miner.csh

#  Authors:
#    Alasdair Allan (aa@astro.ex.ac.uk)

#  Revision:
#     $Id: data_miner.pl,v 1.10 2005/06/30 01:04:11 aa Exp $

#  Copyright:
#     Copyright (C) 2003 University of Exeter. All Rights Reserved.

#-

# ---------------------------------------------------------------------------

# Whack, don't do it again!
use strict;

# G L O B A L S -------------------------------------------------------------

# Global variables
#  $VERSION  - CVS Revision Number
#  %OPT      - Options hash for things we don't want to be persistant
#  $log      - Handle for logging object

use vars qw / $VERSION %OPT $log $config /;

# local status variable
my $status;
 
# P O D  D O C U M E N T A T I O N ------------------------------------------

=head1 NAME

C<data_miner.pl> - data mining process

=head1 SYNOPSIS

   data_miner.pl [-vers]

=head1 DESCRIPTION

C<data_miner.pl> is the data mining component of the the eSTAR Project's
data mining process. It helps populate the survey agent's backend database.

=head1 REVISION

$Id: data_miner.pl,v 1.10 2005/06/30 01:04:11 aa Exp $

=head1 AUTHORS

Alasdair Allan (aa@astro.ex.ac.uk)

=head1 COPYRIGHT

Copyright (C) 2003 University of Exeter. All Rights Reserved.

=cut

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.10 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR Data Mining Software:\n";
      print "Version $VERSION; PERL Version: $]\n";
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
# UA modules
#
use lib $ENV{"ESTAR_PERL5LIB"};     
use eSTAR::Logging;
use eSTAR::Error qw /:try/;
use eSTAR::Constants qw /:all/;
use eSTAR::Util;
use eSTAR::Process;
use eSTAR::UserAgent;

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

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
my $process = new eSTAR::Process( "data_miner" );  

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process->set_version( $VERSION );

# need to use the generic "node_agent" urn instead of the process
# id in this case...
$process->set_urn( "data_miner" );

# C A T C H   S I G N A L S -------------------------------------------------

#  Catch as many signals as possible so that the END{} blocks work correctly
use sigtrap qw/die normal-signals error-signals/;

# make unbuffered
$|=1;					

# signals
$SIG{'INT'} = \&kill_agent;
$SIG{'PIPE'} = 'IGNORE';

# error bleeps?
$OPT{"BLEEP"} = ESTAR__OK;

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
$log->header("Starting Persistent User Agent: Version $VERSION");

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
$number = $config->get_state( "mining.unique_process" ); 
unless ( defined $number ) {
  # $number is not defined correctly (first ever run of the program?)
  $number = 0; 
}

# increment ID number
$number = $number + 1;
$config->set_state( "mining.unique_process", $number );
$log->debug("Setting mining.unique_process = $number"); 
  
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
$config->set_state( "mining.pid", getpgrp() );
  
# commit $pid to STATE file
$status = $config->write_state();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Can not read or write to state.dat file";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("Data Miner PID: " . $config->get_state( "mining.pid" ) );
}

# L A T E  L O A D I N G  M O D U L E S ------------------------------------- 

#
# System modules
#
use POSIX qw/:sys_wait_h/;
use Errno qw/EAGAIN/;
#use Proc::Simple;
#use Proc::Killfam;
use Digest::MD5 'md5_hex';

#
# Networking modules
#
use Net::Domain qw(hostname hostdomain);

#
# Transport modules
#
use Socket;
use SOAP::Lite;
use HTTP::Cookies;
use URI;
use LWP::UserAgent;
use Net::FTP;

#
# IO modules
#

#
# Astro modules
#
use Astro::SIMBAD::Query;

#
# eSTAR modules
#
use eSTAR::Miner::SOAP::Daemon;  # replacement for SOAP::Transport::HTTP::Daemon
use eSTAR::Miner::SOAP::Handler; # SOAP layer ontop of handler class



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

if ( $config->get_state("mining.unique_process") == 1 ) {

   my %user_id;
   tie %user_id, "CfgTie::TieUser";
      
   # grab current user
   my $current_user = $user_id{$ENV{"USER"}};
   my $real_name = ${$current_user}{"GCOS"};
   
   # grab current IP address
   my $ip = inet_ntoa(scalar(gethostbyname(hostname())));
  
   # user defaults
   $config->set_option("user.user_name", $ENV{"USER"} );
   $config->set_option("user.real_name", $real_name );
   $config->set_option("user.email_address", $ENV{"USER"} . "@" .hostdomain() );
   $config->set_option("user.institution", "eSTAR Project" );
   
   # server parameters
   $config->set_option("server.host", $ip );
   $config->set_option("server.port", 8006 );
   
   # db web service parameters
   $config->set_option("db.host", $ip );
   $config->set_option("db.port", 8005 );
   $config->set_option("db.urn", "wfcam_agent" );
     
   # user agent parameters
   $config->set_option("agent.port", 8000 );
   
   # interprocess communication
   $config->set_option("agent.user", "agent" );
   $config->set_option("agent.passwd", "InterProcessCommunication" );

   # USNO-A2 options defaults
   $config->set_option("usnoa2.radius", 10);
   $config->set_option("usnoa2.nout", 9000);
   $config->set_option("usnoa2.url", "archive.eso.org" );
   
   # 2MASS options defaults
   $config->set_option("2mass.radius", 4 );
   
   # SIMBAD option defaults
   $config->set_option("simbad.error", 5 );
   $config->set_option("simbad.units", "arcsec");
   $config->set_option("simbad.url", "simbad.u-strasbg.fr" );
   
   # connection options defaults
   $config->set_option("connection.timeout", 5 );
   $config->set_option("connection.proxy", 'NONE'  );
  
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
$lwp->agent( "eSTAR Data Miner /$VERSION (" 
            . hostname() . "." . hostdomain() .")");

my $ua = new eSTAR::UserAgent(  );  
$ua->set_ua( $lwp );

# ===========================================================================
# M A I N   B L O C K 
# ===========================================================================

# A N O N Y M O U S   S U B - R O U T I N E S -------------------------------

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
   my $thread_name = "Server Thread";
   
   # create SOAP daemon
   $log->thread($thread_name, "Starting server (\$tid = ".threads->tid().")");  
   $daemon = eval{ new eSTAR::Miner::SOAP::Daemon( 
                      LocalPort     => $config->get_option( "server.port"),
                      Listen        => 5, 
                      Reuse         => 1 ) };   
                    
   if ($@) {
      # If we restart the agent process quickly after a crash the port 
      # will still be blocked by the operating system and we won't be able 
      # to start the daemon. Other than the port being in use I can't see
      # why we're going to end up here.
      my $error = "$@";
      chomp($error);
      return "FatalError: $error";
   };
   
   # print some info
   $log->thread($thread_name, "SOAP server at " . $daemon->url() );    
    
   # handlers directory
   my $handler = "eSTAR::Miner::SOAP::Handler";
   
   # defined handlers for the server
   $daemon->dispatch_with({ 'urn:/data_miner' => $handler });
   $daemon->objects_by_reference( $handler );
      
   # handle it!
   $log->thread($thread_name, "Starting handlers..."  );
   $daemon->handle;

};

# S T A R T   S O A P   S E R V E R -----------------------------------------

# Spawn the SOAP server thread
$log->print("Spawning SOAP Server thread...");
$listener_thread = threads->create( $soap_server );

# ===========================================================================
# E N D 
# ===========================================================================

# Wait for threads to join, this shouldn't happen under normal circumstances
# so we must have generated an error if they do, catch the returned status
# on the join and try and exit gracefully.
$status = $listener_thread->join() if defined $listener_thread;
$log->error( $status );
$log->warn( "Warning: Data mining process has been terminated abnormally..." );

# tidy up
END {
   # we must have generated an error somewhere to have gotten here,
   # run the exit code to clean(ish)ly shutdown the agent.
   kill_agent( ESTAR__FATAL );
}

# ===========================================================================
# A S S O C I A T E D   S U B R O U T I N E S 
# ===========================================================================

# anonymous subroutine which is called everytime the data mining process is
# terminated (ab)normally. Hopefully this will provide a clean exit.
sub kill_agent {
   my $from = shift;
   
   # Check to see whether we've been called via a SOAP message
   if (  $from == ESTAR__FATAL ) {  
      $log->debug("Calling kill_agent( ESTAR__FATAL )");
      $log->warn("Warning: Shutting down process after ESTAR__FATAL error...");
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
   $log->print("Killing user_agent processes...");

   # close out log files
   $log->closeout();
   
   # ring my bell, baby
   #if ( $OPT{"BLEEP"} == ESTAR__OK ) {
   #  for (1..10) {print STDOUT "\a"; select undef,undef,undef,0.2}
   #}

   # kill -9 the agent process, hung threads should die screaming
   #killfam 9, ( $config->get_state( "mining.pid") );
   $log->warn( "Warning: Not calling killfam 9" );
   
   # close the door behind you!   
   exit;
} 
  
# T I M E   A T   T H E   B A R  -------------------------------------------

# $Log: data_miner.pl,v $
# Revision 1.10  2005/06/30 01:04:11  aa
# Added more data mining support, problem returning the result to the wfcam_agent.pl. Wonder why?
#
# Revision 1.9  2005/06/29 23:37:40  aa
# Gzipped & Base64 catalogue transfer, plus addition of a working data mining service
#
# Revision 1.8  2005/06/02 00:53:57  aa
# Shipping to summit
#
# Revision 1.7  2005/06/01 23:59:15  aa
# Updates to handle new 3rd generation code base
#
# Revision 1.6  2005/01/11 14:24:47  aa
# Minor modifications
#
# Revision 1.5  2004/11/12 14:32:04  aa
# Extensive changes to support jach_agent.pl, see ChangeLog
#
# Revision 1.4  2004/03/05 00:55:07  aa
# Minor debugging difference
#
# Revision 1.3  2004/02/21 02:56:55  aa
# Added freeze(), thaw() and melt() functions for arbitary objects
# being serialised to the ~/.estar/$process/state/ directory.
#
# Added set_state() and get_state() functions to allow access to the
# state.dat file as well as the options.dat file to which access was
# provided yesterday with the get_option() and set_option() methods.
#
# Moved all the options/state querying to eSTAR::Util and put wrapper
# methods into the Handler classes only.
#
# Wrote a datamining_client.pl script which pushes a VOTable file to
# the data_miner.pl process, along with a host:port to reply to and
# context ID. This script runs up a "fake" wfcam_agent server for the
# data_miner.pl to reply to after it has processed the pushed file.
#
# Added a handle_objects() method to the data_miner.pl, this should
# return immediately with an ACK to the client/agent calling it saying
# that everything is okay, and then return its results in an async
# manner using threads.
#
# Made eSTAR::Util use EXPORT_OK rather than EXPORT and fixed the
# class method calls (hopefully) to reflect this change.
#
# Revision 1.2  2004/02/20 03:42:29  aa
# Changed configuration options so that default options are only generated
# on the inital program run. If an option.dat and state.dat file already
# exist the user's options aren't overwritten. This is now the default
# behaviour for wfcam_agent.pl and data_miner.pl. Added "do nothing" hooks
# to the Handler(s) to query and set options in the $CONFIG file.
#
# Revision 1.1  2004/02/20 00:59:41  aa
# Added a skeleton data mining process, it has a SOAP server on port 8006
#
