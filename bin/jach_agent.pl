#!/software/perl-5.8.6/bin/perl

# D O C U M E N T I O N ------------------------------------------------------

#+ 
#  Name:
#    jach_agent.pl

#  Purposes:
#    eSTAR JACH Embedded Agent

#  LangDNge:
#    Perl script

#  Invocation:
#    Invoked by source ${ESTARDIR}/etc/jach_agent.csh

#  Description:
#    The eSTAR agent process embedded in a JACH telescope.

#  Authors:
#    Alasdair Allan (aa@astro.ex.ac.uk)

#  Revision:
#     $Id: jach_agent.pl,v 1.7 2005/01/11 17:18:26 aa Exp $

#  Copyright:
#     Copyright (C) 2003 University of Exeter. All Rights Reserved.

#-

# ---------------------------------------------------------------------------

# Whack, don't do it again!
use strict;

# G L O B A L S -------------------------------------------------------------

# Global variables
#  $VERSION  - CVS Revision Number
#  $PROJECT  - Lookup table between estar user id and JAC project id
#  %OPT      - Options hash for things we don't want to be persistant
#  $log      - Handle for logging object
#  $config   - Handle for configuration object
#  %running  - A shared hash to hold the currently running observations

use vars qw / $VERSION $PROJECT %OPT $log $config %running /;

# local status variable
my $status;

# P O D  D O C U M E N T A T I O N ------------------------------------------

=head1 NAME

C<jach_agent.pl> - Embedded Agent for JACH Telescopes

=head1 SYNOPSIS

   jach_agent.pl [-vers]

=head1 DESCRIPTION

C<jach_agent.pl> is a persitent component of the the eSTAR Intelligent 
Agent Client Software. The C<jach_agent.pl> is an embedded RTML to TOMAL
translation layer, which also handles external phase 0 discovery requests.

=head1 REVISION

$Id: jach_agent.pl,v 1.7 2005/01/11 17:18:26 aa Exp $

=head1 AUTHORS

Alasdair Allan (aa@astro.ex.ac.uk)

=head1 COPYRIGHT

Copyright (C) 2003 University of Exeter. All Rights Reserved.

=cut

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.7 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR JACH Embedded Agent Software:\n";
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
use eSTAR::JACH::Running;
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
my $process = new eSTAR::Process( "jach_agent" );  

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

# error bleeps?
$OPT{"BLEEP"} = ESTAR__OK;

# S H A R E   C R O S S - T H R E A D   V A R I A B L E S -------------------

# share the running array across threads
share( %running );
my $run = new eSTAR::JACH::Running( $process->get_process() );
$run->set_hash( \%running );

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
$log->header("Starting JACH Embedded Agent: Version $VERSION");

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
  
# create a unique ID for each JACH process, increment every time an JACH is
# created and save it immediately to the state file, of course eventually 
# we'll run out of ints, I guess that will be bad...

my ( $number, $string );
$number = $config->get_state( "jach.unique_process" ); 
if ( defined $number ) {
  # $number is not defined correctly (first ever run of the program?)
  $number = 0; 
}

# increment ID number
$number = $number + 1;
$config->set_state( "jach.unique_process", $number );
$log->debug("Setting jach.unique_process = $number"); 
  
# commit ID stuff to STATE file
$status = $config->write_state();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Can not read or write to state file";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("Unique process ID: updated state.dat file" );
}

# PID OF JACH AGENT
# -----------------

# log the current $pid of the jach_agent.pl process to the state 
# file  so we can kill it from the SOAP server.
$config->set_state( "jach.pid", getpgrp() );
  
# commit $pid to STATE file
$status = $config->write_state( );
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Can not read or write to state.dat file";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("Embedded Agent PID: " . $config->get_state( "jach.pid" ) );
}

# P R O J E C T  L O O K U P  F I L E ---------------------------------------

# LOOKUP FILE
# -----------

# grab users home directory and define options filename
my $project_file = 
  File::Spec->catfile(Config::User->Home(), '.estar', 
                      $process->get_process(), 'project.dat' );

# open (or create) the options file
$log->debug("Reading project ID file from $project_file");
$PROJECT = new Config::Simple( syntax=>'ini', mode=>O_RDWR|O_CREAT );

unless ( defined $PROJECT ) {
   # can't read/write to state file, scream and shout!
   my $error = "FatalError: " . $Config::Simple::errstr;
   $log->error(chomp($error));
   throw eSTAR::Error::FatalError($error, ESTAR__FATAL);      
}
$PROJECT->param( "jach.project", $project_file );

# save the name of the project.dat file into the options.dat file
$config->set_option( "jach.project", $project_file );

# READ PROJECT LIST FROM FILE (OR WEB SERVICE?)
# ---------------------------------------------
#
# < I N S E R T   C O D E   H E R E >

# PROJECT ID LIST
# ---------------

# eventually we want to serialise these project lookups into some sort
# of flatfile or DB, perhaps with a web interface (hooked up to the OMP?)
my %projects;

# Project ID number to password mappings
$projects{"TJ03"} = "sicstran";
$projects{"U/03B/D10"} = "strytess";

# PROJECTS REFERENCED BY ESTAR USER ID
# ------------------------------------

# list of users with access to specific JAC project ID's, can have many
# eSTAR users mapped to one JAC project ID, but not a single eSTAR user
# mapped to many JAC project IDs (at least for now)>=.
#$PROJECT->param( "user.aa", "TJ03" );
#$PROJECT->param( "user.timj", "TJ03" );
$PROJECT->param( "user.aa", "U/03B/D10" );
$PROJECT->param( "user.aa", "U/03B/D10" );

# PROJECT LOOKUP FILE
# -------------------

# loop over all known projects and serialise the lookups

foreach my $key ( sort keys %projects ) {
   $PROJECT->param( "project.".$key, $projects{$key} );
}

# WRITE IT OUT
# ------------
# commit name of the lookup file to PROJECT and CONFIG files
$status = $PROJECT->write( $config->get_option( "jach.project" ) );

unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: " . $Config::Simple::errstr;
  $log->error(chomp($error));
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("Project file: " . $config->get_option( "jach.project" ) );
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
use SOAP::Lite;
use HTTP::Cookies;
use URI;
use LWP::UserAgent;
use Net::FTP;

#
# Astro modules
#
use Astro::Telescope;

#
# eSTAR modules
#
use eSTAR::JACH::SOAP::Daemon;  # replaces for SOAP::Transport::HTTP::Daemon
use eSTAR::JACH::SOAP::Handler; # SOAP layer ontop of handler class

# M A K E   D I R E C T O R I E S -------------------------------------------

# create the data, state and tmp directories if needed
$status = $config->make_directories();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Problems creating data directories";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} 
# L O A D   % R U N N I N G   S H A R E D   H A S H -----------------------        

my ( @files );
if ( opendir (DIR, $config->get_state_dir() )) {
   foreach ( readdir DIR ) {
      push( @files, $_ ); 
   }
   closedir DIR;
} else {
   $log->error("Error: Can not open state directory (" .
               $config->get_state_dir() .") for reading" );      
}         

$log->print("Thawing outstanding observations from state directory...");

# NB: first 2 entries in a directory listing are '.' and '..'
foreach my $i ( 2 ... $#files ) {

   $log->print("File: $files[$i]");
   # thaw the observation
   my $observation_object = eSTAR::Util::thaw( $files[$i] );    
   unless ( defined $observation_object ) {
      $log->warn( "Warning: Unable to deserialise ID = $files[$i]" );   
   }
   
   #push it onto the %running hash
   {      
      my $id = $observation_object->id();
      my $status = $observation_object->status();   

      # only push running or retry observations onto the stack
      if ( $status eq 'running' || $status eq 'retry' ) {
         my $obs_reply = $observation_object->obs_reply();
         my $expire = $obs_reply->time();
      
         $log->debug( "Pushing $id ($status) on hash...");
         $log->debug( "$id expires at $expire");

         $log->debug( "Locking \%running..." );
         lock( %{ $run->get_hash() } );
         my $ref = &share({});
         $ref->{Expire} = "$expire";
         $ref->{Status} = "$status";
         ${ $run->get_hash() }{$id} = $ref;
         $log->debug( "Unlocking \%running...");
      } else {
         $log->warn( "Warning: $id isn't outstanding" );
         $log->warn( "Warning: discarding $id..." );
         my $status = eSTAR::Util::melt( $observation_object );        
         if ( $status == ESTAR__ERROR ) {
            $main::log->warn( 
               "Warning: Problem deleting the \$observation_object");
         } 
        
         $log->debug( "Locking \%running..." );
         lock( %{ $run->get_hash() } );
         $log->debug( "Removing " . $id. " from \%running..." );
         delete ${ $run->get_hash() }{ $id };
         $log->debug( "Unlocking \%running...");
        
      }   
   } # implict unlock() here
   #use Data::Dumper; print Dumper ( %main::running );         

}

# print some debug if there aren't any serialised files
if ( ($#files - 1) == 0 ) {
   $log->warn( "Warning: No outstanding observations found?" );
}   

# M A I N   O P T I O N S   H A N D L I N G ---------------------------------

my $ip = inet_ntoa(scalar(gethostbyname(hostname())));

if ( $config->get_state("jach.unique_process") == 1 ) {

   my %user_id;
   tie %user_id, "CfgTie::TieUser";
      
   # grab current user
   my $current_user = $user_id{$ENV{"USER"}};
   my $real_name = ${$current_user}{"GCOS"};
     
   # user defaults
   $config->set_option("user.user_name", $ENV{"USER"} );
   $config->set_option("user.real_name", $real_name );
   $config->set_option("user.email_address", $ENV{"USER"} . "@" .hostdomain() );
   $config->set_option("user.institution", "eSTAR Project" );
      
   # SOAP server parameters
   $config->set_option( "soap.host", $ip );
   $config->set_option( "server.port", 8080 );

   # interprocess communication
   $config->set_option( "ua.user", "agent" );
   $config->set_option( "ua.passwd", "InterProcessCommunication" );

   # telescope information
   $config->set_option( "dn.telescope", "UKIRT" );

   # garbage collection
   $config->set_option( "jach.garbage", 30 );
   
   # connection options defaults
   $config->set_option("connection.timeout", 5 );
   $config->set_option("connection.proxy", 'NONE'  ); 
    
   # C O M M I T T   O P T I O N S  T O   F I L E S
   # ----------------------------------------------
   
   # committ CONFIG and STATE changes
   $log->warn("Initial default options being generated");
   $log->warn("Committing options and state changes...");
   $status = $config->write_option( );
   $status = $config->write_state( );
}
   
# ===========================================================================
# H T T P   U S E R   A G E N T 
# ===========================================================================

$log->debug("Creating an HTTP User Agent...");


# Create HTTP User Agent
my $lwp = new LWP::UserAgent( 
                timeout => $config->get_option("connection.timeout") );

# Configure User Agent                         
$lwp->env_proxy();
$lwp->agent( "eSTAR Discovery Node Agent /$VERSION (" 
             . hostname() . "." . hostdomain() .")");

my $ua = new eSTAR::UserAgent(  );  
$ua->set_ua( $lwp );

# ===========================================================================
# M A I N   B L O C K 
# ===========================================================================

# S O A P   S E R V E R -----------------------------------------------------

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
       $config->get_option( "server.port") . " (\$tid = ".threads->tid().")");  
   $daemon = eval{ new eSTAR::JACH::SOAP::Daemon( 
                      LocalPort     => $config->get_option( "server.port"),
                      Listen        => 5, 
                      Reuse         => 1 ) };    
                    
   if ($@) {
      # If we restart the jach agent process quickly after a crash the port 
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
   my $handler = "eSTAR::JACH::SOAP::Handler";
   
   # defined handlers for the server
   my $urn = 'urn:/' . $process->get_urn();
   $daemon->dispatch_with({ $urn => $handler });
   $daemon->objects_by_reference( $handler );
      
   # handle it!
   $log->thread($thread_name, "Starting handlers..."  );
   $daemon->handle;

};

# S T A R T   S O A P   S E R V E R -----------------------------------------

# Spawn the SOAP server thread
$log->print("Spawning SOAP Server thread...");
$listener_thread = threads->create( $soap_server );

# G A R B A G E   C O L L E C T I O N ---------------------------------------

# subroutines used by the garbage collection thread need to be defined here
# before the thread is created.

# the thread in which we run the server process
my $garbage_thread;

# anonymous subroutine which starts a SOAP server which will accept
# incoming SOAP requests and route them to the appropriate module
my $garbage = sub {
   my $thread_name = "Garbage Thread";

   # create SOAP daemon
   $log->thread2($thread_name, "Starting garbage collection...");  
   $log->thread2($thread_name, "Collected every " .
                 $config->get_option( "jach.garbage") . " seconds..." );
 
   while( 1 ) {
      sleep $config->get_option( "jach.garbage" );
      $main::log->print( "Garbage Collection started at ". ctime() );
      $log->thread2( $thread_name,
          "Running garbage collection (\$tid = " . threads->tid() . ")");

      # lock the %main::running hash and look through the $id's for expired
      # observations and then melt them() after sending a fail message
      {
         $log->debug( "Locking \%running in jach_agent..." );
         lock( %{ $run->get_hash() } );
         foreach my $key ( keys %{ $run->get_hash() } ) {         
           $log->print( "Observation $key is queued..." );
           
           # RETRY SUBMISSION BACK TO USER AGENT
           # -----------------------------------
              
           my $observation_object = eSTAR::Util::thaw( $key );    
           unless ( defined $observation_object ) {
              $log->warn( "Warning: Unable to deserialise ID = $key" );   
           }
                         
           if ( ${${ $run->get_hash() }{$key}}{Status} eq "retry" &&
                defined $observation_object ) {

              
              # check to see if we have an observation message
              my $message;
              $message = $observation_object->observation();
                            
              # if not fallback to get an update message
              unless ( defined $message ) {
                 $message = $observation_object->update();
              }
              
              # sanity check, if neither of these are defined we're in
              # trouble because one of these two messages has to be
              # defined otherwise the $id status shouldn't be "retry"
              unless ( defined $message ) {
                 $log->error( "Error: No messages defined, how odd!?" );
                 $log->error( "Error: Discarding observation $key" );  
                 my $status = eSTAR::Util::melt( $observation_object );        
                 if ( $status == ESTAR__ERROR ) {
                    $log->warn( 
                       "Warning: Problem deleting the \$observation_object");
                 } 
        
                 $log->debug( "Removing " . $key. " from \%running..." );
                 delete ${ $run->get_hash() }{ $key };
                 next;
              }
             
              # RETRY SENDING THE MESSAGE
              # -------------------------
               
              #$log->warn("Warning: Going to retry connection to user_agent");
         
              #
              # < INSERT RETRY CODE HERE >
              #
              
           # CHECK FOR EXPIRY OF OBSERVATION
           # -------------------------------         
           
           } elsif ( ${${ $run->get_hash() }{$key}}{Status} eq "running" &&
                     defined $observation_object ) {

              #
              # < INSERT CODE TO CHECK EXPIRY HERE >
              # < INSERT CODE TO SEND FAIL MESSAGE TO USER AGENT HERE >
              # < INSERT CODE TO REMOVE OBS FROM RUNNING HERE >
              #
              
           # OBJECT DOESN'T DESERIALISE           
           # --------------------------
              
           } else {
           
              # There is no way we should reach here, in this case the
              # object hasn't deserialised at all, so lets just blow away
              # the object from the State directory and remove it from the
              # running queue. I can't see how this could get called under
              # normal circumstances, which probably means I'll see this
              # error message next time I run the code.
              $log->warn("Warning: Bad status, trying to unlink observation");
              my $file = File::Spec->catfile($config->get_state_dir(), $key);
              unless ( unlink $file ) {
                 $log->warn( "Warning: Unable to unlink file...");
              } else {
                  $log->warn( "Warning: Sucessfully unlinked file..."); 
              }          
              $log->warn( "Warning: Removing " . $key. " from \%running..." );
              delete ${ $run->get_hash() }{ $key };
              next;
           }      
              
         } # end of foreach() loop

         $log->debug( "Unlocking \%running...");
      } # implict unlock() here, end of locking block
                  
      # finished garbage collection
      $log->thread2( $thread_name, "Done with garbage collection..." );
   }
};

# S T A R T   G A R B A G E   C O L L E C T I O N   T H R E A D -------------

# Spawn the garbage collection thread. This thread monitors the %running
# hash and sends out fail messages to the user_agent when the observations
# expire
$log->print("Spawning Garbage Collection thread...");
$garbage_thread = threads->create( $garbage );
$garbage_thread->detach();

# ===========================================================================
# E N D 
# ===========================================================================

# Wait for threads to join, this shouldn't happen under normal circumstances
# so we must have generated an error if they do, catch the returned status
# on the join and try and exit gracefully.
$status = $listener_thread->join() if defined $listener_thread;
$log->error( $status );
$log->warn( "Warning: SOAP Thread has been terminated abnormally..." );


# tidy up
END {
   # we must have generated an error somewhere to have gotten here,
   # run the exit code to clean(ish)ly shutdown the agent.
   kill_agent( ESTAR__FATAL );
}

# ===========================================================================
# A S S O C I A T E D   S U B R O U T I N E S 
# ===========================================================================


# anonymous subroutine which is called everytime the jach agent is
# terminated (ab)normally. Hopefully this will provide a clean exit.
sub kill_agent {
   my $from = shift;
         
   if ( $from eq ESTAR__FATAL ) {  
      $log->debug("Calling kill_agent( ESTAR__FATAL )");
      $log->warn("Warning: Shutting down agent after ESTAR__FATAL error...");
   } else {
      if( threads->tid() == 0 && $from == undef ) {
         $log->debug("Calling kill_agent( SIGINT )");
         $log->warn("Warning: Process interrupted, possible data loss...");
      } else {
         $log->debug("Terminating thread \$tid = " . threads->tid() );
         return;
      }   
   }

   # committ CONFIG and STATE changes
   #$log->warn("Warning: Committing options and state changes");
   #$config->write_option( );
   #$config->write_state( );
   
   # flush the error stack
   $log->debug("Flushing error stack...");
   my $error = eSTAR::Error->prior();
   $error->flush() if defined $error;
    
   # kill the agent process
   $log->print("Killing jach_agent processes...");

   # close out log files
   $log->closeout();
   
   # ring my bell, baby
   #if ( $OPT{"BLEEP"} == ESTAR__OK ) {
   #  for (1..10) {print STDOUT "\a"; select undef,undef,undef,0.2}
   #}
   
   # kill -9 the agent process, hung threads should die screaming
   killfam 9, ( $config->get_state( "jach.pid") );
   
   # close the door behind you!   
   exit;

} 

# T I M E   A T   T H E   B A R  -------------------------------------------

# $Log: jach_agent.pl,v $
# Revision 1.7  2005/01/11 17:18:26  aa
# Refactored, should work once OMP issues are resolved  (see ChangeLog for details.
#
# Revision 1.6  2004/12/21 17:04:09  aa
# Fixes to store the LWP::UserAgent in a single instance object and get rid of the last $main:: references in the handler code
#
# Revision 1.5  2004/11/30 19:05:30  aa
# Working user_agent.pl, Handler.pm cleaned of most $main:: references. Only $main::OPT{http_agent} reference remains, similar to jach_agent.pl. Not tried a loopback test yet
#
# Revision 1.4  2004/11/30 18:36:26  aa
# Fixed some of the software decay that had set into the distribution. The user_agent.pl and associated code still needs looking at to ermove direct access to $main::* in some cases
#
# Revision 1.3  2004/11/12 14:32:04  aa
# Extensive changes to support jach_agent.pl, see ChangeLog
#
# Revision 1.2  2004/11/05 15:32:08  aa
# Inital commit of jach_agent and associated files. Outstandingf problems with the $main::* in eSTAR::JACH::Handler and %running in eSTAR::JACH::Handler and jach_agent.pl script itself. How do I share %running across threads, but keep it a singleton object?
#
# Revision 1.1  2004/11/05 14:37:24  aa
# Inital check-in, modified from working generation 2 code. Probably won't run at this point
#
# Revision 1.14  2003/08/27 10:48:42  aa
# Shipping to summit
#
# Revision 1.13  2003/08/27 08:30:34  aa
# Shipping to summit
#
# Revision 1.12  2003/08/19 18:57:35  aa
# Created eSTAR::Util class, moved general methods to this class. Moved the
# infrastructure to support the new Astro::Catalog V3.* API. Tested user agent
# against the old node agent installed on dn2.astro.ex.ac.uk, but the JAC
# and node agent have not been tested (but should work).
#
# Revision 1.11  2003/07/26 03:12:47  aa
# More error checking in garbage collection thread
#
# Revision 1.10  2003/07/25 04:22:51  aa
# Garbage Collection thread (almost) done
#
# Revision 1.9  2003/07/24 03:07:54  aa
# End of day checkin (see ChangeLog)
#
# Revision 1.8  2003/07/23 01:28:55  aa
# Shipping to muttley
#
# Revision 1.7  2003/07/20 02:23:50  aa
# Moved to ForkAfterProcessing from ThreadOnAccept, broken authentication?
#
# Revision 1.6  2003/07/19 00:05:07  aa
# Shipping to NAHOKU
#
# Revision 1.5  2003/07/18 01:32:57  aa
# Syncing to nahoku.jach.hawaii.edu
#
# Revision 1.4  2003/07/15 19:31:19  aa
# Minor twiddle, ignore it
#
# Revision 1.3  2003/07/15 19:14:53  aa
# Changed urn identifier on jach_agent.pl
#
# Revision 1.2  2003/07/15 08:28:32  aa
# Minimal handle_rtml() function in the JACH Agent
#
# Revision 1.1  2003/07/15 03:32:49  aa
# Changes made at OSCON'03
#
