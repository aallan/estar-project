#!/software/perl-5.8.6/bin/perl


=head1 NAME

make_observation - command line client to generate an observation request

=head1 SYNOPSIS

  make_observation

=head1 DESCRIPTION

A simple command line client to generate an observation request trigger
to the user_agent

=head1 AUTHORS

Alasdair Allan (aa@astro.ex.ac.uk)

=head1 REVISION

$Id: make_observation.pl,v 1.6 2008/02/26 14:54:15 aa Exp $

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

#use strict;
use vars qw / $VERSION $log /;

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.6 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR User Agent Software:\n";
      print "Observation Client $VERSION; PERL Version: $]\n";
      exit;
    }
  }
}

# L O A D I N G -------------------------------------------------------------

# eSTAR modules
use lib $ENV{ESTAR_PERL5LIB};
use eSTAR::Nuke;
use eSTAR::Logging;
use eSTAR::Constants qw /:status/; 
use eSTAR::Util;
use eSTAR::Process;

# general modules
#use SOAP::Lite +trace => all;  
use SOAP::Lite;
use Digest::MD5 'md5_hex';
use URI;
use HTTP::Cookies;
use Sys::Hostname;
use Config::User;
use Getopt::Long;


# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
my $process = new eSTAR::Process( "make_observations" );  

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
$log = new eSTAR::Logging( $process->get_process() );

# Toggle debugging in the log system, passing ESTAR__QUIET will turn off 
# debugging while ESTAR__DEBUG will turn it on.
$log->set_debug(ESTAR__DEBUG);

# Start of log file
$log->header("Starting Observation Script: Version $VERSION");

# C O M M A N D   L I N E   A R G U E M E N T S -----------------------------

my ( %opt, %observation );

# grab options from command line
my $status = GetOptions( "host=s"     => \$opt{"host"},
                         "port=s"     => \$opt{"port"},
                         "user=s"     => \$observation{"user"},
                         "pass=s"     => \$observation{"pass"},
                         "ra=s"       => \$observation{"ra"},
                         "dec=s"      => \$observation{"dec"},
                         "target=s"   => \$observation{"target"},
			 "project=s"  => \$observation{"project"},
                         "exposure=s" => \$observation{"exposure"},
                         "sn=s"       => \$observation{"signaltonoise"},
                         "mag=s"      => \$observation{"magnitude"},
                         "passband=s" => \$observation{"passband"},
                         "type=s"     => \$observation{"type"},
                         "followup=s" => \$observation{"followup"},
                         "groupcount=s" => \$observation{"groupcount"},
                         "starttime=s" => \$observation{"starttime"},
                         "endtime=s" => \$observation{"endtime"},
                         "seriescount=s" => \$observation{"seriescount"},
                         "interval=s" => \$observation{"interval"},
                         "tolerance=s" => \$observation{"tolerance"},
			 "toop=s" => \$observation{"toop"},
                         "priority=s" => \$observation{"priority"}
                          );

# default hostname
unless ( defined $opt{"host"} ) {
   # localhost.localdoamin
   $opt{"host"} = "127.0.0.1";
}

# default port
unless( defined $opt{"port"} ) {
   # default port for the user agent
   $opt{"port"} = 8000;   
}

# build endpoint
my $endpoint = "http://" . $opt{"host"} . ":" . $opt{"port"};
my $uri = new URI($endpoint);

$log->debug("Connecting to server at $endpoint");

# default number of followup observations is 0 if type = SingleExposure
if ( defined $observation{"type"} ) {

   # we have a type defined, but no followup
   unless ( defined $observation{"followup"} ) {
      if( $observation{"type"} eq "SingleExposure") {
         $observation{"followup"} = 0;
      } else {
         $observation{"followup"} = 1;
      }
   }
} else {

   # we have no type defined, default to type = SingleExposure
    $observation{'type'} = 'SingleExposure';
    $observation{'followup'} = 0;
}    
      
# default user, note that this user is the default interprocess
# communication user, and wont have actual telescope access permissions
unless ( defined $observation{"user"} && defined $observation{"user"} ) {
   # default interprocess communication user and password
   $observation{"user"} = "agent";   
   $observation{"pass"} = "InterProcessCommunication";
}

# create authentication cookie
$log->debug("Creating authentication token");
my $cookie = 
    eSTAR::Util::make_cookie($observation{"user"},$observation{"pass"});
  
my $cookie_jar = HTTP::Cookies->new();
$cookie_jar->set_cookie(0, user => $cookie, '/', $uri->host(), $uri->port());

# create SOAP connection
$log->print("Building SOAP client...");
 
# create SOAP connection
my $soap = new SOAP::Lite();
$soap->uri('urn:/user_agent'); 
$soap->proxy($endpoint, cookie_jar => $cookie_jar);

$log->print("Calling new_observation( " );
foreach my $key ( keys %observation ) {
  $log->print("                         $key => " . $observation{$key});
}
  $log->print("                        )");
    
#use Data::Dumper; print Dumper($soap);    
    
# grab result 
my $result;
eval { $result = $soap->new_observation( %observation ); };
if ( $@ ) {
  $log->error("Error: $@");
  exit;   
}
  
# Check for errors
$log->debug("Transport Status: " . $soap->transport()->status() );
unless ($result->fault() ) {
  $log->print("SOAP Result     : " . $result->result() );
} else {
  $log->error("Fault Code      : " . $result->faultcode() );
  $log->error("Fault String    : " . $result->faultstring() );
}  
  
exit;
