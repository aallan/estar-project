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
  $VERSION = sprintf "%d.%d", q$Revision: 1.68 $ =~ /(\d+)\.(\d+)/;
 
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
  my $files_arrayref = shift;
  my @files = @$files_arrayref;

  my $sigma_limit = $config->get_option("corr.sigma_limit");

  # Form Astro::Catalog objects from the list of files.
  my @threads;
  my @variable_catalogs;
  my @catalogs;
  if( $files[0] =~ /\.fit$/ ) {
    @catalogs = map{ new Astro::Catalog( Format => 'FITSTable',
                                         File => $_ ) } @files;
    $log->debug( "Got catalogues in binary FITS table format." );
  } elsif( $files[0] =~ /\.cat$/ ) {
    @catalogs = map{ new Astro::Catalog( Format => 'Cluster',
                                         File => $_ ) } @files;
    $log->debug( "Got catalogues in Cluster format." );
  }
  
  # grab the filter from the first item of the first catalogue, we're
  # in a case where we only have one filter so this isn't a problem.
  $log->debug( "Grabbing filter from first catalogue item...");
  my $star = $catalogs[0]->starbyindex(0);
  print "FIRST TIME READ FROM DISK\n";
  use Data::Dumper; print Dumper( $star );
      
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
   
  # create placeholders for the new and variable object catalogues.   
  my $new_objects = new Astro::Catalog;
  my $var_objects = new Astro::Catalog;

  # Correlate, finding objects that are not in one catalogue but are
  # in another.
  $log->print("Matching star catalogues" );

  foreach my $i ( 0 .. ( $#catalogs - 1 ) ) {
    foreach my $j ( ( $i + 1 ) .. ( $#catalogs ) ) {

      # LOOK FOR NEW OBJECTS
      # --------------------

      $log->print("Looking for new objects (catalogues $i & $j)...");

      my $cat1 = dclone($catalogs[$i]);
      my $cat2 = dclone($catalogs[$j]);
      $log->debug( "Correlating catalogues $i and $j to find new objects..." );
      my $corr = new Astro::Correlate( catalog1 => $cat1,
                                       catalog2 => $cat2,
                                       method => 'FINDOFF',
                                       verbose => 0,
                                     );

      my ( $corrcat1, $corrcat2 );
      ( $corrcat1, $corrcat2 ) = $corr->correlate;
      $cat1 = dclone($catalogs[$i]);
      $cat2 = dclone($catalogs[$j]);
      
      $log->debug( "Catalogue $i has " . $cat1->sizeof . " objects before" .
                   " matching and " . $corrcat1->sizeof . " objects afterwards." );
      $log->debug( "Catalogue $j has " . $cat2->sizeof . " objects before" .
                   " matching and " . $corrcat2->sizeof . " objects afterwards." );

      # We can still access the catalog_files in this loop and pull the 
      # correct datestamp from the relevant headers to create the catalog 
      # objects

      $log->debug( "Reading $files[$i]" );
      my $header1 = new Astro::FITS::Header::CFITSIO( File => $files[$i] );
      tie my %keywords1, "Astro::FITS::Header", $header1, tiereturnsref => 1;

      $log->debug( "Reading $files[$j]" );
      my $header2 = new Astro::FITS::Header::CFITSIO( File => $files[$j] );
      tie my %keywords2, "Astro::FITS::Header", $header2, tiereturnsref => 1;

      my $date1 = $keywords1{'SUBHEADERS'}->[0]->{'DATE-OBS'};
      if ( defined $date1 ) {
        $log->debug("FITS headers (catalog $i): DATE: $date1");
        $date1 = DateTime::Format::ISO8601->parse_datetime( $date1 );
      }

      my $date2 = $keywords2{'SUBHEADERS'}->[0]->{'DATE-OBS'};
      if ( defined $date2 ) {
        $log->debug("FITS headers (catalog $j): DATE: $date2");
        $date2 = DateTime::Format::ISO8601->parse_datetime( $date2 );
      }

      # Now, get a list of objects that -didn't- match between the two
      # catalogues.
      $log->debug( "Generating list of non-matching objects from catalogue $i");
      foreach my $star ( $corrcat1->stars ) {
        $star->comment =~ /^Old ID: (\d+)$/;
        my $oldid = $1;
        my $origstar = $cat1->popstarbyid( $oldid );
      }
      $log->debug( "Generating list of non-matching objects from catalogue $j");
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

      # date stamp the stars
      foreach my $star ( @cat1objects ) {
        if ( defined $date1 ) {
          $star->fluxdatestamp( $date1 );
          $log->debug( "Attaching DateTime to star ID " . $star->id() .
                       " from catalogue $i");
        }
      }
      foreach my $star ( @cat2objects ) {
        if ( defined $date2 ) {
          $star->fluxdatestamp( $date2 );
          $log->debug( "Attaching DateTime to star ID " . $star->id() .
                       " from catalogue $j");
        }
      }

      # push to new objects catalog
      $new_objects->pushstar( @cat1objects, @cat2objects );

      # LOOK FOR VARIABLE STARS
      # -----------------------

      $log->print("Looking for variable stars (catalogues $i & $j)...");
      my @vars = match_catalogs( $corrcat1, $corrcat2 );

      if ( defined $vars[0] ) {

        foreach my $i ( 0 ... $#vars ) {
          $log->print_ncr("The following star is a possible variable:");
          $log->print( " ID $vars[$i]" );

          my $star_from1 = $corrcat1->popstarbyid( $vars[$i] );
          if ( defined $date1 ) {  
            foreach my $star ( @$star_from1 ) {
              $star->fluxdatestamp( $date1 );
              $log->debug( "Attaching DateTime to star ID " . $star->id() . 
                           " from list of variable objects");
            }
          }
          $var_objects->pushstar( @$star_from1 );

          my $star_from2 = $corrcat2->popstarbyid( $vars[$i] );
          if ( defined $date2 ) {  
            foreach my $star ( @$star_from2 ) {
              $star->fluxdatestamp( $date2 );
              $log->debug( "Attaching DateTime to star ID " . $star->id() . 
                           " from list of variable objects");
            }
          }

          $var_objects->pushstar( @$star_from2 );
        }
      } else {
        $log->print( "No stars vary at the " . $sigma_limit . " sigma level");
      }
    }
  }

  # loop through each of the two catalogues and compare the stars and see
  # if we have objects that are actually the same physical object. We do
  # this by looking at the distance between the stars (if they're really
  # close toether <2 arcsec (perhaps?) then they're probably the same
  # object and we'll merge the records.

  my $new_object_catalogue = new Astro::Catalog();
  my $var_object_catalogue = new Astro::Catalog();

  my $separation = $config->get_option( "corr.maxsep" );
  $log->print("Merging new star detections...");
  my @deleted;
  foreach my $i ( 0 ... ( $new_objects->sizeof() - 1 ) ) {
    my $star1 = $new_objects->starbyindex( $i );

    foreach my $j ( ( $i + 1 ) .. ( $new_objects->sizeof() - 1 ) ) {
      my $done_flag;
      foreach my $k ( 0 ... $#deleted) {
        $done_flag = 1 if $deleted[$k] == $j;
      }
      next if $done_flag;

      my $star2 = $new_objects->starbyindex( $j );

      $log->print( "Comparing star $i with star $j" );

      if ( $star1->within( $star2, $separation ) ) {

        # if the timestamp on the fluxes object is the same as for both
        # then this is actually the same object and we can ignore it...
        my @flux = $star1->fluxes()->fluxesbywaveband( 
	                              waveband => $OPT{'filter'} );
        my $same_flag;
        foreach my $f ( @flux ) {
          if ( $f->datetime() == $star2->fluxes()->flux( 
	                               waveband =>  $OPT{'filter'},
                                       type => 'isophotal_flux' )->datetime() ) {
            $log->debug( "Star $i and star $j are identical..." );
	    $same_flag = 1;
          }
        }

        push @deleted, $j;
        $log->warn( "Setting star $j as deleted...");

        next if $same_flag;

        $log->debug( "Star $i and star $j are within the merge radius of " .
                     $separation . " arcsec" );	       	  	 
        $log->debug( "Merging flux(es) from star $j into star $i");
        my $fluxes1 = $star1->fluxes();
        my $fluxes2 = $star2->fluxes();
        $fluxes1->merge( $fluxes2 );
        $star1->fluxes( $fluxes1, 1 );

      } else {
        $log->debug( "Star $i and star $j appear to be independant" );
      }
    }

    my $push_flag = 1;
    foreach my $k ( 0 ... $#deleted) {
      $push_flag = 0 if $deleted[$k] == $i;
    }
    if ( $push_flag ) {
      $log->debug( "Pushing star $i into \$new_object_catalogue" );
      $new_object_catalogue->pushstar( $star1 );
    } else {
      $log->debug("Star $i has been deleted, so not pushed to catalogue...");
    }
  }

  #use Data::Dumper;
  #print Dumper( $new_object_catalogue );
  #exit;

  $log->print("Merging variable star detections...");
  my @var_deleted;
  foreach my $i ( 0 ... ( $var_objects->sizeof() - 1 ) ) {
    my $star1 = $var_objects->starbyindex( $i );

    foreach my $j ( ( $i + 1 ) .. ( $var_objects->sizeof() - 1 ) ) {
      my $done_flag;
      foreach my $k ( 0 ... $#var_deleted) {
        last unless defined $var_deleted[0];
        $done_flag = 1 if $var_deleted[$k] == $j;
      }
      next if $done_flag;

      my $star2 = $var_objects->starbyindex( $j );

      $log->print( "Comparing star $i with star $j" );

      if ( $star1->within( $star2, $separation) ) {

        # if the timestamp on the fluxes object is the same as for both
        # then this is actually the same object and we can ignore it...
        my @flux = $star1->fluxes()->fluxesbywaveband( 
	                       waveband => $OPT{'filter'} );
        my $same_flag;
        foreach my $f ( @flux ) {
          if ( $f->datetime() == $star2->fluxes()->flux( 
	                       waveband =>  $OPT{'filter'},
                               type => 'isophotal_flux' )->datetime() ) {

            $log->debug( 	"Star $i and star $j are identical..." );
	          $same_flag = 1;
          }
        }

        push @var_deleted, $j;
        $log->warn( "Setting star $j as deleted...");

        next if $same_flag;		

        $log->debug( "Star $i and star $j are within the merge radius of " .
                     $separation . " arcsec" );

        $log->debug( "Merging flux(es) from star $j into star $i");
        my $fluxes1 = $star1->fluxes();
        my $fluxes2 = $star2->fluxes();
        $fluxes1->merge( $fluxes2 );
        $star1->fluxes( $fluxes1, 1 );

      } else {
        $log->debug( "Star $i and star $j appear to be independant" );
      }
    }

    my $push_flag = 1;
    foreach my $k ( 0 ... $#var_deleted) {
      last unless defined $var_deleted[0];
      $push_flag = 0 if $var_deleted[$k] == $i;
    }
    if ( $push_flag ) {
      $log->debug( "Pushing star $i into \$var_object_catalogue" );
      $var_object_catalogue->pushstar( $star1 );
    } else {
      $log->debug("Star $i has been deleted, so not pushed to catalogue...");
    }
  }

  #use Data::Dumper;
  #print Dumper( $var_object_catalogue );
  #exit;

  $log->print( "Found " . $new_object_catalogue->sizeof() .
               " object(s) that did not match spatially between catalogues." );
  $log->print( "Found " . $var_object_catalogue->sizeof() .
               " object(s) that may be potential variable stars." );

#  $log->print("New Objects:");
#  my @tmp_star1 = $new_object_catalogue->allstars();
#  foreach my $t1 ( @tmp_star1 ) {
#     print "ID " . $t1->id() . "\n";
#     my $tmp_fluxes1 = $t1->fluxes();
#     my @tmp_flux1 = $tmp_fluxes1->fluxesbywaveband( waveband =>  $OPT{'filter'} );
#     foreach my $f1 ( @tmp_flux1 ) {
#  	$log->debug("  Date: " . $f1->datetime()->datetime() .
#  	            " (" . $f1->type() . ")" );
#     }
#     print "\n";
#  }
#  $log->print("Variable Objects:");
#  my @tmp_star2 = $var_object_catalogue->allstars();
#  foreach my $t2 ( @tmp_star2 ) {
#     print "ID " . $t2->id() . "\n";
#     my $tmp_fluxes2 = $t2->fluxes();
#     my @tmp_flux2 = $tmp_fluxes2->fluxesbywaveband( waveband => $OPT{'filter'} );
#     foreach my $f2 ( @tmp_flux2 ) {
#  	$log->debug("  Date: " . $f2->datetime()->datetime() .
#  	            " (" . $f2->type() . ")" );
#     }
#     print "\n";
#  }
#  exit;

  # dispatch list of variables, and list of all stars to DB web
  # service via a SOAP call. We'll pass the lists as Astro::Catalog
  # objects to avoid any sort of information loss. We can do this
  # because we're running all Perl. If we need interoperability
  # later, we'll move to document literal.
  # end point

  $log->print( "Creating thread to dispatch results..." );
  my $dispatch = threads->create( \&call_webservice,
                                  $new_object_catalogue,
                                  $var_object_catalogue,
                                  @catalogs );

  unless ( defined $dispatch ) {
    $log->error( "Error: Could not spawn a thread to talk to the DB" );
    $log->error( "Error: Returning ESTAR__FATAL to main loop..." );
    return ESTAR__FATAL;
  }
  $log->debug( "Detaching thread...");
  $dispatch->detach();

  #my $status;
  #eval { $status = call_webservice( $new_object_catalogue,
  #				    $var_object_catalogue,
  #			            @catalogs ); };

  #if ( $@ ) {
  #  $log->error( "Error: $@" );
  #  exit;
  #}

  #unless ( $status == ESTAR__OK ) {
  #  $log->error( "Error: Exiting with bad status ($status)" );
  #  exit;
  #}

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
  $log->debug( "Pushing $catalog_file onto stack." );
  push @catalog_files, $catalog_file;

  if( $catalog_file =~ /\.fit$/ ) {

    # Read in the header of the FITS file, check to see if we're
    # at the end of a microstep sequence or not.
    $log->debug( "Reading $catalog_file" );
    my $header = new Astro::FITS::Header::CFITSIO( File => $catalog_file );
    tie my %keywords, "Astro::FITS::Header", $header, tiereturnsref => 1;

    my $nustep = $keywords{'SUBHEADERS'}->[0]->{'NUSTEP'};
    my $ustep_position = $keywords{'SUBHEADERS'}->[0]->{'USTEP_I'};
    $log->debug("FITS headers: nustep: $nustep ustep_pos: $ustep_position");
    if( $ustep_position == $nustep && $nustep != 1 ) {

      $spawn_correlation = 1;
    }
    if( $nustep == 1 ) {
      @catalog_files = ();
    }
  } elsif( $catalog_file =~ /\.cat$/ ) {
    if( scalar( @catalog_files ) == 2 ) {
      $spawn_correlation = 1;
    }
  }

  if( $spawn_correlation ) {
    $log->print( "Spawing correlation process..." );
    correlate( \@catalog_files );
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
  
