#!/jac_sw/estar/perl-5.8.6/bin/perl -w

# Whack, don't do it again!
use strict;

# G L O B A L S -------------------------------------------------------------

use vars qw / $log $process $config $VERSION  %opt /;

# local status variable
my $status;

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR Server Software:\n";
      print "Correlation Daemon $VERSION; PERL Version: $]\n";
      exit;
    }
  }
}

# ===========================================================================
# S E T U P   B L O C K
# ===========================================================================

# push $VERSION into %OPT
$opt{"VERSION"} = $VERSION;

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

# General modules
use Config;
use IO::Socket;
use Errno qw(EWOULDBLOCK EINPROGRESS);
use Net::Domain qw(hostname hostdomain);
use Time::localtime;
use Getopt::Long;
use Data::Dumper;
use Fcntl qw(:DEFAULT :flock);
use SOAP::Lite;
use Digest::MD5 'md5_hex';
use URI;
use HTTP::Cookies;

# Astronomy modules
use Astro::Catalog;
use Astro::Correlate;

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process = new eSTAR::Process( "correlation_daemon" );  

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process->set_version( $VERSION );

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
$log->header("Starting Correlation Daemon: Version $VERSION");

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
$number = $config->get_state( "corr.unique_process" ); 
unless ( defined $number ) {
  # $number is not defined correctly (first ever run of the program?)
  $number = 0; 
}

# increment ID number
$number = $number + 1;
$config->set_state( "corr.unique_process", $number );
$log->debug("Setting corr.unique_process = $number"); 
  
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

# PID OF PROCESS
# --------------

# log the current $pid of the process to the state 
# file so we can kill itmore easily.
$config->set_state( "corr.pid", getpgrp() );
  
# commit $pid to STATE file
$status = $config->write_state();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Can not read or write to state.dat file";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("GCN Server PID: " . $config->get_state( "corr.pid" ) );
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

if ( $config->get_state("corr.unique_process") == 1 ) {
  
   # user agentrameters
   $config->set_option("db.host", $ip );
   $config->set_option("db.port", 8005 );

   # interprocess communication
   $config->set_option("corr.user", "agent" );
   $config->set_option("corr.passwd", "InterProcessCommunication" );

   # connection options defaults
   $config->set_option("connection.timeout", 5 );
   $config->set_option("connection.proxy", 'NONE'  );
  
   # mail server
   $config->set_option("mailhost.name", 'ieie' );
   $config->set_option("mailhost.domain", 'jach.hawaii.edu' );
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
$status = GetOptions( "user=s"     => \$opt{"user"},
                      "pass=s"     => \$opt{"pass"},
                      "agent=s"    => \$opt{"db"} );


# default user agent location
unless( defined $opt{"db"} ) {
   # default host for the user agent we're trying to connect to...
   $opt{"db"} = $config->get_option("db.host");   
} else {
   $log->warn("Warning: Resetting port from " .
             $config->get_option("db.host") . " to $opt{db}");
   $config->set_option("db.host", $opt{"db"});
}

# default user and password location
unless( defined $opt{"user"} ) {
   $opt{"user"} = $config->get_option("corr.user");
} else{       
   $log->warn("Warning: Resetting username from " .
             $config->get_option("corr.user") . " to $opt{user}");
   $config->set_option("corr.user", $opt{"user"} );
}

# default user and password location
unless( defined $opt{"pass"} ) {
   $opt{"pass"} = $config->get_option("corr.passwd");
} else{       
   $log->warn("Warning: Resetting password...");
   $config->set_option("corr.passwd", $opt{"pass"} );
}

# ===========================================================================
# C A L L B A C K 
# ===========================================================================

# thread in which the callback runs
my $callback_thread;

# callback from main loop which monitors the flag files
my $callback = sub {
   # everything passed to the callback is a filename, honest!
   my @files = @_;
   
   # spawn the correlation threads
   my ( @threads, @variable_catalogs );
   foreach my $i ( 0 ... $#files ) {
   
   
   }
   
   # wait for all threads to rejoin
   
   
   # merge catalogues into one single variable catalogue list
   # removing duplicate entries (based on RA and Dec alone?)
   
   
   # dispatch list of variables, and list of all stars to DB web 
   # service via a SOAP call. We'll pass the lists as Astro::Catalog
   # objects to avoid any sort of information loss. We can do this
   # because we're running all Perl. If we need interoperability
   # later, we'll move to document literal.
   
   
   return ESTAR__OK;
   
};

# ===========================================================================
# M A I N   L O O P 
# ===========================================================================

my $exit_code;
while ( !$exit_code ) {

   # look for flag file creation
   
   # check to see what type of flag file we have got
   if ( ) {
      # We have a 4 position jitter
      
      
      $log->print("Spawning callback() to handle catalogues...");
      $callback_thread = threads->create( $callback );
   
   } elsif ( ) {
      # We have a 9 position jitter
      
      
      $log->print("Spawning callback() to handle catalogues...");
      $callback_thread = threads->create( $callback );
      
   } 
   
}


# ===========================================================================
# E N D 
# ===========================================================================

# tidy up
END {
   # we must have generated an error somewhere to have gotten here,
   # run the exit code to clean(ish)ly shutdown the agent.
   kill_process( ESTAR__FATAL );
}

# ===========================================================================
# A S S O C I A T E D   S U B R O U T I N E S 
# ===========================================================================

# anonymous subroutine which is called everytime the process is
# terminated (ab)normally. Hopefully this will provide a clean exit.
sub kill_process {
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
   $log->print("Killing correlation_daemon processes...");

   # close out log files
   $log->closeout();
   
   # ring my bell, baby
   #if ( $OPT{"BLEEP"} == ESTAR__OK ) {
   #  for (1..10) {print STDOUT "\a"; select undef,undef,undef,0.2}
   #}

   # kill -9 the agent process, hung threads should die screaming
   killfam 9, ( $config->get_state( "corr.pid") );
   #$log->warn( "Warning: Not calling killfam 9" );
   
   # close the door behind you!   
   exit;
} 

sub intra_flag_from_bits {
  unless ( scalar(@_) == 3 ) {
     my $errror = 
        "Wrong number of arguements: intra_flag_from_bits(ut, obsnum, camnum)";
     $log->error( "Error: $error" );
     throw eSTAR::Error::FatalError( $error, ESTAR__FATAL );
  }
  my $utdate = shift;
  my $obsnum = shift;
  my $camnum = shift;

  my $fname = flag_from_bits( $utdate, $obsnum, $camnum );
  my $directory = $config->get_option( "corr.camera${camnum}_data_directory" );
  if( ! defined( $$directory ) ) {
    my $error = "Could not retrieve data directory from configuration " .
                "options for WFCAM camera $camnum"
    $log->error( "Error: $error" );
    throw eSTAR::Error::FatalError( $error, ESTAR__FATAL );
  }
  
  my $directory = $config->get_option( "corr.camera${camnum}.data_directory" );
  if( ! defined(   
  my $prefix = $config->get_option( "corr.camera${camnum}.prefix" );
  if( ! defined( $prefix ) ) {
    my $error = "Could not retrieve filename prefix from configuration " .
                "options for WFCAM camera $camnum";
    $log->error( "Error: $error" );
    throw eSTAR::Error::FatalError( $error, ESTAR__FATAL );
  }
  
