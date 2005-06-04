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
  $VERSION = sprintf "%d.%d", q$Revision: 1.35 $ =~ /(\d+)\.(\d+)/;
 
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
use Storable qw/ dclone /;
use Math::Libm qw(:all);

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
   $config->set_option("corr.camera2_directory",  
                       $config->get_option( "dir.data" ) );
   
   $config->set_option("corr.camera3_prefix", "y" );
   $config->set_option("corr.camera2_directory",  
                       $config->get_option( "dir.data" ) ); 
   
   $config->set_option("corr.camera4_prefix", "z" );
   $config->set_option("corr.camera2_directory",  
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
  my $new_objects = new Astro::Catalog;

  # Correlate, finding objects that are not in one catalogue but are
  # in another.
  foreach my $i ( 0 .. ( $#catalogs - 1 ) ) {
    foreach my $j ( ( $i + 1 ) .. ( $#catalogs ) ) {
      my $cat1 = dclone($catalogs[$i]);
      my $cat2 = dclone($catalogs[$j]);
      my $corr = new Astro::Correlate( catalog1 => $cat1,
                                       catalog2 => $cat2,
                                       method => 'FINDOFF',
                                     );

      ( my $corrcat1, my $corrcat2 ) = $corr->correlate;

      $log->debug( "Catalogue 1 has " . $cat1->sizeof . " objects before" .
                   " matching and " . $corrcat1->sizeof . " objects afterwards." );
      $log->debug( "Catalogue 2 has " . $cat2->sizeof . " objects before" .
                   " matching and " . $corrcat2->sizeof . " objects afterwards." );

      # Now, get a list of objects that -didn't- match between the two
      # catalogues.
      foreach my $star ( $corrcat1->stars ) {
        $star->comment =~ /^Old ID: (\d+)$/;
        my $oldid = $1;
        my $origstar = $cat1->popstarbyid( $oldid );
      }
      foreach my $star ( $corrcat2->stars ) {
        $star->comment =~ /^Old ID: (\d+)$/;
        my $oldid = $1;
        my $origstar = $cat2->popstarbyid( $oldid );
      }

      # $cat1 and $cat2 are now catalogues of objects that did not match
      # between the two input catalogues. Merge them into the "new_objects"
      # catalogue.
      my @cat1objects = $cat1->stars;
      my @cat2objects = $cat2->stars;
      $new_objects->pushstar( @cat1objects );
      $new_objects->pushstar( @cat2objects );

      $log->print("Matching catalogues...");
      my @vars = match_catalogs( $corrcat1, $corrcat2 );

      if ( defined $vars[0] ) {
        $log->print("The following stars are possible variables:");
        foreach my $i ( 0 ... $#vars ) {
          $log->print( "   Star ID $vars[$i]" );
        }
      } else {
        $log->print("No stars vary at the 3 sigma level");	 
      }
    }
  }

  $log->print( "Found " . $new_objects->sizeof() . " objects that did not match" .
               " spatially between catalogues." );

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
  my $catalog_file = File::Spec->catfile( 
                       $config->get_option( "corr.camera${camera}_directory" ),
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
    $log->print( 
       "Spawning correlation_callback() to handle catalogue correlation..." );

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

# -------------------------------------------------------------------------
# F I T T  I N G   R O U T I N E S 
# -------------------------------------------------------------------------


sub match_catalogs {
   my $corr1 = shift;
   my $corr2 = shift;
   
  my (@data, @errors, @ids); 
  foreach my $i ( 0 ... $corr1->sizeof() - 1 ) {
     
     # Grab magnitude for STAR from Catalogue 1
     my $star1 = $corr1->starbyindex( $i );
     
     my $mag1 = $star1->get_magnitude('unknown');
     $mag1 = pow( (-$mag1/2.5), 10);
     my $id1 = $star1->id();
     
     my $err1 = sqrt( $mag1 );
     $err1 = $mag1 + $err1;
     
     $mag1 = -2.5*log10( $mag1 );
     $err1 = abs ( -2.5*log10( $err1 ) );
     $err1 = abs( $err1 ) - abs ($mag1 ) ;
          
     # Find the corresponding STAR in Catalogue 2
     
     my @stars2 = $corr2->popstarbyid( $id1 );
     unless ( scalar(@stars2) == 1 ) {
        print "Duplicate IDs, yuck...\n";
	#print Dumper( @stars2 );
	exit;
     }
     my $star2 = $stars2[0];
     
     # Grab magnitude for STAR from Catalogue 2     
     my $mag2 = $star2->get_magnitude('unknown');
     $mag2 = pow( (-$mag2/2.5), 10);
     my $id2 = $star2->id();
     
     my $err2 = sqrt( $mag2 );  
     $err2 = $mag2 + $err2;
       
     $mag2 = -2.5*log10( $mag2 );
     $err2 = abs ( -2.5*log10( $err2 ) );     
     $err2 = abs ($err2) - abs ($mag2) ;
     
     my $diff_mag = $mag1 - $mag2;
     my $diff_err = sqrt ( pow( $err1, 2) + pow( $err2, 2) );
     
#     print "STAR $id1,$id2 has $mag1 +- $err1 and $mag2 +- $err2\n";     	
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
     if( $sigmas[$m] > 3 ) {
         push @vars, $ids[$m];  
     }	
  }  
  
  #print Dumper( @vars );
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
         $wmean = $sumav/$sumerr;
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


