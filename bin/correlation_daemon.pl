#!/jac_sw/estar/perl-5.8.6/bin/perl -w

# Whack, don't do it again!
use strict;

# G L O B A L S -------------------------------------------------------------

use vars qw / $log $process $config $VERSION  %OPT /;

# local status variable
my $status;

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.20 $ =~ /(\d+)\.(\d+)/;
 
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
$OPT{"VERSION"} = $VERSION;

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
use DateTime;
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
use Astro::Corlate;
use Astro::FITS::Header::CFITSIO;

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process = new eSTAR::Process( "correlation_daemon" );  

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process->set_version( $VERSION );

# Get date and time
my $date = scalar(localtime);
my $host = hostname;
my $datetime = DateTime->now;
my $currentut = $datetime->ymd('');

# L O G G I N G --------------------------------------------------------------

# Start logging
# -------------

# start the log system
$log = new eSTAR::Logging( $process->get_process() );
print "Starting logging...\n\n";

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
  $log->debug("Correlation Daemon PID: " . $config->get_state( "corr.pid" ) );
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
   
   # instrument defaults
   $config->set_option("corr.camera1_prefix", "w" );
   $config->set_option("corr.camera1_directory",  
                       $config->get_option( "dir.data" ) );
   
   $config->set_option("corr.camera2_prefix", "x" );
   $config->set_option("corr.camera1_directory",  
                       $config->get_option( "dir.data" ) );
   
   $config->set_option("corr.camera3_prefix", "y" );
   $config->set_option("corr.camera1_directory",  
                       $config->get_option( "dir.data" ) ); 
   
   $config->set_option("corr.camera4_prefix", "z" );
   $config->set_option("corr.camera1_directory",  
                       $config->get_option( "dir.data" ) );
    
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
$status = GetOptions( "user=s"     => \$OPT{"user"},
                      "pass=s"     => \$OPT{"pass"},
                      "agent=s"    => \$OPT{"db"},
                      "from=s"     => \$OPT{'from'},
                      "ut=s"       => \$OPT{'ut'},
                      "camera=s"   => \$OPT{'camera'}, );


# default user agent location
unless( defined $OPT{"db"} ) {
   # default host for the user agent we're trying to connect to...
   $OPT{"db"} = $config->get_option("db.host");   
} else {
   $log->warn("Warning: Resetting port from " .
             $config->get_option("db.host") . " to $OPT{db}");
   $config->set_option("db.host", $OPT{"db"});
}

# default user and password location
unless( defined $OPT{"user"} ) {
   $OPT{"user"} = $config->get_option("corr.user");
} else{       
   $log->warn("Warning: Resetting username from " .
             $config->get_option("corr.user") . " to $OPT{user}");
   $config->set_option("corr.user", $OPT{"user"} );
}

# default user and password location
unless( defined $OPT{"pass"} ) {
   $OPT{"pass"} = $config->get_option("corr.passwd");
} else{       
   $log->warn("Warning: Resetting password...");
   $config->set_option("corr.passwd", $OPT{"pass"} );
}

# Default starting observation number.
unless( defined( $OPT{'from'} ) ) {
  $OPT{'from'} = 1;
}

my $starting_obsnum = $OPT{'from'};
my $starting_ut = get_utdate();

# default user and password location
unless( defined $OPT{"camera"} ) {
   $OPT{"camera"} = $config->get_option("corr.camera");
} else{
   $log->warn("Warning: Resetting camera from " .
             $config->get_option("corr.camera") . " to $OPT{camera}");
   $config->set_option("corr.camera", $OPT{"camera"} );
}

# ===========================================================================
# C A L L B A C K S
# ===========================================================================


sub correlate {
  my $files_arrayref = shift;
  my @files = @$files_arrayref;

  # Form Astro::Catalog objects from the list of files.
  my @threads;
  my @variable_catalogs;
  my @catalogs = map{ new Astro::Catalog( Format => 'FITSTable',
                                          File => $_ ) } @files;

  # Correlate.
# foreach my $i ( 0 .. ( $#catalogs - 1 ) ) {
#    foreach my $j ( ( $i + 1 ) .. ( $#catalogs ) ) {
#      print "correlating catalog $i with $j\n";
#      my $cat1 = $catalogs[$i];
#      print "catalog 1 has " . $cat1->sizeof . " objects before.\n";
#      my $cat2 = $catalogs[$j];
#      print "catalog 2 has " . $cat2->sizeof . " objects before.\n";
#      my $corr = new Astro::Correlate( catalog1 => $cat1,
#                                       catalog2 => $cat2,
#                                       method => 'FINDOFF',
#                                     );
#      $corr->verbose( 1 );
#      ( my $corrcat1, my $corrcat2 ) = $corr->correlate;
#
#      print "catalog 1 has " . $cat1->sizeof . " objects before, " . $corrcat1->sizeof . " objects after.\n";
#
#    }
#  }

 foreach my $i ( 0 .. ( $#catalogs - 1 ) ) {
    foreach my $j ( ( $i + 1 ) .. ( $#catalogs ) ) {
      print "correlating catalog $i with $j\n";
    
      # object catalogue
      my ($voli,$diri,$filei) = File::Spec->splitpath( $catalogs[$i] );
      my ($volj,$dirj,$filej) = File::Spec->splitpath( $catalogs[$j] );
      $filei =~ s/\.fit//;
      $filej =~ s/\.fit//;
      
      my $id = $i . "_with_" .$j . "_cam" . $camera . "_proc" . $$";
      
      my $camera = $OPT{'camera'};
      my $file_i = File::Spec->catfile( $config->get_tmp_dir(), 
                                        "$filei_$id.cat");
      my $file_j = File::Spec->catfile( $config->get_tmp_dir(), 
                                        "$filej_$id.cat");
									       
      $log->debug("Writing catalogue $file_i to disk...");
      $catalogs[$i]->write_catalog( Format => 'Cluster', File => $file_i );
      $log->debug("Writing catalogue $file_j to disk...");
      $catalogs[$j]->write_catalog( Format => 'Cluster', File => $file_j ); 
      
      $log->debug("Building corelation object...");
      my $corlate = new Astro::Corlate(  Reference   => $file_i,
                                         Observation => $file_j  );
  
      # log file
      my $log_file = File::Spec->catfile( $config->get_tmp_dir(), 
                                          "$id.corlate_log.log");
      $corlate->logfile( $log_file );

      # fit catalog
      my $fit_file = File::Spec->catfile( $config->get_tmp_dir(), 
                                          "$id.corlate_fit.fit");
      $corlate->fit( $fit_file );
                   
      # histogram
      my $hist_file = File::Spec->catfile( $config->get_tmp_dir(), 
                                       "$id.corlate_hist.dat");
      $corlate->histogram( $hist_file );
                   
      # information
      my $info_file = File::Spec->catfile( $config->get_tmp_dir(), 
                                       "$id.corlate_info.dat");
      $corlate->information( $info_file );
                   
      # varaiable catalog
      my $var_file = File::Spec->catfile( $config->get_tmp_dir(), 
                                      "$id.corlate_var.cat");
      $corlate->variables( $var_file );
                   
      # data catalog
      my $data_file = File::Spec->catfile( $config->get_tmp_dir(), 
                                       "$id.corlate_fit.cat");
      $corlate->data( $data_file);
                   
      # Astro::Corlate inputs
      # ---------------------
      my ($volume, $directories, $file); 
 
      $log->debug("Starting cross correlation...");
      ($volume, $directories, $file) = File::Spec->splitpath( $file_i );
      $log->debug("Temporary directory   : " . $directories);
      $log->debug("Reference catalogue   : " . $file);
  
      ($volume, $directories, $file) = File::Spec->splitpath( $file_j );
      $log->debug("Observation catalogue : " . $file);
  
      ($volume, $directories, $file) = File::Spec->splitpath( $log_file );
      $log->debug("Log file              : " . $file);
  
      ($volume, $directories, $file) = File::Spec->splitpath( $fit_file );
      $log->debug("X/Y Fit file          : " . $file);
  
      ($volume, $directories, $file) = File::Spec->splitpath( $hist_file );
      $log->debug("Histogram file        : " . $file);
  
      ($volume, $directories, $file) = File::Spec->splitpath( $info_file );
      $log->debug("Information file      : " . $file);
  
      ($volume, $directories, $file) = File::Spec->splitpath( $var_file );
      $log->debug("Variable catalogue    : " . $file);
  
      ($volume, $directories, $file) = File::Spec->splitpath( $data_file );
      $log->debug("Colour data catalogue : " . $file);   
      
      # run the corelation routine
      # --------------------------
      my $status = ESTAR__OK;
      try {
         $log->debug("Called run_corlate()...");
         $corlate->run_corlate();
      } otherwise {
         my $error = shift;
         eSTAR::Error->flush if defined $error;
         $status = ESTAR__ERROR;
                
         # grab the error line
         my $err = "$error";
         chomp($err);
         $log->debug("Error: $err");
      }; 
  
      # undef the Astro::Corlate object
      $corlate = undef;
  
      # check for good status
      # ---------------------
      unless ( $status == ESTAR__OK ) {
         $log->warn( "Warning: Cross Correlation routine failed to run" );
      }
    }
  }

  # merge catalogues into one single variable catalogue list
  # removing duplicate entries (based on RA and Dec alone...)


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

my $camera = $OPT{'camera'};
$log->debug( "Beginning file loop for camera $camera." );

my $utdate = $starting_ut;
my $obsnum = $starting_obsnum;
my @catalog_files = ();

while( 1 ) {
  my $flag;
  $obsnum = flag_loop( $utdate, $obsnum, $camera );
  $log->debug( "Found flag file for observation $obsnum for camera $camera." );
  my $catalog_file = File::Spec->catfile( $config->get_option( "corr.camera${camera}_directory" ),
  					  cat_file_from_bits( $utdate, $obsnum, $camera ) );
  $log->debug( "Pushing $catalog_file onto stack." );
  push @catalog_files, $catalog_file;

  # Read in the header of the FITS file, check to see if we're
  # at the end of a microstep sequence or not.
  $log->debug( "Reading $catalog_file" );
  my $header = new Astro::FITS::Header::CFITSIO( File => $catalog_file );
  tie my %keywords, "Astro::FITS::Header", $header, tiereturnsref => 1;

  my $nustep = $keywords{'SUBHEADERS'}->[0]->{'NUSTEP'};
  my $ustep_position = $keywords{'SUBHEADERS'}->[0]->{'USTEP_I'};
  $log->debug("FITS headers: nustep: $nustep ustep_pos: $ustep_position");
  if( $ustep_position == $nustep &&
      $nustep != 1 ) {

    # We're at the end of a microstep sequence, so spawn off a thread
    # to do the correlation.
    $log->print( "Spawning correlation_callback() to handle catalogue correlation..." );

    # Correlate without a new thread.
    correlate( \@catalog_files );

    @catalog_files = ();
  }
  if( $nustep == 1 ) {
    @catalog_files = ();
  }

  $obsnum++;

}
$log->print( "Parent process terminating..." );

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

  
   # close the door behind you!
   exit;
}

=item B<flag_loop>

=cut

sub flag_loop {
  my $utdate = shift;
  my $obsnum = shift;
  my $camera = shift;

  my $directory = $config->get_option( "corr.camera${camera}_directory" );

  while( 1 ) {
    my $flagfile = flag_from_bits( $utdate, $obsnum, $camera );

    my $filename = File::Spec->catfile( $directory, $flagfile );
    $log->debug( "Looking for flag file named $filename..." );
    last if( -e $filename );

    # File hasn't been found, so check the directory for any files
    # that might have observation numbers after this one.
    my $next = check_data_dir( $obsnum - 1, $directory, $camera );

    if( defined( $next ) ) {
      if( $next != $obsnum ) {
        $obsnum = $next;
        last;
      }
    }

    sleep( 2 );

  }

  return $obsnum;

}

=item B<flag_from_bits>

Returns the name of the flag file.

  $filename = flag_from_bits( $utdate, $obsnum, $camera );

The three arguments are all mandatory. The first is the UT date in
YYYYMMDD format, the second is the observation number, and the third
is the WFCAM camera number.

This subroutine returns a string containing the filename. It does not
include the directory in which the file will be found.

=cut

sub flag_from_bits {
  my $utdate = shift;
  my $obsnum = shift;
  my $camera = shift;

  my $prefix = $config->get_option( "corr.camera${camera}_prefix" );

  $obsnum = "0" x ( 5 - length( $obsnum ) ) . $obsnum;
  return "." . $prefix . $utdate . "_" . $obsnum . ".ok";
}

sub cat_file_from_bits {
  my $utdate = shift;
  my $obsnum = shift;
  my $camera = shift;

  my $prefix = $config->get_option( "corr.camera${camera}_prefix" );

  $obsnum = "0" x ( 5 - length( $obsnum ) ) . $obsnum;
  return $prefix . $utdate . "_" . $obsnum . "_sf_st_cat.fit";
}

=item B<check_data_dir>

Checks the data directory for the existence of files created after
the requested observation number.

  $next = check_data_dir( $obsnum, $directory, $camera );

If there are no files written after the requested observation number,
this subroutine will return undef. Otherwise it will return the next
observation number that is higher than the requested one.

=cut

sub check_data_dir {
  my $obsnum = shift;
  my $directory = shift;
  my $camera = shift;

  my $utdate = get_utdate();

  # Only look for .ok files.
  my $prefix = $config->get_option( "corr.camera${camera}_prefix" );
  my $pattern = $prefix . $utdate . '_\d{5}\.ok$';

  my $openstatus = opendir( my $DATADIR, $directory );
  if( ! $openstatus ) {
    my $error = "Could not open ORAC-DR data directory $directory: $!";
    $log->error( "Error: $error" );
    throw eSTAR::Error::FatalError( $error, ESTAR__FATAL );
  }

  # Get a sorted list of observation numbers. Note that this assumes
  # that flag files have the format _NNNNN.ok, where NNNNN is the
  # observation number.
  my @sort = sort { $a <=> $b }
               map { $_ =~ /_(\d+)\.ok$/o; $1 }
                 grep { /$pattern/ } readdir( $DATADIR );
  closedir( $DATADIR );

  # Now go through the list of observation numbers and find out if
  # there's one that's higher than the observation number we were
  # given.
  my $next = undef;
  foreach( @sort ) {
    if( $_ > $obsnum ) {
      $next = $_;
      last;
    }
  }

  # Return. Make sure we return an int so that we don't return something
  # like "00003".
  if( defined( $next ) ) {
    return int( $next );
  } else {
    return undef;
  }
}

sub get_utdate {
  if( defined( $OPT{'ut'} ) ) {
    return $OPT{'ut'};
  } else {
    my $datetime = DateTime->now;
    return $datetime->ymd('');
  }
}
