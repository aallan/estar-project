#!/Software/perl-5.8.8/bin/perl

use strict;
use vars qw / $VERSION $log /;

use threads;
use threads::shared;

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR User Agent Software:\n";
      print "Event Monitor $VERSION; PERL Version: $]\n";
      exit;
    }
  }
}

# L O A D   T K -------------------------------------------------------------
 
# 
# Tk modules
#
use Tk;
use Tk::ProgressBar;
use Tk::JPEG;
use Tk::Zinc;

# C R E A T E  M A I N  W I N D O W -----------------------------------------

my $status_text;
my $thread_text : shared;
my ( $MW, $canvas, $progress, $label )  = create_window();

# Create shared array
my @shared_array;
my $shared_ref = \@shared_array;
share( $shared_ref );

# L O A D I N G -------------------------------------------------------------

# eSTAR modules
use lib $ENV{ESTAR_PERL5LIB};
use eSTAR::Logging;
use eSTAR::Constants qw /:status/; 
use eSTAR::Config;
use eSTAR::Util;
use eSTAR::Process;
use eSTAR::UserAgent;
use eSTAR::Mail;

# general modules
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
use Data::Dumper;
use Carp;

use Starlink::AST;
use Starlink::AST::Tk;

use Astro::FITS::CFITSIO;
use Astro::FITS::Header::CFITSIO;

use Astro::VO::VOEvent;

use XMLRPC::Lite;
use XMLRPC::Transport::HTTP;

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
my $process = new eSTAR::Process( "event_monitor_plastic" );  

# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process->set_version( $VERSION );

# turn off buffering
$| = 1;

# Get date and time
my $date = scalar(localtime);
my $host = hostname;


# Update progress bar
$status_text = "Loaded modules ...";
$progress->value(5);
$progress->update();

# L O G G I N G --------------------------------------------------------------

# Start logging
# -------------

# start the log system
$log = new eSTAR::Logging( $process->get_process() );

# Toggle debugging in the log system, passing ESTAR__QUIET will turn off 
# debugging while ESTAR__DEBUG will turn it on.
$log->set_debug(ESTAR__DEBUG);

# Start of log file
$log->header("Starting Event Monitor: Version $VERSION");


# Update progress bar
$status_text = "Started logging...";
$progress->value(10);
$progress->update();

# C O N F I G U R A T I O N --------------------------------------------------

# Load in previously saved options, should be in a file in the users home 
# directory. If not there, we go with the defaults and commit basic defaults 
# to Options file

my $config = new eSTAR::Config(  );  

# Update progress bar
$status_text = "Loaded configuration ...";
$progress->value(15);
$progress->update();

# S T A T E   F I L E -------------------------------------------------------

# HANDLE UNIQUE ID
# ----------------

my ( $number, $string );
$number = $config->get_state( "ec.unique_process" ); 
unless ( defined $number ) {
  # $number is not defined correctly (first ever run of the program?)
  $number = 0; 
}

# increment ID number
$number = $number + 1;
$config->set_state( "ec.unique_process", $number );
$log->debug("Setting ec.unique_process = $number"); 
  
# commit ID stuff to STATE file
my $status = $config->write_state();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Can not read or write to state.dat file";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("Unique process ID: updated state.dat file" );
}

# PID OF PROGRAM
# --------------

# log the current $pid of the user_agent.pl process to the state 
# file  so we can kill it from the SOAP server.
$config->set_state( "ec.pid", getpgrp() );
  
# commit $pid to STATE file
$status = $config->write_state();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Can not read or write to state.dat file";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} else {    
  $log->debug("Event Monitor PID: " . $config->get_state( "ec.pid" ) );
}

# Update progress bar
$status_text = "Generated unique ID ...";
$progress->value(20);
$progress->update();

# M A K E   D I R E C T O R I E S -------------------------------------------

# create the data, state and tmp directories if needed
$status = $config->make_directories();
unless ( defined $status ) {
  # can't read/write to options file, bail out
  my $error = "FatalError: Problems creating data directories";
  $log->error( $error );
  throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
} 


# Update progress bar
$status_text = "Build backend directories ...";
$progress->value(25);
$progress->update();

# M A I N   O P T I O N S   H A N D L I N G ---------------------------------

# grab current IP address
my $ip = inet_ntoa(scalar(gethostbyname(hostname())));
$log->debug("This machine as an IP address of $ip");

if ( $config->get_state("ec.unique_process") == 1 ) {
  
   # local XMLRPC server
   $config->set_option("ec.host", $ip );
   $config->set_option("ec.port", 9002 );
   
   # connection options defaults
   $config->set_option("connection.timeout", 20 );
   $config->set_option("connection.proxy", 'NONE'  );
  
   # mail server
   $config->set_option("mailhost.name", 'butch' );
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


# Update progress bar
$status_text = "Set initial options ...";
$progress->value(30);
$progress->update();

# H T T P   U S E R   A G E N T ----------------------------------------------

$log->debug("Creating an HTTP User Agent...");
 
# Create HTTP User Agent
my $lwp = new LWP::UserAgent( 
                timeout => $config->get_option( "connection.timeout" ));

# Configure User Agent                         
$lwp->env_proxy();
$lwp->agent( "eSTAR Event Monitor /$VERSION (" . hostname() . ")" );

my $ua = new eSTAR::UserAgent(  );  
$ua->set_ua( $lwp );


# Update progress bar
$status_text = "Built HTTP user agent ...";
$progress->value(35);
$progress->update();

# C O M M A N D   L I N E   A R G U E M E N T S -----------------------------

my ( %opt, %observation );

# grab options from command line
my $status = GetOptions( 
                         "port=s"     => \$opt{"port"}
	               );

# default port
unless( defined $opt{"port"} ) {
   $opt{"port"} = $config->get_option("ec.port");   
} else {
   if ( defined $config->get_option("ec.port") ) {
      $log->warn("Warning: Resetting XMLRPC port from " . 
              $config->get_option("ec.port") . " to $opt{port}");
   }
   $config->set_option("ec.port", $opt{"port"});
}

 
# Update progress bar
$status_text = "Handled command line options ...";
$progress->value(40);
$progress->update();

# B U I L D   G U I ----------------------------------------------------------

$log->print( "Drawing all sky image..." );
my $photo = $canvas->Photo( -file => "./all_sky_j.jpg" );
$canvas->configure( -tile => $photo );

# Update progress bar
$status_text = "Drawn all sky image ...";
$progress->value(45);
$progress->update();

$log->debug("Beginning Starlink::AST context");
Starlink::AST::Begin();

# Update progress bar
$status_text = "Beginning AST context ...";
$progress->value(50);
$progress->update();

$log->debug("Building FitsChan...");
my $fc = new Starlink::AST::FitsChan( );
$fc->PutFits( "CRPIX1  = 512", 1 );
$fc->PutFits( "CRPIX2  = 256", 1 );
$fc->PutFits( "CRVAL1  = 0.0", 1 );
$fc->PutFits( "CRVAL2  = 0.0", 1 );
$fc->PutFits( "CTYPE1  = 'RA---AIT'", 1 );
$fc->PutFits( "CTYPE2  = 'DEC--AIT'", 1 );
$fc->PutFits( "CDELT1  = 0.35", 1 );
$fc->PutFits( "CDELT2  = 0.35", 1 );

# Update progress bar
$status_text = "Built FitsChan ...";
$progress->value(55);
$progress->update();

$fc->Clear( "Card" );
$log->debug("Building WCS FrameSet...");
my $wcs = $fc->Read( );

# Update progress bar
$status_text = "Built WCS FrameSet ...";
$progress->value(60);
$progress->update();

# AST axes
# --------
$log->debug("Building AST Plot..." );
my $plot = Starlink::AST::Plot->new( $wcs, 
   [0,0.1,1,0.9],[0.0, 0.0, 1024.0, 512.0], "Grid=1");

# Update progress bar
$status_text = "Built AST Plot ...";
$progress->value(65);
$progress->update();

$log->debug("Ploting to Tk Canvas...");
my $status = $plot->tk( $canvas );

# Update progress bar
$status_text = "Plotted to Tk Canvas ...";
$progress->value(70);
$progress->update();

$plot->Set( Colour => 11, Width => 1, 'Size(title)' => 1.5 );
$plot->Set( Title => "Real Time Event Monitor" );

# Update progress bar
$status_text = "Calculating grid lines ...";
$progress->value(75);
$progress->update();

$plot->Grid();

# Update progress bar
$status_text = "Plotted grid lines ...";
$progress->value(80);
$progress->update();


# D A E M O N -------------------------------------------------------------

$log->print("Starting Plastic Daemon...");
my $daemon = threads->new( \&daemon_process );
$daemon->detach;

# Update progress bar
$status_text = "Started Plastic Daemon ...";
$progress->value(85);
$progress->update();

# R P C -------------------------------------------------------------------

$log->debug("Getting XMLRPC endpoint from .plastic file...");
# Grab an RPC endpoint for the ACR
my $file = File::Spec->catfile( Config::User->Home(), ".plastic" );
croak( "Unable to open file $file" ) unless open(PREFIX, "<$file" );

$/ = "\n"; # shouldn't be necessary?
my @prefix = <PREFIX>;
close( PREFIX );

my $endpoint;
foreach my $i ( 0 ... $#prefix ) {
  if ( $prefix[$i] =~ "plastic.xmlrpc.url" ) {
     my @line = split "=", $prefix[$i];
     chomp($line[1]);
     $endpoint = $line[1];
     $endpoint =~ s/\\//g;
  }    
}
$log->debug("Plastic Hub Endpoint: $endpoint");
my $rpc = new XMLRPC::Lite();
$rpc->proxy($endpoint);

# Update progress bar
$status_text = "Hub: $endpoint";
$progress->value(90);
$progress->update();

# R E G I S T E R ----------------------------------------------------------

$status_text = "Waiting for XMLPRC server to start...";
$log->debug("Waiting for server to start...");
$progress->value(95);
$progress->update();
sleep(5);

my @list;
$list[0] = 'ivo://votech.org/test/echo';
$list[1] = 'ivo://votech.org/info/getName';
$list[1] = 'ivo://votech.org/info/getIVORN';
$list[2] = 'ivo://votech.org/info/getVersion';
$list[3] = 'ivo://votech.org/info/getIconURL';
$list[4] = 'ivo://votech.org/hub/event/ApplicationRegistered';
$list[5] = 'ivo://votech.org/hub/event/ApplicationUnregistered';
$list[6] = 'ivo://votech.org/hub/event/HubStopping';
$list[7] = 'ivo://votech.org/hub/Exception';
$list[8] = 'ivo://votech.org/sky/pointAtCoords';

$log->print("Registering with Plastic hub" );
my $register;
eval{ $register = $rpc->call( 'plastic.hub.registerXMLRPC', 
                              'eSTAR Event Monitor', \@list, "http://". 
			      $config->get_option("ec.host").":".
			      $config->get_option("ec.port")."/" ); };

if( $@ ) {
   my $error = "$@";
   croak( "Error: $error" );
}   

my $id;
unless( $register->fault() ) {
   $id = $register->result();
   $log->debug("Got Plastic ID of $id");
} else {
   croak( "Error: ". $register->faultstring );
}

# Update progress bar
$status_text = "Registered with Hub";
$progress->value(100);
$progress->update();

# M A I N L O O P ------------------------------------------------------------

$MW->after(100, \&update_window );

# enter Tk mainloop()
$progress->destroy();
MainLoop();
exit;

# A S S O C I A T E D   S U B - R O U T I N E S #############################

# test harness window
sub create_window {

   my $font = 'helvetica 12';
   
   my $MW = MainWindow->new();
   $MW->positionfrom("user");
   $MW->geometry("+40+100");
   $MW->title("Event Monitor");   
   $MW->iconname("Event Monitor");
   $MW->configure( -cursor => "tcross" );

   # create the canvas widget
   my $canvas = $MW->Zinc( -render      => 1,
                           -width       => 640, 
			   -height      => 400, 
			   -font        => $font,
			   -backcolor   => 'darkgrey',
			   -borderwidth => 3 );
   $canvas->pack();

   my $frame = $MW->Frame( -relief => 'flat', -borderwidth => 1 );
   $frame->pack( -side => 'bottom', -fill => 'both', -expand => 'yes');
   
   my $label = $frame->Label( -width      => 40,
			      -anchor     =>'w',
			      -foreground =>'blue',
			      -font => $font,
                              -textvariable => \$status_text);  
   $label->pack( -side => 'left' ); 
   
   my $progress = $frame->ProgressBar( -from        => 0, 
                                       -to          => 100, 
                                       -width       => 15, 
			               -length      => 270,
                                       -blocks      => 20, 
			               -anchor      => 'w',
                                       -colors      => [0, 'blue'],
                                       -relief      => 'sunken',
                                       -borderwidth => 3,
                                       -troughcolor => 'grey',);
   $progress->pack( -side => 'left' ); 

   my $button = $frame->Button( -text             => 'Quit',
                                -font             => 'Helvetica 12',
	   		        -activeforeground => 'white',
                                -activebackground => 'red',
                                -foreground       => 'white',
                                -background       => 'darkgrey',
                                -borderwidth      => 3,
                                -command => sub { exit; } );
   $button->pack( -side => 'right' );
   $MW->update;
   
   return ($MW, $canvas, $progress, $label);
}

sub update_window {
   #print "Calling update_window ($thread_text)\n";
   
   $status_text = $thread_text;
   my $coord;
   {
      lock( @$shared_ref );
      $coord = pop @$shared_ref;
   } # implicit unlock here 
   if ( defined $coord ) {
      my ( $ra, $dec ) = split ",", $coord;
      $status_text = "Plotting event on sky...";
          
      $log->debug( "Converting RA $ra, Dec $dec to Galactic" );
      my $sky = Starlink::AST::SkyFrame->new('');
      $sky->Set( System => "FK5" );
      my $ra1 = $sky->Unformat( 1, $ra."d" );
      my $dec1 = $sky->Unformat( 2, $dec."d" );

      my $gal = Starlink::AST::SkyFrame->new('');
      $gal->Set( System => "GALACTIC" );
     
      my $convert = $sky->Convert( $gal, "" ); 
      $convert->Set( Report => 1 );
      my ( $aref, $dref ) = $convert->Tran2( [$ra1], [$dec1], 1 );
      
      $plot->Set( Colour => 2, Width => 5 );
      $plot->Mark(24, $aref, $dref);
   }   
   $MW->after(100, \&update_window );
}


# D A E M O N   S E R V E R   T H R E A D ###################################

sub daemon_process {

  my $name = "Daemon";
  $log->thread2($name, "Starting daemon process (\$tid = ".threads->tid().")");
  my $daemon;
  eval { $daemon = XMLRPC::Transport::HTTP::Daemon
   -> new (LocalPort => $config->get_option("ec.port"), 
  	   LocalHost => $config->get_option("ec.host") )
   -> dispatch_to( 'perform' );  };
  if ( $@ ) {
     my $error = "$@";
     croak( "Error: $error" );
  }		
  
  my $url = $daemon->url();   
  $log->thread2($name, "Starting XMLRPC server at $url");

  eval { $daemon->handle; };  
  if ( $@ ) {
    my $error = "$@";
    croak( "Error: $error" );
  }  
  
  $log->thread2($name, "Server started sucessfully, waiting...");
  while(1) { };

}

# P L A S T I C   D A E M O N  C A L L B A C K S ---------------------------

sub perform {
  Plastic::perform( @_ );
  $thread_text = "";
}  

package Plastic;

use Data::Dumper;

my $log;

sub perform {
  my @args = @_;
  $log = eSTAR::Logging::get_reference();

  my $name = "Plastic";
  $log->thread($name, "In perform()");
  #print Dumper( @args );
  $thread_text = "$args[2]";
  
  if ($args[2] eq 'ivo://votech.org/test/echo' ) {
     $log->thread($name, 'ivo://votech.org/test/echo' );
     $thread_text = "Echoing $args[3]";
     return $args[3];
  }
  if ($args[2] eq 'ivo://votech.org/info/getName' ) {
     $log->thread($name, 'ivo://votech.org/info/getName' );
     return "eSTAR Event Monitor";
  }
  if ($args[2] eq 'ivo://votech.org/info/getIvorn' ) {
     $log->thread($name, 'ivo://votech.org/info/getIvorn' );
     return "ivo://uk.org.estar";
  }   
  if ($args[2] eq 'ivo://votech.org/info/getVersion' ) {
     $log->thread($name, 'ivo://votech.org/info/getVersion' );
     return "0.4";
  }
  if ($args[2] eq 'ivo://votech.org/info/getIconURL' ) {
     $log->thread($name, 'ivo://votech.org/info/IconURL' );
     return "http://www.estar.org.uk/png/estar-e-trans.png";
  }   
  if ($args[2] eq 'ivo://votech.org/hub/event/ApplicationRegistered' ) {
     $log->thread($name, 'ivo://votech.org/event/ApplicationRegistered' );
     return 1;
  }   
  if ($args[2] eq 'ivo://votech.org/hub/event/ApplicationUnregistered' ) {
     $log->thread($name, 'ivo://votech.org/event/ApplicationUnregistered' );
     return 1;
  }   
  if ($args[2] eq 'ivo://votech.org/hub/event/HubStopping' ) {
     $log->thread($name, 'ivo://votech.org/event/HubStopping' );
     $thread_text = "Hub stopping...";
     $log->warn("Warning: Hub Stopping Message" );
  }   
  if ($args[2] eq 'ivo://votech.org/hub/Exception' ) {
     $log->thread($name, 'ivo://votech.org/hub/Exception' );
     $log->warn("Warning: Hub Exception Message" );
     $log->warn("Warning: $args[3]");
     return 1;
  }   
  
  if($args[2] eq 'ivo://votech.org/sky/pointAtCoords' ) {
     $thread_text = "ivo://votech.org/sky/pointAtCoords";
     $log->thread($name, 'ivo://votech.org/sky/pointAtCoords' );
     my $ra = ${$args[3]}[0];
     my $dec = ${$args[3]}[1];
     $log->debug( "Recieved an event at ($ra, $dec)");
     {
     	lock( @$shared_ref );
     	push  @$shared_ref, $ra.",".$dec;
     } # implicit unlock here	
     
     my $return = XMLRPC::Data->type( boolean => 'true' );    
     return $return;
  }  
  
}
