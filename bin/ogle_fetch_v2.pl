#!/software/perl-5.8.8/bin/perl


=head1 NAME

ogle_fetch - command line client fetch OGLE priorities

=head1 SYNOPSIS

  make_observation

=head1 DESCRIPTION

A simple command line client to generate observation requests triggering
to the user_agent to observe a list of OGLE events.

=head1 AUTHORS

Alasdair Allan (aa@astro.ex.ac.uk)

=head1 REVISION

$Id: ogle_fetch_v2.pl,v 1.4 2008/05/23 20:15:25 aa Exp $

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

#use strict;
use vars qw / $VERSION /;

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.4 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR User Agent Software:\n";
      print "OGLE Fetch V2 ($VERSION); PERL Version: $]\n";
      exit;
    }
  }
}

# L O A D I N G -------------------------------------------------------------

# Threading code (ithreads)
use threads;
use threads::shared;

# eSTAR modules
use lib $ENV{ESTAR_PERL5LIB};
use eSTAR::Nuke;
use eSTAR::Error qw /:try/;
use eSTAR::Constants qw /:status/; 
use eSTAR::Logging;
use eSTAR::Util;
use eSTAR::Mail;
use eSTAR::Process;
use eSTAR::Config;
use eSTAR::UserAgent;

# general modules
#use SOAP::Lite +trace => all;  
use SOAP::Lite;
use POSIX qw(:sys_wait_h);
use Errno qw(EWOULDBLOCK EINPROGRESS);
use Net::Domain qw(hostname hostdomain);
use Fcntl qw(:DEFAULT :flock);
use Time::localtime;
use Digest::MD5 'md5_hex';
use URI;
use LWP::UserAgent;
use HTTP::Cookies;
use Sys::Hostname;
use Config::User;
use Getopt::Long;
use Data::Dumper;
use Config;
use Socket;

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
my $process = new eSTAR::Process( "ogle_fetch_v2" );  

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process->set_version( $VERSION );


# turn off buffering
$| = 1;

# Get date and time
my $date = scalar(localtime);
my $host = hostname;

# L O G G I N G --------------------------------------------------------------

# Start logging
# -------------

# start the log system
my $log = new eSTAR::Logging( $process->get_process() );

# Toggle debugging in the log system, passing ESTAR__QUIET will turn off 
# debugging while ESTAR__DEBUG will turn it on.
$log->set_debug(ESTAR__DEBUG);

# Start of log file
$log->header("Starting OGLE Fetch Script: Version $VERSION");

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
$number = $config->get_state( "of.unique_process" ); 
unless ( defined $number ) {
  # $number is not defined correctly (first ever run of the program?)
  $number = 0; 
}

# increment ID number
$number = $number + 1;
$config->set_state( "of.unique_process", $number );
$log->debug("Setting of.unique_process = $number"); 
  
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
$config->set_state( "of.pid", getpgrp() );
  
# commit $pid to STATE file
$status = $config->write_state();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Can not read or write to state.dat file";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("OGLE Fetch PID: " . $config->get_state( "of.pid" ) );
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

if ( $config->get_state("of.unique_process") == 1 ) {
  
   # user agentrameters
   $config->set_option("ua.host", "estar5.astro.ex.ac.uk" );
   $config->set_option("ua.port", 8000 );

   # interprocess communication
   $config->set_option("of.user", "agent" );
   $config->set_option("of.passwd", "InterProcessCommunication" );
   $config->set_option("of.project", "exoplanet" );
   
   # ogle page
#   $config->set_option("of.remote", "cgi.st-andrews.ac.uk");
#   $config->set_option("of.url", "cgi/~cdbs/optimise.pl");

#   $config->set_option("of.remote", "robonet.astro.livjm.ac.uk");
#   $config->set_option("of.url", "~robonet/newcode/cgi-bin/optimise.cgi");

   $config->set_option("of.remote", "robonet.lcogt.net");
   $config->set_option("of.url", "~robonet/newcode/cgi-bin/optimise.cgi");

#   $config->set_option("of.remote", "algo1.lcogt.net");
#   $config->set_option("of.url", "robonet/newcode/cgi-bin/optimise.cgi");

   # connection options defaults
   $config->set_option("connection.timeout", 20 );
   $config->set_option("connection.proxy", 'NONE'  );
  
   # mail server
   $config->set_option("mailhost.name", 'mail.ex.ac.uk' );
   $config->set_option("mailhost.domain", 'astro.ex.ac.uk' );
   $config->set_option("mailhost.timeout", 30 );
   $config->set_option("mailhost.debug", 0 );   
   
   # science 
   $config->set_option("science.Vmean", "19.0" );
   $config->set_option("science.k", "0.1" );
   $config->set_option("science.aperture", "2.0" );
   $config->set_option("science.thruput", "60" );
   $config->set_option("science.bandwidth", "1410" );
   $config->set_option("science.QE", "90" );
   $config->set_option("science.pixel", "0.27" );
   $config->set_option("science.gain", "2.708" );
   $config->set_option("science.ron", "2.33" );
   $config->set_option("science.bias", "1200" );
   $config->set_option("science.sat", "60000" );
   $config->set_option("science.tread", "10" );
   $config->set_option("science.slew", "30" );
   $config->set_option("science.data", "PLENS" );
   $config->set_option("science.time", "NOW" );
   $config->set_option("science.OPTIMISE", "NOW" );
   $config->set_option("science.seeing", "1.0" );
   $config->set_option("science.q", "0.001" );
   $config->set_option("science.dchi", "25" );
   $config->set_option("science.hours", "1.0" );
   $config->set_option("science.last_data", "ROBONET" );
   $config->set_option("science.tel_max_exp", "180" );
   $config->set_option("science.anomalies", "TRUE" );
   
   # long, lat & elev defaults are for the LT
   #$config->set_option("science.long", "-17.88166" );
   #$config->set_option("science.lat", "28.76" );
   #$config->set_option("science.elev", "2326" );
       
   # C O M M I T T   O P T I O N S  T O   F I L E S
   # ----------------------------------------------
   
   # committ CONFIG and STATE changes
   $log->warn("Initial default options being generated");
   $log->warn("Committing options and state changes...");
   $status = $config->write_option( );
   $status = $config->write_state();
}

# H T T P   U S E R   A G E N T ----------------------------------------------

$log->debug("Creating an HTTP User Agent...");
 

# Create HTTP User Agent
my $lwp = new LWP::UserAgent( 
                timeout => $config->get_option( "connection.timeout" ));

# Configure User Agent                         
$lwp->env_proxy();
$lwp->agent( "eSTAR OGLE Fetch /$VERSION (" 
             . hostname() . ")" );

my $ua = new eSTAR::UserAgent(  );  
$ua->set_ua( $lwp );

# C O M M A N D   L I N E   A R G U E M E N T S -----------------------------

# grab options from command line
my %opt;
my $status = GetOptions( "host=s"     => \$opt{"host"},
                         "port=s"     => \$opt{"port"},
                         
                         "user=s"     => \$opt{"user"},
                         "pass=s"     => \$opt{"pass"},
                         "project=s"  => \$opt{"project"},
                         
                         "long=s"     => \$opt{"long"},
                         "lat=s"      => \$opt{"lat"},
                         "elev=s"     => \$opt{"elev"},
                         "hours=s"    => \$opt{"hours"},
                         
                         "start=s"    => \$opt{"start"},
                         "end=s"      => \$opt{"end"}
                          );

# N O N - S C I E N C E   D E F A U L T S -----------------------------------

# default hostname
unless ( defined $opt{"host"} ) {
   my $ip = inet_ntoa(scalar(gethostbyname(hostname())));
   $opt{"host"} = $config->get_option("ua.host");
} else{
   if ( defined $config->get_option("ua.host") ) {
      $log->warn("Warning: Resetting host from" . 
              $config->get_option("ua.host") . " to $opt{host}");
   }           
   $config->set_option("ua.host", $opt{"host"});
}

# default port
unless( defined $opt{"port"} ) {
   $opt{"port"} = $config->get_option("ua.port");   
} else {
   if ( defined $config->get_option("ua.port") ) {
      $log->warn("Warning: Resetting port from " . 
              $config->get_option("ua.port") . " to $opt{port}");
   }
   $config->set_option("ua.port", $opt{"port"});
}


# default user and password location
unless( defined $opt{"user"} ) {
   $opt{"user"} = $config->get_option("of.user");
} else{       
   if ( defined $config->get_option("of.user") ) {
      $log->warn("Warning: Resetting username from " .
                $config->get_option("of.user") . " to $opt{user}");
      $config->set_option("of.user", $opt{"user"} );
   }
}

# default user and password location
unless( defined $opt{"pass"} ) {
   $opt{"pass"} = $config->get_option("of.passwd");
} else{       
   if ( defined $config->get_option("of.passwd") ) {
      $log->warn("Warning: Resetting password...");
      $config->set_option("of.passwd", $opt{"pass"} );
   }
}

# default projecct location
unless( defined $opt{"project"} ) {
   $opt{"project"} = $config->get_option("of.project");
} else{       
   if ( defined $config->get_option("of.project") ) {
      $log->warn("Warning: Resetting project from " .
                $config->get_option("of.project") . " to $opt{project}");
      $config->set_option("of.project", $opt{"project"} );
   }
}


# S C I E N C E   D E F A U L T S --------------------------------------------

unless( defined $opt{"long"} ) {
   $opt{"long"} = $config->get_option("science.long");
   $log->warn( "Using default longitude of $opt{long}" );
} else{       
   if ( defined $config->get_option("science.long") ) {
      $log->debug("Resetting longitude from " .
                $config->get_option("science.long") . " to $opt{long}");
      $config->set_option("science.long", $opt{"long"} );
   }   
}

unless( defined $opt{"lat"} ) {
   $opt{"lat"} = $config->get_option("science.lat");
   $log->warn( "Using default latitude of $opt{lat}" );
} else{       
   if ( defined $config->get_option("science.lat") ) {
      $log->debug("Resetting latitude from " .
                $config->get_option("science.lat") . " to $opt{lat}");
      $config->set_option("science.lat", $opt{"lat"} );
   }   
}

unless( defined $opt{"elev"} ) {
   $opt{"elev"} = $config->get_option("science.elev");
   $log->warn( "Using default elevation of $opt{elev}" );
} else{       
   if ( defined $config->get_option("science.elev") ) {
      $log->debug("Resetting elevation from " .
                $config->get_option("science.elev") . " to $opt{elev}");
      $config->set_option("science.elev", $opt{"elev"} );
   }   
}

unless( defined $opt{"hours"} ) {
   $opt{"hours"} = $config->get_option("science.hours");
   $log->warn( "Using default value of $opt{hours}hr for number of hours" );
} else{       
   if ( defined $config->get_option("science.hours") ) {
      $log->debug("Resetting hours per night from " .
                $config->get_option("science.hours") . " to $opt{hours}");
      $config->set_option("science.hours", $opt{"hours"} );
   }   
}

# B U I L D   U R L ----------------------------------------------------------

$log->debug("Building request..." );

my $query = [ "long"        => $config->get_option("science.long"),
              "lat"         => $config->get_option("science.lat"),
              "elev"        => $config->get_option("science.elev"),
              "Vmean"       => $config->get_option("science.Vmean"),
              "k"           => $config->get_option("science.k"),
              "aperture"    => $config->get_option("science.aperture"),
              "thruput"     => $config->get_option("science.thruput"),
              "bandwidth"   => $config->get_option("science.bandwidth"),
              "QE"          => $config->get_option("science.QE"),
              "pixel"       => $config->get_option("science.pixel"),
              "gain"        => $config->get_option("science.gain"),
              "ron"         => $config->get_option("science.ron"),
              "bias"        => $config->get_option("science.bias"),
              "sat"         => $config->get_option("science.sat"),
              "tread"       => $config->get_option("science.tread"),
              "slew"        => $config->get_option("science.slew"),
              "data"        => $config->get_option("science.data"),
              "time"        => $config->get_option("science.time"),
              "seeing"      => $config->get_option("science.seeing"),
              "q"           => $config->get_option("science.q"),
              "dchi"        => $config->get_option("science.dchi"),
              "hrspernight" => $config->get_option("science.hours"),
	      "OPTIMISE"    => $config->get_option("science.OPTIMISE" ),
              "last_data"   => $config->get_option("science.last_data"),
   	      "tel_max_exp" => $config->get_option("science.tel_max_exp" ),
              "anomalies"   => $config->get_option("science.anomalies" ),
	      "output"      => "ASCII" ];

my $url = "http://" . $config->get_option("of.remote") . "/" . 
          $config->get_option("of.url");

# F E T C H   O G L E   U R L ------------------------------------------------

$log->debug("URL = $url" );
$log->print("Fetching page..." );
my $reply;
eval { $reply = $ua->get_ua()->post( $url, $query ) };

# we're fucked, live with it
if ( $@ ) {
   $log->error( "Error: $@" );
   $log->error( "Exiting with bad status..." );
   throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
}   

# We successfully made a request but it returned bad status
unless ( ${$reply}{"_rc"} eq 200 ) {
  # the network connection failed?      
  $log->error( "Error: (${$reply}{_rc}): ${$reply}{_msg}");
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
}
 
$log->print(${$reply}{_content});

$log->debug("Harvesting content from data file...");
 
# we should have a reply
my @page = split "\n", ${$reply}{_content};

#print Dumper( @page );
#exit;

# P A R S E   D A T A -----------------------------------------------------

# loop through the remaining part of the table and discard any rows which
# aren't data (the repeated "rank" lines are annoying special cases and 
# have to be removed from the list).
my @data;
foreach my $j ( 0 ... $#page ) {
   
   my @columns = split " ", $page[$j];
   foreach my $k ( 0 ... $#columns ) {
      $columns[$k] =~ s/^\s+//g;
      $columns[$k] =~ s/\s+$//g;
   }  

   # get key
   my $key = $columns[0];

   # get exposure time
   my $time = $columns[4];

   # get number of exposures in series
   my $series = $columns[3];
      
   # get RA & Dec
   my $ra = $columns[1];
   $ra =~ s/:/ /g;

   my $dec = $columns[2];
   $dec =~ s/:/ /g;

   $log->debug("Line ($j) $key: $series x $time seconds exposures at $ra, $dec");

   # don't bother to add it to the hash if we aren't going to observe it
   unless ( $series == 0 ) {
   
      # build the hash entry
      my $ref = {ID => $key, SeriesCount => $series, Time => $time, RA => $ra, Dec => $dec };
      push @data, $ref;
   }   


}

# F I X   G R O U P C O U N T S --------------------------------------------

# we have all the necessary data to schedule the observations now, however
# it's likely that some of the exposure times are greater then 120 seconds
# which is the maximum *right now* for the FTN. So we munge the exposure 
# times so this isn't going to generate multiruns we didn't know about.


foreach my $n ( 0 ... $#data ) {

   $count = 0;
   while ( ${$data[$n]}{Time} > 120 ) {
      ${$data[$n]}{Time} = ${$data[$n]}{Time}/2.0;
      $count = $count + 1;
   }
   if ( $count > 0 ) {
      ${$data[$n]}{GroupCount} = $count*2;
   }      

}

#print Dumper ( @data );


# O B S E V R A T I O N   R E Q U E S T S   T O   U S E R   A G E N T -------

my $year = 1900 + localtime->year();
my $month = localtime->mon() + 1;
my $day = localtime->mday();

my $hour = localtime->hour();
my $min = localtime->min();
$sec = localtime->sec();

# could be last day of the month
if ( $day >= 28 && $day <= 31 ) {
  
  # Special case for Februry
  if ( $month == 2 ) {
  
     # insert code to handle leap year here
  
     $month = $month + 1;
     $day = 1;
     
  } elsif ( $month == 9 || $month == 4 || $month == 6 || $month == 11 ) {
    if( $day == 30 ) {
       $month = $month + 1;
       $day = 1;
    }
    
  } elsif ( $day == 31 ) {
    $month = $month + 1;
    $day = 1;
  }  
}

# fix roll over errors
my $dayplusone = $day + 1;
my $hourplustwelve = $hour + 13; # Actually plus 13 hours, not 12 now!
if( $hourplustwelve > 24 ) {
  $hourplustwelve = $hourplustwelve - 24;
} 
 
# fix less than 10 errors
$month = "0$month" if $month < 10;
$day = "0$day" if $day < 10;   
$hour = "0$hour" if $hour < 10;   
$min = "0$min" if $min < 10;   
$sec = "0$sec" if $sec < 10;   
$dayplusone = "0$dayplusone" if $dayplusone < 10;   
$hourplustwelve = "0$hourplustwelve" if $hourplustwelve < 10;

# defaults of now till 12 hours later 
my ( $start_time, $end_time ); 
 
# modify start time
unless( defined $opt{"start"} ) {
   $start_time = "$year-$month-$day" . "T". $hour.":".$min.":".$sec . "UTC";
} else {
   $start_time = $opt{"start"};
} 

# modify end time
unless( defined $opt{"start"} ) {
   $end_time = "$year-$month-$dayplusone" . 
               "T". $hourplustwelve.":".$min.":".$sec . "UTC"; 
} else {
   $end_time = $opt{"end"};  
}    

foreach my $n ( 0 ... $#data ) {

   my $interval = 6.0*60.0*60.0/${$data[$n]}{SeriesCount};
   my $tolerance = $interval*0.95;  # set t0 0.5 later in the season
   $interval = $interval . "S";
   $tolerance = $tolerance . "S";

   my $counter = $n+1;
   $log->print("\nBuilding observation request $counter of " . scalar(@data) );

   #print Dumper ( $data[$n] );
   
   $log->print("Building observation object for ${$data[$n]}{ID}" );
   $log->print("Co-ordinates (RA ${$data[$n]}{RA}, Dec ${$data[$n]}{Dec}" .")");

   #my @name = split "-", ${$data[$n]}{ID};
   #my $year = $name[1];
   #$year =~ s/20//;
   #my $id = "OB". $year. sprintf("%03d", $name[3]);
   #${$data[$n]}{ID} = $id;
   #$log->warn("Warning: Fixing object name to ${$data[$n]}{ID}" );
    
   my %observation;
   if ( defined ${$data[$n]}{GroupCount} &&
        ${$data[$n]}{SeriesCount} == 1 ) {

      $log->print( "We have an single observation group of " . 
                   ${$data[$n]}{GroupCount} .  " exposures of " . 
                   ${$data[$n]}{Time} . "s");
         %observation = ( user          => $config->get_option("of.user"),
                          pass          => $config->get_option("of.passwd"),
                          ra            => ${$data[$n]}{RA},
                          dec           => ${$data[$n]}{Dec},
                          target        => ${$data[$n]}{ID},
                          exposure      => ${$data[$n]}{Time},
                          passband      => "R",
                          type          => "ExoPlanetMonitor",
                          followup      => 0,
                          groupcount    => ${$data[$n]}{GroupCount},
                          starttime     => $start_time,
                          endtime       => $end_time,
                          seriescount   => ${$data[$n]}{SeriesCount},
                          project       => $config->get_option("of.project"),
			  priority      => 1 );
          
   } elsif ( defined ${$data[$n]}{GroupCount} &&
             ${$data[$n]}{SeriesCount} > 1 ) {

      $log->print("We have a series of " . ${$data[$n]}{SeriesCount} .
                  " groups of " . ${$data[$n]}{GroupCount} . 
                  " exposures of " . ${$data[$n]}{Time} . "s" );
         %observation = ( user          => $config->get_option("of.user"),
                          pass          => $config->get_option("of.passwd"),
                          ra            => ${$data[$n]}{RA},
                          dec           => ${$data[$n]}{Dec},
                          target        => ${$data[$n]}{ID},
                          exposure      => ${$data[$n]}{Time},
                          passband      => "R",
                          type          => "ExoPlanetMonitor",
                          followup      => 0,
                          groupcount    => ${$data[$n]}{GroupCount},
                          starttime     => $start_time,
                          endtime       => $end_time,
                          seriescount   => ${$data[$n]}{SeriesCount},
                          interval      => $interval,
                          tolerance     => $tolerance,
                          project       => $config->get_option("of.project") );
                    
          
                          
   } elsif ( ${$data[$n]}{SeriesCount} == 1 ) {                       
     
      $log->print("We have a single exposure of  " . 
                  ${$data[$n]}{Time} . "s");
         %observation = ( user          => $config->get_option("of.user"),
                          pass          => $config->get_option("of.passwd"),
                          ra            => ${$data[$n]}{RA},
                          dec           => ${$data[$n]}{Dec},
                          target        => ${$data[$n]}{ID},
                          exposure      => ${$data[$n]}{Time},
                          passband      => "R",
                          type          => "ExoPlanetMonitor",
                          followup      => 0,
                          starttime     => $start_time,
                          endtime       => $end_time,
                          project       => $config->get_option("of.project") );
   } else {
   
      $log->print("We have a series of " . ${$data[$n]}{SeriesCount} . 
                  " exposures of " . ${$data[$n]}{Time} . "s");
         %observation = ( user          => $config->get_option("of.user"),
                          pass          => $config->get_option("of.passwd"),
                          ra            => ${$data[$n]}{RA},
                          dec           => ${$data[$n]}{Dec},
                          target        => ${$data[$n]}{ID},
                          exposure      => ${$data[$n]}{Time},
                          passband      => "R",
                          type          => "ExoPlanetMonitor",
                          followup      => 0,
                          starttime     => $start_time,
                          endtime       => $end_time,
                          seriescount   => ${$data[$n]}{SeriesCount},
                          interval      => $interval,
                          tolerance     => $tolerance,
                          project       => $config->get_option("of.project") );   
   
   }
   
   # build endpoint
   my $endpoint = "http://" . $config->get_option("ua.host") . 
                  ":" . $config->get_option("ua.port");
   my $uri = new URI($endpoint);

   $log->debug("Connecting to server at $endpoint");


   # create authentication cookie
   $log->debug( "Creating authentication token for " .
                $config->get_option("of.user"));
   my $cookie = 
        eSTAR::Util::make_cookie( $config->get_option("of.user"),
                                  $config->get_option("of.passwd") );
  
   my $cookie_jar = HTTP::Cookies->new();
   $cookie_jar->set_cookie(0, user => $cookie, '/', $uri->host(), $uri->port());

   # create SOAP connection
   $log->print("Building SOAP client...");
 
   # create SOAP connection
   my $soap = new SOAP::Lite();
   $soap->uri('urn:/user_agent'); 
   $soap->proxy($endpoint, cookie_jar => $cookie_jar);

   $log->debug("Calling new_observation( ) in 'urn:/user_agent' at $endpoint" );
   foreach my $key ( keys %observation ) {
     $log->print("                         $key => " . $observation{$key});
   }
    
    
   # grab the result 
   my $soap_result;
   eval { $soap_result = $soap->new_observation( %observation ); };
   
   # check for coding errors
   if ( $@ ) {
     my $error = "Error $@";
     $log->error( $error );
     throw eSTAR::Error::FatalError( $error, ESTAR__FATAL);
   }
  
   # Check for transport errors
   $log->print("Transport Status = " . $soap->transport()->status() );
   unless ($soap_result->fault() ) {
     $log->print("SOAP Result (" . $soap_result->result() .")" );
   } else {
     my $error = "Error: " . $soap_result->faultstring();
     $log->error("Error: Fault code = " . $soap_result->faultcode() );
     $log->error( $error );
     throw eSTAR::Error::FatalError( $error, ESTAR__FATAL);
   }  
  


}


# T I M E   A T   T H E   B A R ---------------------------------------------
 
exit;
