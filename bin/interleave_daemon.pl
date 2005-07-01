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
  $VERSION = sprintf "%d.%d", q$Revision: 1.3 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR Server Software:\n";
      print "Interleave Correlation Daemon $VERSION; PERL Version: $]\n";
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
use DateTime::Format::ISO8601;
use Time::localtime;
use Getopt::Long;
use Data::Dumper;
use Fcntl qw(:DEFAULT :flock);
use SOAP::Lite;
use Digest::MD5 'md5_hex';
use URI;
use HTTP::Cookies;
use Storable qw/ dclone /;
use Math::Libm qw(:all);
use Data::Dumper;
use Compress::Zlib;

# Astronomy modules
use Astro::Catalog;
use Astro::Correlate;
#use Astro::Corlate;
use Astro::FITS::Header::CFITSIO;

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process = new eSTAR::Process( "interleave_daemon" );  

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
$log->header("Starting Interleave Correlation Daemon: Version $VERSION");

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
   $config->set_option("db.urn", "wfcam_agent" );

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
   $config->set_option("corr.camera2_directory",  
                       $config->get_option( "dir.data" ) );
   
   $config->set_option("corr.camera3_prefix", "y" );
   $config->set_option("corr.camera3_directory",  
                       $config->get_option( "dir.data" ) ); 
   
   $config->set_option("corr.camera4_prefix", "z" );
   $config->set_option("corr.camera4_directory",  
                       $config->get_option( "dir.data" ) );
		       
   $config->set_option("corr.sigma_limit", "3" );
   $config->set_option("corr.maxsep", "2.0" ); # 2.0 arc seconds
		       
    
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
                      "camera=s"   => \$OPT{'camera'},
		      "sigma=s"    => \$OPT{'sigma'} );


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

# default sigma limit
unless( defined $OPT{"sigma"} ) {
   $OPT{"sigma"} = $config->get_option("corr.sigma_limit");
} else{
   $log->warn("Warning: Resetting variable star detection limit " .
              " to $OPT{sigma} sigma");
   $config->set_option("corr.sigma_limit", $OPT{"sigma"} );
}


# default camera
unless( defined $OPT{"camera"} ) {
   $OPT{"camera"} = $config->get_option("corr.camera")
      if defined $config->get_option("corr.camera");
} else{
   $log->warn("Warning: Resetting camera number to $OPT{camera}");
   $config->set_option("corr.camera", $OPT{"camera"} );
}


# -------------------------------------------------------------------------
# W E B   S E R V I C E S
# -------------------------------------------------------------------------

sub call_webservice {
  croak ( "main::call_webservice() called without arguements" )
     unless defined @_;

  my $thread_name = "populateDB()";
  
  $log->thread( $thread_name, "In main::call_webservice()..." );
  $log->thread($thread_name, "Starting client (\$tid = ".threads->tid().")");  
     
  my @args = @_;   
  
  my @chilled;
  foreach my $catalog ( @args ) {
     $catalog->reset_list(); # otherwise we breake the serialisation
     $log->debug( "Compressing catalogue...");
     my $string  = eSTAR::Util::chill( $catalog );
     my $compressed = Compress::Zlib::memGzip( $string );
     push @chilled, $compressed;
  }   
  
  # Debugging
  #use Data::Dumper;
  #print "DIRECTLY BEFORE DISPATCHING VIA WEBSERVICE\n";
  #print Dumper( $args[2]->starbyindex(0) );
  
  #print "\n\nTHE CHILLED VERSION OF THE SAME STAR\n";
  #print Dumper( eSTAR::Util::chill( $args[2]->starbyindex(0)) );
  
  
  $log->thread( $thread_name, "Connecting to WFCAM DB Web Service..." );
  
  my $endpoint = "http://" . $config->get_option( "db.host") . ":" .
              $config->get_option( "db.port");
  my $uri = new URI($endpoint);
  $log->debug("Web service endpoint $endpoint" );
  
  # create a user/passwd cookie
  $log->debug("Creating cookie..." );
  my $cookie = eSTAR::Util::make_cookie( "agent", "InterProcessCommunication" );
  
  $log->debug("Dropping cookie in jar..." );
  my $cookie_jar = HTTP::Cookies->new();
  $cookie_jar->set_cookie(0, user => $cookie, '/', $uri->host(), $uri->port());

  # create SOAP connection
  my $soap = new SOAP::Lite();
  
  my $urn = "urn:/" . $config->get_option( "db.urn" );
  $log->debug( "URN of endpoint service is $urn");
  
  $soap->uri($urn); 
  $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
  #use Data::Dumper;
  #print Dumper( $chilled[0] );  
    
  # report
  $log->thread( $thread_name, "Calling populate_db() in remote service");
    
  # grab result 
  my $result;
  eval { $result = $soap->populate_db(SOAP::Data->type(base64 => @chilled )); };
  if ( $@ ) {
    $log->warn( "Warning: Could not connect to $endpoint");
    $log->warn( "Warning: $@" );
      
  }  
  
  $log->debug( "Transport status: " . $soap->transport()->status() );
  unless ( defined $result ) {
    $log->error("Error: No result object is present..." );
    $log->error("Error: Returning ESTAR__FAULT to main thread" );
    return ESTAR__FAULT;
  }
    
  unless ($result->fault() ) {
    if ( $result->result() eq "OK" ) {
       $log->debug( "Recieved an ACK message from DB web service");
    } else {
       $log->warn( "Warning: Recieved status ".$result->result() ." from DB");
    }   
  } else {
    $log->warn("Warning: recieved fault code (" . $result->faultcode() .")" );
    $log->warn("Warning: " . $result->faultstring() );
    $log->thread( $thread_name, "Returning ESTAR__FAULT to main thread");
    return ESTAR__FAULT;
  }  

  $log->thread( $thread_name, "Returning ESTAR__OK to main thread");
  return ESTAR__OK;  
}

# ===========================================================================
# C A L L B A C K S
# ===========================================================================


sub correlate {
  my $file = shift;

  my $sigma_limit = $config->get_option("corr.sigma_limit");

  # Form Astro::Catalog objects from the list of files.
  my $catalog;
  if( $file =~ /\.fit$/ ) {
    $catalog = new Astro::Catalog( Format => 'FITSTable',File => $file);
    $log->debug( "Got catalogue in binary FITS table format." );
  } elsif( $file =~ /\.cat$/ ) {
    $catalog = new Astro::Catalog( Format => 'SExtractor',File => $file ) ;
    $log->debug( "Got catalogue in SExtractor format." );
  }
  
  # grab the filter from the first item of the first catalogue, we're
  # in a case where we only have one filter so this isn't a problem.
  $log->debug( "Grabbing filter from first catalogue item...");
  my $star = $catalog->starbyindex(0);
  #print "FIRST TIME READ FROM DISK\n";
  #use Data::Dumper; print Dumper( $star );
      
  my @waveband = $star->what_filters();
  if ( defined $waveband[0] ) {
     $log->debug( "Setting \$OPT{filter} to be '".$waveband[0]."'");
     $OPT{filter} = $waveband[0];
  } else {
     $log->warn( "Warning: The filter is undefined, setting as 'unknown'");
     $OPT{filter} = 'unknown';
  } 
  $log->warn("Warning: Resetting filter to '".$OPT{filter}."'");
  $config->set_option("corr.filter", $OPT{"filter"} );

  # Convert filter to waveband object
  my $waveband = new Astro::Waveband( filter => $OPT{filter} );  
   
  # GRAB CENTRE OF FIELD AND RADIUS
  # -------------------------------

# Following two lines are commented out pending catalogue central coordinate
# and radius creation by the Astro::Catalog::IO::FITSTable module.
#  my $coords = $catalog->get_coords;
#  my $radius = $catalog->get_gadius;

  my $coords = new Astro::Coords( ra => '10 52 33.68', 
                                  dec => '+57 13 49.65',
                                  type => 'J2000'
                                  units=> 'sexagesimal');
  my $radius = 120;                           # in arcseconds 

  # CONNECT TO DB WEB SERVICE
  # -------------------------
  
  my $endpoint = "http://" . $config->get_option( "db.host") . ":" .
              $config->get_option( "db.port");
  my $uri = new URI($endpoint);
  $log->debug("Web service endpoint $endpoint" );
  
  # create a user/passwd cookie
  $log->debug("Creating cookie..." );
  my $cookie = eSTAR::Util::make_cookie( "agent", "InterProcessCommunication" );
  
  $log->debug("Dropping cookie in jar..." );
  my $cookie_jar = HTTP::Cookies->new();
  $cookie_jar->set_cookie(0, user => $cookie, '/', $uri->host(), $uri->port());

  # create SOAP connection
  my $soap = new SOAP::Lite();
  
  my $urn = "urn:/" . $config->get_option( "db.urn" );
  $log->debug( "URN of endpoint service is $urn");
  
  $soap->uri($urn); 
  $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
  # report
  $log->thread( $thread_name, "Calling query_db() in remote service");
    
  # grab result 
  my $result;

  $log->debug( "Calling eSTAR::Util::chill( \$coords )");
  $coords = eSTAR::Util::chill( $coords );  
  $log->debug("Compresing \$coords...");
  $coords = Compress::Zlib::memGzip( $coords );
  $log->debug( "Calling eSTAR::Util::chill( \$waveband )");
  $waveband = eSTAR::Util::chill( $waveband ); 
  $log->debug("Compresing \$waveband...");
  $coords = Compress::Zlib::memGzip( $waveband );
  eval { $result = $soap->query_db( SOAP::Data->type(base64 => $coords ),
                                    $result,
				    SOAP::Data->type(base64 => $waveband) ); };
  if ( $@ ) {
    $log->warn( "Warning: Could not connect to $endpoint");
    $log->warn( "Warning: $@" );
      
  }  
  
  $log->debug( "Transport status: " . $soap->transport()->status() );
  unless ( defined $result ) {
    $log->error("Error: No result object is present..." );
    $log->error("Error: Returning ESTAR__FAULT to main thread" );
    return ESTAR__FAULT;
  }
    
  if ($result->fault() ) {
    $log->warn( "Warning: Recieved status ".$result->result() ." from DB");
    $log->warn("Warning: recieved fault code (" . $result->faultcode() .")" );
    $log->warn("Warning: " . $result->faultstring() );
    return ESTAR__FAULT;
  }
  
  my $compressed = $result->result();
  $log->debug( "Uncompressing catalogue...");
  my $string = Compress::Zlib::memGunzip( $compressed );
  	   
  $log->debug( "Calling eSTAR::Util::reheat( \$catalog )");
  my $db_catalog = eSTAR::Util::reheat( $string );

  # try and catch parsing errors here...
  if( $@ ) {
     $log->error("Error: $@");
     $log->warn("Warning: Returned SOAP Error message");
     die SOAP::Fault
  	->faultcode("Client.DataError")
  	->faultstring("Client Error: $@")
  } 
  
  # sanity check the passed values
  $log->debug("Doing a sanity check on the integrity of the catalogues");
  unless ( UNIVERSAL::isa( $db_catalog, "Astro::Catalog" ) ) {
     my $error = "Passed catalogue does not parse correctly";
     $log->error("Error: $error");
     $log->warn("Warning: Returned SOAP Error message");
     die SOAP::Fault
  	->faultcode("Client.DataError")
  	->faultstring("Client Error: $error")	
 
  } else {
     $log->debug( "Reference appears to be Astro::Catalog object");
  }  
     
  use Data::Dumper; 
  print Dumper( $db_catalog ); 
   
   
   
   

  # Send good status
  $log->print( "Returning ESTAR__OK to main loop..." );
  return ESTAR__OK;

};

# ===========================================================================
# M A I N   L O O P
# ===========================================================================

my $camera = $config->get_option("corr.camera");
$log->debug( "Beginning file loop for camera $camera." );

my $utdate = $starting_ut;
my $obsnum = $starting_obsnum;
my @catalog_files = ();

while( 1 ) {
  my $spawn_correlation = 0;
  $obsnum = flag_loop( $utdate, $obsnum, $camera );
  $log->debug( "Found flag file for observation $obsnum for camera $camera." );
  my $catalog_file = File::Spec->catfile(
                       $config->get_option( "corr.camera${camera}_directory" ),
                       cat_file_from_bits( $utdate, $obsnum, $camera ) );

  $log->print( "Spawing correlation process..." );
  correlate( $catalog_file );

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
  return "." . $prefix . $utdate . "_" . $obsnum . "_int" . ".ok";
}

sub cat_file_from_bits {
  my $utdate = shift;
  my $obsnum = shift;
  my $camera = shift;

  my $prefix = $config->get_option( "corr.camera${camera}_prefix" );

  $obsnum = "0" x ( 5 - length( $obsnum ) ) . $obsnum;
  return $prefix . $utdate . "_" . $obsnum . "_int_cat.fit";
#  return $prefix . $utdate . "_" . $obsnum . "_mos.cat";
}

sub data_file_from_bits {
  my $utdate = shift;
  my $obsnum = shift;
  my $camera = shift;
  my $prefix = $config->get_option( "corr.camera${camera}_prefix" );
  $obsnum = "0" x ( 5 - length( $obsnum ) ) . $obsnum;
  return $prefix . $utdate . "_" . $obsnum . ".sdf";
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

# -------------------------------------------------------------------------
# F I T T  I N G   R O U T I N E S 
# -------------------------------------------------------------------------


sub match_catalogs {
  my $cat1 = shift;
  my $cat2 = shift;
  
  my $sigma_limit = $config->get_option( "corr.sigma_limit" );

  # Deep clone the catalogues so we can popstarbyid
  my $corr1 = dclone($cat1);
  my $corr2 = dclone($cat2);
   
  my (@data, @errors, @ids); 
  foreach my $i ( 0 ... $corr1->sizeof() - 1 ) {

    # Grab magnitude for STAR from Catalogue 1
    my $star1 = $corr1->starbyindex( $i );
    
    #print Dumper( $star1 );
    
    my $id1 = $star1->id;
    my $fluxes1 = $star1->fluxes;
    
    #print Dumper( $fluxes1 );

    my $iso_flux1 = $fluxes1->flux( 
                        waveband => $OPT{'filter'},
                        type => 'isophotal_flux' );
				    
    #print Dumper( $iso_flux1 );
				    
    my $iso_flux1_quantity = $iso_flux1->quantity('isophotal_flux');
    my $iso_flux1_error = sqrt( $iso_flux1_quantity );

    my $iso_flux1_max = $iso_flux1_quantity + $iso_flux1_error;
    my $mag1 = -2.5 * log10( $iso_flux1_quantity );
    my $mag1_max = -2.5 * log10( $iso_flux1_max );
    my $mag1_err = abs( $mag1_max -  $mag1 );

    # Find the corresponding STAR in Catalogue 2
    my @stars2 = $corr2->popstarbyid( $id1 );
    unless ( scalar(@stars2) == 1 ) {
      my $error = "There are multiple stars with the same ID ($id1) " . 
      "in catalogue 2. This is a fatal error and should " .
      " not occur as FINDOFF should renumber the entries.";
      $log->error( "Error: $error" );
      throw eSTAR::Error::FatalError( $error, ESTAR__FATAL );
    }
    my $star2 = $stars2[0];

     # Grab magnitude for STAR from Catalogue 2
    my $id2 = $star2->id();
    my $fluxes2 = $star2->fluxes;
    my $iso_flux2 = $fluxes2->flux( 
                           waveband =>  $OPT{'filter'},
                           type => 'isophotal_flux' );
    my $iso_flux2_quantity = $iso_flux2->quantity('isophotal_flux');
    my $iso_flux2_error = sqrt( $iso_flux2_quantity );
    my $iso_flux2_max = $iso_flux2_quantity + $iso_flux2_error;

    my $mag2 = -2.5 * log10( $iso_flux2_quantity );
    my $mag2_max = -2.5 * log10( $iso_flux2_max );
    my $mag2_err = abs( $mag2_max - $mag2 );

     my $diff_mag = $mag1 - $mag2;
     my $diff_err = sqrt ( pow( $mag1_err, 2) + pow( $mag2_err, 2) );

#     print "STAR $id1,$id2 has $mag1 +- $mag1_err and $mag2 +- $mag2_err\n";
#     print "     $diff_mag +- $diff_err\n";

     push @data, $diff_mag;
     push @errors, $diff_err;
     push @ids, $id1;
     
  }
  
  my ( $wmean, $redchi, $reject ) = clip_wmean( \@data, \@errors );
  #print "$wmean, $redchi, $reject\n";
  
  # loop through the @data array and subtract the $wmean and then 
  # divide by the corresponding @error value. This will give us an
  # array containing sigma values. Any @sigma > than 3 or 4 is probably
  # a variable.
  my @sigmas;
  foreach my $k ( 0 ... $#data ) {
     $sigmas[$k] = abs( ( $data[$k] - $wmean ) / $errors[$k] );
#     print "sigma $k = $sigmas[$k]\n";
  }
  
  # loop through @sigmas, if $sigma[$m] is > 3 then this is probably a
  # variable star. Marshal the @ids and build a list of possible variables
  my @vars;
  foreach my $m ( 0 ... $#sigmas ) {
     if( $sigmas[$m] > $sigma_limit ) {
         push @vars, $ids[$m];  
     }	
  }  
  
  #print Dumper( @vars );
  
  # return a list of star IDs which are potiential variable stars
  # to the main code...
  return @vars;
  
}  
  

sub clip_wmean {
   my $data_ref = shift;
   my $error_ref = shift;
   
   my @data = @$data_ref;
   my @error = @$error_ref;
   
   # Takes a data and error array and returns a weighted mean a reduced
   # chi-squared value and the number of points rejected by the algorithim

   #   real, dimension(:), intent(in)::data, error
   #   real, intent(out):: wmean, redchi
   #   integer, intent(out):: reject
   #   integer, intent(in)::npoints

   my ( $wmean, $redchi, $chisq, $reject );
   
   if ( $#data <= 1 ) {
      $wmean = 0;
      $redchi = 0;
      $reject = 0;
      return ( $wmean, $redchi, $reject );
   }

   my $sumav = 0;
   my $sumerr = 0;
   foreach my $i ( 0 ... $#data ) {
      $sumav = $sumav + $data[$i] / ( pow ( $error[$i], 2) );
      $sumerr = $sumerr + ( 1.0 / pow ( $error[$i], 2) );
   }

   $redchi = 0;
   $wmean = $sumav / $sumerr;
   foreach my $j ( 0 ... $#data ) {
      $redchi = $redchi + pow( ( ($data[$j]-$wmean)/$error[$j] ) ,2);
   }
   $redchi = $redchi / scalar(@data);

   #print "sumav = $sumav\nsumerr = $sumerr\nredchi = $redchi\n".
   #      "wmean = $wmean\n";

   my $flag;
   while ( ! $flag ) {
      
      $reject = 0;
      $sumav = 0;
      $sumerr = 0;
      
      foreach my $j ( 0 ... $#data ) {
      
         if ( pow((($data[$j]-$wmean)/$error[$j]),2) < (4.0*$redchi ) ) {
             # Here we allow points in if their contribution to chi-squared
             # is less than 4 times the reduced chi squared, from the last fit
	     
	     #print "Star $j contributes\n";
             $sumav = $sumav + ( $data[$j]/pow($error[$j],2));
             $sumerr = $sumerr + (1.0/pow($error[$j],2));
         } else {
	     
	     #print "Star $j rejected\n";
             $reject = $reject + 1;
         }
      }
      
      if( $sumerr == 0.0 ) {
         $wmean = 0.0;
      } else { 
         $wmean = $sumav/($sumerr*$sumerr);  # should this just be $sumerr?
      }
      
      #print "sumav = $sumav\nsumerr = $sumerr\nredchi = $redchi\n".
      #      "wmean = $wmean\nreject=$reject\n";
      
      # Work out the chi-squared for the new fit.
      my $redchi_new = 0.0;
      foreach my $k ( 0 ... $#data ) {
         if ( pow((($data[$k]-$wmean)/$error[$k]),2) < (4.0*$redchi ) ) {
             $redchi_new = $redchi_new + pow((($data[$k]-$wmean)/$error[$k]),2);
         }
      }
      
      if ( scalar(@data) - $reject == 0.0 ) {
         $redchi_new = 0.0;
      } else {	 
         $redchi_new = $redchi_new/(scalar(@data) - $reject);
      }
      
      if ( $redchi == 0.0 ) {
         $flag = 1;
	 next;      
      
      } elsif (abs($redchi-$redchi_new)/$redchi < 1.0e-06) {
         $flag = 1;
	 next;
      }	 
      $redchi = $redchi_new;
   }
   
   return ( $wmean, $redchi, $reject );
   
}
  
