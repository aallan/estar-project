#!/software/perl-5.8.6/bin/perl

# D O C U M E N T I O N ------------------------------------------------------

#+ 
#  Name:
#    virtual_telescope.pl

#  Purposes:
#    eSTAR simulated telescope for agent algorithm testing

#  Language:
#    Perl script

#  Invocation:
#    Invoked by source ${ESTAR_DIR}/etc/virtual_telescope.csh

#  Description:
#    An embedded agent SOAP interface connected to an emulated telescope
#    backend.

#  Authors:
#    Alasdair Allan (aa@astro.ex.ac.uk), Eric Saunders (saunders@astro.ex.ac.uk)

#  Revision:
#     $Id: virtual_telescope.pl,v 1.3 2007/04/26 10:21:15 saunders Exp $

#  Copyright:
#     Copyright (C) 2003,2006 University of Exeter. All Rights Reserved.

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

# share the lookup hash across threads

# local status variable
my $status;
   
# P O D  D O C U M E N T A T I O N ------------------------------------------

=head1 NAME

C<virtual_telescope.pl> - eSTAR simulated telescope for agent algorithm testing

=head1 SYNOPSIS

   virtual_telescope.pl [-vers]

=head1 DESCRIPTION

C<virtual_telescope.pl> is a persistent component of the eSTAR Intelligent 
Agent Client Software. The C<virtual_telescope.pl> provides a SOAP interface
that understands RTML (v2.2) and passes observation request parameters on to
the internal virtual telescope implementation. It requires an up-to-date copy
of the user database.


=head1 REVISION

$Id: virtual_telescope.pl,v 1.3 2007/04/26 10:21:15 saunders Exp $

=head1 AUTHORS

Alasdair Allan (aa@astro.ex.ac.uk), Eric Saunders (saunders@astro.ex.ac.uk)

=head1 COPYRIGHT

Copyright (C) 2003,2006 University of Exeter. All Rights Reserved.

=cut

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.3 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR Virtual Telescope Software:\n";
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
use eSTAR::ADP::Util qw( get_network_time );

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

my ( $name, $cmd_soap_port );   
GetOptions( "name=s" => \$name,
            "soap=s" => \$cmd_soap_port,);

my $process_name;
if ( defined $name ) {
  $process_name = "virtual_telescope_" . $name;
} else { 
  $process_name = "virtual_telescope";
}  

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
my $process = new eSTAR::Process( $process_name );  

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process->set_version( $VERSION );

# need to use the generic "node_agent" urn instead of the process
# id, so that the user agent thinks it's talking to an embedded agent.
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
$log->header("Starting Virtual Telescope: Version $VERSION");

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

# To a certain extent the UA must be persistent state, it needs to know about
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
$number = $config->get_state( "na.unique_process" ); 
unless ( defined $number ) {
  # $number is not defined correctly (first ever run of the program?)
  $number = 0; 
}

# increment ID number
$number = $number + 1;
$config->set_state( "na.unique_process", $number );
$log->debug("Setting na.unique_process = $number"); 
  
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
$config->set_state( "na.pid", getpgrp() );
  
# commit $pid to STATE file
$status = $config->write_state();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Can not read or write to state.dat file";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("Virtual Telescope PID: " . $config->get_state( "na.pid" ) );
}

# L A T E  L O A D I N G  M O D U L E S ------------------------------------- 

#
# System modules
#
use POSIX qw/:sys_wait_h/;
use Errno qw/EAGAIN/;
use Proc::Simple;
#use Proc::Killfam;
use Digest::MD5 'md5_hex';
use Fcntl qw(:DEFAULT :flock);
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
use SOAP::Lite;
use HTTP::Cookies;
use URI;
use LWP::UserAgent;
use Net::FTP;

#
# Astro modules
#

#
# eSTAR modules
#
use eSTAR::VT::SOAP::Daemon;  # replacement for SOAP::Transport::HTTP::Daemon
use eSTAR::VT::SOAP::Handler; # SOAP layer ontop of handler class

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
$log->debug("This machine has an IP address of $ip");

if ( $config->get_state("na.unique_process") == 1 ) {
   
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
   

   
   # interprocess communication
   $config->set_option( "ua.user", "saunders" );
   $config->set_option( "ua.passwd", "vstar" );

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

if ( defined $cmd_soap_port ) {
   $log->warn("Warning: Command line override of default port values...");
   $log->warn("Warning: Setting SOAP port to $cmd_soap_port");
   $config->set_option("soap.port", $cmd_soap_port );
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
$lwp->agent( "eSTAR Persistent Virtual Telescope /$VERSION (" 
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
   my $thread_name = "SOAP Thread";


   # create SOAP daemon
   $log->thread($thread_name, "Starting server on port " . 
            $config->get_option( "soap.port") . " (\$tid = ".threads->tid().")");  
   $daemon = eval { new eSTAR::VT::SOAP::Daemon( 
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
   my $handler = "eSTAR::VT::SOAP::Handler";
   
   # defined handlers for the server
   $daemon->dispatch_with({ 'urn:/node_agent' => $handler });
   $daemon->objects_by_reference( $handler );
      
   # handle it!
   $log->thread($thread_name, "Starting handlers..."  );
   $daemon->handle();

};




# S T A R T   S O A P   S E R V E R -----------------------------------------

# Temporary hack until we move observation manager here.
my $proc_name = eSTAR::Process::get_reference->get_process();
unlink "$ENV{HOME}/.estar/$proc_name/tmp/sch.dat";

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
$log->warn( "Warning: SOAP Thread has been terminated abnormally..." );
$log->error( $status );
kill_agent( ESTAR__FATAL );

# tidy up
END {
   # we must have generated an error somewhere to have gotten here,
   # run the exit code to clean(ish)ly shutdown the agent.
   $log->warn("Warning: Terminating process from parent thread");
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
   #killfam 9, ( $config->get_state( "na.pid") );
   $log->warn( "Warning: Not calling killfam 9" );
   
   # close the door behind you!   
   exit;
}                                

# T I M E   A T   T H E   B A R  -------------------------------------------

# $Log: virtual_telescope.pl,v $
# Revision 1.3  2007/04/26 10:21:15  saunders
# Fixed hardcoded user directories
#
# Revision 1.2  2007/04/24 16:52:42  saunders
# Merged ADP agent branch back into main trunk.
#
# Revision 1.1.2.7  2007/04/20 12:47:33  saunders
# Changes to support multi-telescope simulation
#
# Revision 1.1.2.6  2007/02/14 18:30:13  saunders
# Cut memory usage of VT by 90%
#
# Revision 1.1.2.5  2007/02/08 23:17:51  saunders
# driver code is self aware!
#
# Revision 1.1.2.4  2007/02/06 13:53:51  saunders
# Extensively tested return messages for different observing conditions
#
# Revision 1.1.2.3  2007/02/05 10:16:16  saunders
# Added location on Earth and sunrise/sunset info to virtual telescope
#
# Revision 1.1.2.2  2007/01/05 15:40:23  saunders
# Implemented virtual telescope asynchronous update messaging
#
# Revision 1.1.2.1  2006/12/20 09:48:01  saunders
# Created basic virtual telescope.
#

