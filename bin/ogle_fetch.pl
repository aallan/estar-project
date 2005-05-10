#!/software/perl-5.8.6/bin/perl


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

$Id: ogle_fetch.pl,v 1.2 2005/05/10 00:25:10 aa Exp $

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
  $VERSION = sprintf "%d.%d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR User Agent Software:\n";
      print "OGLE Fetch $VERSION; PERL Version: $]\n";
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
my $process = new eSTAR::Process( "ogle_fetch" );  

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
   $config->set_option("ua.host", $ip );
   $config->set_option("ua.port", 8000 );

   # interprocess communication
   $config->set_option("of.user", "agent" );
   $config->set_option("of.passwd", "InterProcessCommunication" );
   
   # ogle page
   $config->set_option("of.remote", "cgi.st-andrews.ac.uk");
   $config->set_option("of.url", "cgi/~cdbs/optimise.pl");

   # connection options defaults
   $config->set_option("connection.timeout", 5 );
   $config->set_option("connection.proxy", 'NONE'  );
  
   # mail server
   $config->set_option("mailhost.name", 'butch' );
   $config->set_option("mailhost.domain", 'astro.ex.ac.uk' );
   $config->set_option("mailhost.timeout", 30 );
   $config->set_option("mailhost.debug", 0 );   
   
   # science (defaults are for LT)
   $config->set_option("science.long", "-17.88166" );
   $config->set_option("science.lat", "28.76" );
   $config->set_option("science.elev", "2326" );
   $config->set_option("science.Vmean", "20.0" );
   $config->set_option("science.k", "0.1" );
   $config->set_option("science.aperture", "2.0" );
   $config->set_option("science.thruput", "60" );
   $config->set_option("science.bandwidth", "1410" );
   $config->set_option("science.QE", "90" );
   $config->set_option("science.pixel", "0.27" );
   $config->set_option("science.gain", "2.6" );
   $config->set_option("science.ron", "2.5" );
   $config->set_option("science.bias", "1200" );
   $config->set_option("science.sat", "60000" );
   $config->set_option("science.tread", "10" );
   $config->set_option("science.slew", "30" );
   $config->set_option("science.data", "PLENS" );
   $config->set_option("science.time", "TONIGHT" );
   $config->set_option("science.seeing", "1.0" );
   $config->set_option("science.q", "0.001" );
   $config->set_option("science.dchi", "25" );
   $config->set_option("science.hours", "2.0" );
    
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
                         
                         "long=s"     => \$opt{"long"},
                         "lat=s"      => \$opt{"lat"},
                         "elev=s"     => \$opt{"elev"},
                         "hours=s"    => \$opt{"hours"},
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
              "hrspernight" => $config->get_option("science.hours") ];

my $url = "http://" . $config->get_option("of.remote") . "/" . 
          $config->get_option("of.url");

# F E T C H   O G L E   U R L ------------------------------------------------

$log->debug("URL = $url" );
$log->debug("Fetching page..." );
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

# we should have a reply
my @page = split "\n", ${$reply}{_content};

print Dumper( @page );

# Validate our reply, certain strings should be in certain places. If 
# they aren't in the right place then 

# use the headers from line 11 of the page
my @headers = split "<td>", $page[10];

# get rid of the first <tr>
shift @headers;

# get rid of the trailing <tr>
$headers[10] =~ s/<\/tr>//;

foreach my $i ( 0 ... $#headers ) {
   $headers[$i] =~ s/^\s+//g;
   $headers[$i] =~ s/\s+$//g;
}
print Dumper( @headers );

# check things, if they aren't right throw an error
unless ( $headers[0] eq "rank" &&
         $headers[1] eq "event" &&
         $headers[2] eq "mag" &&
         $headers[3] eq "A" &&
         $headers[4] eq "t-t0" &&
         $headers[5] eq "t_E" &&
         $headers[6] eq "nx(read+exp)= tobs" &&
         $headers[7] eq "S/N" &&
         $headers[8] eq "g" &&
         $headers[9] eq "W" &&
         $headers[10] eq "Chi/N"  ) {
   my $error = "Error: Page does not parse correctly";
   $log->error( "Retrieved HTML:\n" );
   foreach my $i ( 0 ... $#page ) {
      $log->error( $page[$i] );
   }         
   $log->error( $error );
   throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
}   

# loop through the remaining part of the table and discard any rows which
# aren't data (the repeated "rank" lines are annoying special cases and 
# have to be removed from the list).
my @data;
foreach my $j ( 11 ... $#page ) {
   last if $page[$j] =~ "</table>"; # end of the data table
   next if $page[$j] =~ "rank";     # non-data line
   
   my @columns = split "<td>", $page[$j];
   shift @columns;
   $columns[10] =~ s/<\/tr>//;
   
   foreach my $k ( 0 ... $#columns ) {
      $columns[$k] =~ s/^\s+//g;
      $columns[$k] =~ s/\s+$//g;
   }  
    


   # grab the unique event name which we'll use as a key
   my $key = $columns[1];
   $key =~ 
    s/<a href=http:\/\/star-www.st-and.ac.uk\/~kdh1\/cool\/blg-\d+.html>//;
   $key =~ s/<\/a>//;
   
   # get URL
   my $url = $columns[1];
   $url =~ s/<a href=//;
   $url =~ s/>OGLE-\n+-blg-\n+<\/a>//;
   
   # get number of exposures
   my $num = $columns[6];
   $num =~ s/x\(\d+\+\d+\)=\d+s$//;
   
   # get exposure time
   my $read = $columns[6];
   $read =~ s/^\d+x\(//;
   $read =~ s/\+\d+\)=\d+s$//;
   my $exp = $columns[6];
   $exp =~ s/^\d+x\(\d+\+//;
   $exp =~ s/\)=\ds$//; 
   
   my $time = $read + $exp; 
   
   # build the hash entry
   my $ref = { ID => $key, URL => $url, Number => $num, Time => $time };
   push @data, $ref;
   
   #print "\$j = $j\n\n";
   #print Dumper( @columns );
   #print "\nKey = $key\nURL = $url\nNum = $num\nRead = $read\nExp = $exp\nTime = $time\n";
   #print "\n\n\n";

}

print Dumper ( @data );

  
exit;
