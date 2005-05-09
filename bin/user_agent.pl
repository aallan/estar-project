#!/software/perl-5.8.6/bin/perl

# D O C U M E N T I O N ------------------------------------------------------

#+ 
#  Name:
#    user_agent.pl

#  Purposes:
#    eSTAR User Agent

#  Language:
#    Perl script

#  Invocation:
#    Invoked by source ${ESTAR_DIR}/etc/user_agent.csh

#  Description:
#    The eSTAR persistent user agent process

#  Authors:
#    Alasdair Allan (aa@astro.ex.ac.uk)

#  Revision:
#     $Id: user_agent.pl,v 1.14 2005/05/09 12:43:09 aa Exp $

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

C<user_agent.pl> - Persistent User Agent

=head1 SYNOPSIS

   user_agent.pl [-vers]

=head1 DESCRIPTION

C<user_agent.pl> is main persitent component of the the eSTAR Intelligent 
Agent Client Software. This is the program that is started by the user to 
talk to Discovery Nodes. It should take care of all other housekeeping duties
itself.

=head1 REVISION

$Id: user_agent.pl,v 1.14 2005/05/09 12:43:09 aa Exp $

=head1 AUTHORS

Alasdair Allan (aa@astro.ex.ac.uk)

=head1 COPYRIGHT

Copyright (C) 2003 University of Exeter. All Rights Reserved.

=cut

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.14 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR User Agent Software:\n";
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
# UA modules
#
use lib $ENV{"ESTAR_PERL5LIB"};     
use eSTAR::Logging;
use eSTAR::Error qw /:try/;
use eSTAR::Constants qw /:status/;
use eSTAR::Util;
use eSTAR::Process;
use eSTAR::UserAgent;
use eSTAR::Config;

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
use Fcntl qw(:DEFAULT :flock);

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
my $process = new eSTAR::Process( "user_agent" );  

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process->set_version( $VERSION );

# need to use the generic "node_agent" urn instead of the process
# id in this case...
$process->set_urn( "user_agent" );
   
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
$number = $config->get_state( "ua.unique_process" ); 
unless ( defined $number ) {
  # $number is not defined correctly (first ever run of the program?)
  $number = 0; 
}

# increment ID number
$number = $number + 1;
$config->set_state( "ua.unique_process", $number );
$log->debug("Setting ua.unique_process = $number"); 
  
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
$config->set_state( "ua.pid", getpgrp() );
  
# commit $pid to STATE file
$status = $config->write_state();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Can not read or write to state.dat file";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("User Agent PID: " . $config->get_state( "ua.pid" ) );
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
use eSTAR::UA::SOAP::Daemon;  # replacement for SOAP::Transport::HTTP::Daemon
use eSTAR::UA::SOAP::Handler; # SOAP layer ontop of handler class

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

if ( $config->get_state("ua.unique_process") == 1 ) {
  
   my %user_id;
   tie %user_id, "CfgTie::TieUser";
   
   # grab current user
   my $current_user = $user_id{$ENV{"USER"}};
   my $real_name = ${$current_user}{"GCOS"};
  
   # user defaults
   $config->set_option("user.user_name", $ENV{"USER"} );
   $config->set_option("user.real_name", $real_name );
   $config->set_option("user.email_address", $ENV{"USER"}."@".hostdomain());
   $config->set_option("user.institution", "eSTAR Project" );
   $config->set_option("user.notify", 1 );
   
   # server parameters
   $config->set_option("server.host", $ip );
   $config->set_option("server.port", 8000 );

   # burster agent parameters
   #$config->set_option("ba.host", $ip );
   #$config->set_option("ba.port", 8001 );

   # interprocess communication
   #$config->set_option("ba.user", "agent" );
   #$config->set_option("ba.passwd", "InterProcessCommunication" );

   # node port
   $config->set_option("dn.port", 8080 );

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
$lwp->agent( "eSTAR Persistent User Agent /$VERSION (" 
            . hostname() . "." . hostdomain() .")");

my $ua = new eSTAR::UserAgent(  );  
$ua->set_ua( $lwp );

# ===========================================================================
# K N O W N   N O D E S 
# ===========================================================================

# list of "default" known nodes
#$config->set_option( "nodes.Exeter", "dn2.astro.ex.ac.uk" );
#$config->set_option( "nodes.LJM", "150.204.240.111" );
#$config->set_option( "nodes.UKIRT", "estar.ukirt.jach.hawaii.edu" );
#$config->set_option( "nodes.LTproxy", "estar.astro.ex.ac.uk" );
$config->set_option( "nodes.FTNproxy", "estar.astro.ex.ac.uk" );
#$config->set_option( "nodes.Test", "127.0.0.1" );
$status = $config->write_option( );

# ===========================================================================
# M A I N   B L O C K 
# ===========================================================================

# grab the CERTIFICATE and KEY files from the environment
#if ( defined $ENV{"HTTPS_CERT_FILE"} ) {
#   $CONFIG->param("ssl.cert_file", $ENV{"HTTPS_CERT_FILE"} );
#   $log->debug("HTTPS_CERT_FILE = " . $CONFIG->param("ssl.cert_file") );
#} else {
#   my $error = "FatalError: Enivornment variable HTTPS_CERT_FILE unset";
#   $log->error($error);
#   throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
#} 

# grab the CERTIFICATE and KEY files from the environment
#if ( defined $ENV{"HTTPS_CERT_KEY"} ) {
#   $ENV{"HTTPS_KEY_FILE"} = $ENV{"HTTPS_CERT_KEY"};
#   $CONFIG->param("ssl.cert_key", $ENV{"HTTPS_CERT_KEY"} );
#   $log->debug("HTTPS_CERT_FILE = " . $CONFIG->param("ssl.cert_key") );
#} else {
#   my $error = "FatalError: Enivornment variable HTTPS_CERT_KEY unset";
#   $log->error($error);
#   throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
#}

# set the HTTPS_CERT_PASS environment variable from the options file
#if ( defined $CONFIG->param("ssl.cert_pass") ) {
#   $ENV{"HTTPS_CERT_PASS"} = $CONFIG->param("ssl.cert_pass");
#   $ENV{"HTTPS_PROXY_PASSWORD"} = $CONFIG->param("ssl.cert_pass");
#} else {   
   # doesn't seem to be defined in the options.dat file, lets try
   # the password to the default key shipped with the user_agent
#   $ENV{"HTTPS_CERT_PASS"} = "eSTAR PEM#002";
#   $ENV{"HTTPS_PROXY_PASSWORD"} = "eSTAR PEM#002";
#   $CONFIG->param("ssl.cert_pass", "eSTAR PEM#002")
#}

# set the HTTPS_PROXY_USERNAME environment variable from the options file
#if ( defined $CONFIG->param("ssl.cert_user") ) {
#   $ENV{"HTTPS_PROXY_USERNAME"} = $CONFIG->param("ssl.cert_user");
#} else {   
   # doesn't seem to be defined in the options.dat file, lets try
   # the password to the default key shipped with the user_agent
#   $ENV{"HTTPS_PROXY_USERNAME"} = "soap_user";
#   $CONFIG->param("ssl.cert_user", "soap_user")
#}

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
   $daemon = eval{ new eSTAR::UA::SOAP::Daemon( 
                      LocalPort     => $config->get_option( "server.port"),
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
   my $handler = "eSTAR::UA::SOAP::Handler";
   
   # defined handlers for the server
   $daemon->dispatch_with({ 'urn:/user_agent' => $handler });
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
$log->warn( "Warning: User agent has been terminated abnormally..." );

# tidy up
END {
   # we must have generated an error somewhere to have gotten here,
   # run the exit code to clean(ish)ly shutdown the agent.
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
   $log->print("Killing user_agent processes...");

   # close out log files
   $log->closeout();
   
   # ring my bell, baby
   #if ( $OPT{"BLEEP"} == ESTAR__OK ) {
   #  for (1..10) {print STDOUT "\a"; select undef,undef,undef,0.2}
   #}

   # kill -9 the agent process, hung threads should die screaming
   killfam 9, ( $config->get_state( "ua.pid") );
   #$log->warn( "Warning: Not calling killfam 9" );
   
   # close the door behind you!   
   exit;
} 
  
# T I M E   A T   T H E   B A R  -------------------------------------------

# $Log: user_agent.pl,v $
# Revision 1.14  2005/05/09 12:43:09  aa
# Updated account information to work on FTN
#
# Revision 1.13  2005/05/05 13:54:40  aa
# Working node_agent for LT and FTN. Changes to user_agent to support new RTML tags (see ChangeLog)
#
# Revision 1.12  2005/02/15 22:01:43  aa
# Fixed race conditions, see ChangeLog for details. Yuck!
#
# Revision 1.11  2005/02/15 20:41:23  aa
# Fixed race conditions
#
# Revision 1.10  2005/02/15 17:13:59  aa
# Bug fixed to handlers to fix notification problems
#
# Revision 1.9  2005/02/15 17:01:49  aa
# Bug fixes, small
#
# Revision 1.8  2005/02/15 17:00:34  aa
# More mail notification
#
# Revision 1.7  2005/02/14 20:22:44  aa
# Removed obsolete ba.* configuration, break anything?
#
# Revision 1.6  2005/01/18 21:14:48  aa
# Moved project file to singleton object
#
# Revision 1.5  2005/01/11 14:35:30  aa
# Minor bug fix
#
# Revision 1.4  2005/01/11 14:24:18  aa
# Modified user_agent.pl and supporting files to use a standard directory path, now generated from eSTAR::Config rather from the agent itself. This will let us reuse that routine for all the rest of the agents
#
# Revision 1.3  2005/01/11 01:41:25  aa
# Modified backend configuration files to use a singleton object, should be more reliable?
#
# Revision 1.2  2004/12/21 17:04:09  aa
# Fixes to store the LWP::UserAgent in a single instance object and get rid of the last $main:: references in the handler code
#
# Revision 1.1  2004/11/30 19:05:31  aa
# Working user_agent.pl, Handler.pm cleaned of most $main:: references. Only $main::OPT{http_agent} reference remains, similar to jach_agent.pl. Not tried a loopback test yet
#
# Revision 1.30  2003/08/27 10:48:42  aa
# Shipping to summit
#
# Revision 1.29  2003/08/26 21:36:56  aa
# Added 2MASS cross correlation algorithmic block, andupdated the UA and Handler appropriately
#
# Revision 1.28  2003/08/26 20:57:05  aa
# ignore this
#
# Revision 1.27  2003/08/19 18:57:35  aa
# Created eSTAR::Util class, moved general methods to this class. Moved the
# infrastructure to support the new Astro::Catalog V3.* API. Tested user agent
# against the old node agent installed on dn2.astro.ex.ac.uk, but the JAC
# and node agent have not been tested (but should work).
#
# Revision 1.26  2003/07/23 01:28:55  aa
# Shipping to muttley
#
# Revision 1.25  2003/07/21 00:55:19  aa
# Lots of changes, see ChangeLog
#
# Revision 1.24  2003/07/20 02:23:50  aa
# Moved to ForkAfterProcessing from ThreadOnAccept, broken authentication?
#
# Revision 1.23  2003/07/19 00:05:07  aa
# Shipping to NAHOKU
#
# Revision 1.22  2003/07/18 01:32:57  aa
# Syncing to nahoku.jach.hawaii.edu
#
# Revision 1.21  2003/07/15 03:32:49  aa
# Changes made at OSCON'03
#
# Revision 1.20  2003/06/27 16:38:02  aa
# Moved to IP address rather than hostnames
#
# Revision 1.19  2003/06/27 16:11:50  aa
# Changed to use raw IP rather than hostname(s)
#
# Revision 1.18  2003/06/24 14:23:03  aa
# Modified query_webcam() to use SOAP::MIME
#
# Revision 1.17  2003/06/11 01:27:09  aa
# user_agent should be able to do photometric followup in a generic manner
#
# Revision 1.16  2003/06/09 04:37:48  aa
# End of night(!) check-in, added basic handling of retruned obsverations
#
# Revision 1.15  2003/06/03 23:29:38  aa
# Interim checkin, pre-test on dn2.astro.ex.ac.uk
#
# Revision 1.14  2003/05/26 14:24:06  aa
# Updates made at home, inital stab at new_observation() functionailty
#
# Revision 1.13  2003/05/09 00:33:01  aa
# Bug Fix
#
# Revision 1.12  2003/05/09 00:18:51  aa
# Minor logging tweak
#
# Revision 1.11  2003/05/08 20:20:46  aa
# Added Buster Agent, fixed bug in eSTAR::SOAP::User
#
# Revision 1.10  2003/05/08 17:04:04  aa
# Minor log string fix
#
# Revision 1.9  2003/05/07 17:29:25  aa
# Minor twiddles not worth documenting
#
# Revision 1.8  2003/05/07 17:01:41  aa
# user_agent.pl now catches signals
#
# Revision 1.7  2003/05/06 22:59:52  aa
# Minor changes to logging output
#
# Revision 1.6  2003/05/06 21:56:07  aa
# Added logging to eSTAR::UA::Handler and authentication to main::shutdown()
#
# Revision 1.5  2003/05/06 19:18:16  aa
# Working authorisation using SOAP cookie jar backed by Berkely DB
#
# Revision 1.4  2003/05/02 19:17:09  aa
# End of day, use agent now has a threaded SOAP server
#
# Revision 1.3  2003/05/01 20:46:38  aa
# End of day checkin, SSL SOAP requests not working
#
# Revision 1.2  2003/04/30 18:55:29  aa
# Fixed logging to be process specific
#
# Revision 1.1  2003/04/29 17:37:20  aa
# Intial agent infrastructure, options and state file, some logging implemented
#
