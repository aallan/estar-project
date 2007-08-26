#!/Software/perl-5.8.8/bin/perl

use strict;
use vars qw / $VERSION $log /;

use threads;
use threads::shared;

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.5 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR User Agent Software:\n";
      print "Event Monitor $VERSION; PERL Version: $]\n";
      exit;
    }
  }
}

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
use POSIX qw(:sys_wait_h);
use Errno qw(EAGAIN);
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
use Net::FTP;
use File::Copy;
use Astro::VO::VOEvent;


# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
my $process = new eSTAR::Process( "event_client_kml" );  

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
$log->header("Starting Event Client: Version $VERSION");


# C O N F I G U R A T I O N --------------------------------------------------

# Load in previously saved options, should be in a file in the users home 
# directory. If not there, we go with the defaults and commit basic defaults 
# to Options file

my $config = new eSTAR::Config(  );  


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
  $log->debug("Event Client PID: " . $config->get_state( "ec.pid" ) );
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

if ( $config->get_state("ec.unique_process") == 1 ) {

   # event broker
   $config->set_option("eb.host", "144.173.229.22" );
   $config->set_option("eb.port", 8099 );

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


# C O M M A N D   L I N E   A R G U E M E N T S -----------------------------

my ( %opt, %observation );

# grab options from command line
my $status = GetOptions( 
                         "host=s"     => \$opt{"host"},
                         "port=s"     => \$opt{"port"}
	               );

# default hostname
unless ( defined $opt{"host"} ) {
   my $ip = inet_ntoa(scalar(gethostbyname(hostname())));
   $opt{"host"} = $config->get_option("eb.host");
} else{
   if ( defined $config->get_option("eb.host") ) {
      $log->warn("Warning: Reseting host from " . 
              $config->get_option("eb.host") . " to $opt{host}");
   }           
   $config->set_option("eb.host", $opt{"host"});
}

# default port
unless( defined $opt{"port"} ) {
   $opt{"port"} = $config->get_option("eb.port");   
} else {
   if ( defined $config->get_option("eb.port") ) {
      $log->warn("Warning: Reseting port from " . 
              $config->get_option("eb.port") . " to $opt{port}");
   }
   $config->set_option("eb.port", $opt{"port"});
}

# E V E N T   C L I E N T --------------------------------------------------

my $event_client = threads->new( \&event_process );
$event_client->detach;

# M A I N  L O O P ---------------------------------------------------------

while(1) { };

exit;

# E V E N T   C L I E N T ###################################################

sub event_process {

   my $sock;
   SOCKET: { 

     $log->print("Opening client connection to $opt{host}:$opt{port}");    
     my $sock = new IO::Socket::INET( PeerAddr => $opt{host},
                                   PeerPort => $opt{port},
                                   Proto    => "tcp" );

     unless ( $sock ) {
         my $error = "$@";
         chomp($error);
         $log->warn("Warning: $error");
         $log->warn("Warning: Trying to reopen socket connection...");
         sleep 5;
         redo SOCKET;
     }    
              
     my $message;
     $log->print("Socket open, listening...");
     my $flag = 1;    
     while( $flag ) {

        my $length;  
        my $bytes_read = read( $sock, $length, 4 );

        next unless defined $bytes_read;
   
        $log->debug("Recieved a packet from $opt{host}...");
        if ( $bytes_read > 0 ) {

           $log->debug( "Recieved $bytes_read bytes on $opt{port} from ".
	                 $sock->peerhost() );
          
           $length = unpack( "N", $length );
           if ( $length > 512000 ) {
               $log->error("Error: Message length is > 512000 characters");
               $log->error("Error: Message claims to be $length long");
               $log->warn("Warning: Discarding bogus message");
           } else {   
         
              $log->print("Message is $length characters");               
              $bytes_read = read( $sock, $message, $length); 
      
              $log->debug("Read $bytes_read characters from socket");
      
              # callback to handle incoming Events     
	      #print $message . "\n";
       
              my $object = new Astro::VO::VOEvent( XML => $message );
	 
	      my $response;
	      if ( $object->role() eq "iamalive" ) {
	         $log->debug("Echoing 'iamalive' packet..");
	         $response = $message;
              } else {
	         $log->debug("Responding with an 'ack' packet...");
	         $response =
                 "<?xml version='1.0' encoding='UTF-8'?>"."\n".
                 '<VOEvent role="ack" id="ivo://estar.ex/" version="1.1">'."\n".
                 ' <Who>'."\n".
                 '   <PublisherID>ivo://estar.ex</PublisherID>'."\n".
                 ' </Who>'."\n".
                 '</VOEvent>'."\n";
	      }
	 
	      my $bytes = pack( "N", length($response) ); 
              $log->debug("Sending " . length($response) . " bytes to socket");
              print $sock $bytes;
              $sock->flush();
              print $sock $response;
	      #print "$response\n";
              $sock->flush(); 
	      
	      if ( $object->role() eq "observation" || $object->role() eq "test" ) {

                my $id;
                eval { $id = $object->id( ); };
                if ( $@ ) {
   	           my $error = "$@";
   	           chomp( $error );
   	           $log->error( "Error: $error" );
   	           $log->error( "\$data = " . $message );
   	           next;
                } 
                $log->debug( "ID: $id" );
		   
                my $description;
                eval { $description = $object->description( ); };
                if ( $@ ) {
   	           my $error = "$@";
   	           chomp( $error );
   	           $log->error( "Error: $error" );
   	           $log->error( "\$data = " . $message );
   	           next;
                } 
                $log->debug( "Description: $description" );  
      
      
                # get $name
                my $name;
                $name = "eSTAR" if $id =~ "uk.org.estar";
                $name = "Caltech" if $id =~ "nvo.caltech";
                $name = "NOAO" if $id =~ "noao.edu";
                $name = "RAPTOR" if $id =~ "talons.lanl";
                $name = "PLANET" if $id =~ "planet";
                $name = "Robonet-1.0" if $id =~ "robonet-1.0";
                
                # build url
                my $idpath = $id;
                $idpath =~ s/#/\//;
                my @path = split( "/", $idpath );
                if ( $path[0] eq "ivo:" ) {
   	           splice @path, 0 , 1;
                }
                if ( $path[0] eq "" ) {
   	           splice @path, 0 , 1;
                }
                my $url = "http://www.estar.org.uk/voevent/$name";
                foreach my $i ( 0 ... $#path ) {
   	           $url = $url . "/$path[$i]"; 
                }
                $url = $url . ".xml";
                                 
                $description = 
                  '<![CDATA['.
                  'XML: <a href="'.$url.'">'.$id.'</a><br><br>'.$description .
                  '<br>'.
                  '<table><tr width="100%"><td><a href="http://www.estar.org.uk/"><img border="0" src="http://estar4.astro.ex.ac.uk/voevent/estar_logo.png"></a></td><td align="justify"><font size="-1"><em>The <a href="http://www.estar.org.uk/">eSTAR</a> project is a programme to build an intelligent robotic telescope network. It is a joint project between the Astrophysics Research Institute at Liverpool John Moores University and the Astrophysics Research Group of the School of Physics at the University of Exeter.</td></tr></table>'. 
                  ']]>';    
                   
                $description =~ s/ OGLE / <a href="http:\/\/www.estar.org.uk\/wiki\/index.php\/OGLE">OGLE<\/a> /g;  
                   
		my $ra = $object->ra();
		my $dec = $object->dec();
		if ( defined $ra && defined $dec ) {
		
  		   $log->print( "RA = $ra, Dec = $dec" );
                   my $long = $ra - 180;
                   $log->debug( "RA - 180 deg = $long" );

                   # Writing to voevent.kml file
                   my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
                   my $kml = File::Spec->catfile( $state_dir, "voevent.kml" );

                   # write the observation object to disk.
                   # -------------------------------------
   
                   if ( open ( KML, "$kml" )) {
                       
		      $log->warn( "Slurping from $kml" );
		      my @lines;
		      {
		         $/ = "\n";
		         @lines = <KML>;
	              }		 
		      close( KML );
		      
		      $log->debug("Updating content" );
		      my $string = 
		      '  <Placemark>'."\n".
		      '    <name>'.$id.'</name>'."\n".
		      '    <description>'.$description.'</description>'."\n".
		      '    <Point>'."\n".
		      '      <coordinates>'.$long.','.$dec.',0</coordinates>'."\n".
		      '    </Point>'."\n".
		      '  </Placemark>'."\n".
		      '  </Folder>'."\n";
		      
		      my $line = $#lines - 1;
		      $lines[$line] = $string;
		      
		      $log->warn( "Unlinking old file...");
		      unlink $kml;
		      
		      $log->warn( "Writing new KML file...");
		      open ( KML, ">$kml" );
		      foreach my $i ( 0 ... $#lines ) {
		         print KML $lines[$i];
		      }
		      close( KML );	  
		       
                   } else {
		      $log->warn( "Creating $kml" );
		      open ( KML, ">$kml" );
		      	                 
		      my $string = '<?xml version="1.0" encoding="UTF-8"?>'."\n".
		      '<kml xmlns="http://earth.google.com/kml/2.1">'."\n".
		      '  <Folder>'."\n".
		      '  <Placemark>'."\n".
		      '    <name>'.$id.'</name>'."\n".
		      '    <description>'.$description.'</description>'."\n".
		      '    <Point>'."\n".
		      '      <coordinates>'.$long.','.$dec.',0</coordinates>'."\n".
		      '    </Point>'."\n".
		      '  </Placemark>'."\n".
		      '  </Folder>'."\n".
		      '</kml>'."\n";
                      $log->debug("Writing new KML file");
		      print KML $string;
		      close ( KML );
                   }
		   
		   #eval { 
                   #   $log->print("Opening FTP connection to lion.drogon.net...");  
                   #   my $ftp = Net::FTP->new( "lion.drogon.net", Debug => 1 );
                   #   $log->debug("Going into PASV mode...");
                   #   $log->debug("Logging into estar account...");  
                   #   $ftp->login( "estar", "tibileot" );
                   #   $ftp->cwd( "www.estar.org.uk/docs/voevent/" );
                   #   $log->debug("Transfering file $kml");  
                   #   $ftp->put( $kml, "voevent.kml" );
                   #   $ftp->quit();
	           #   $log->print("Closed FTP connection...");
                   #};
                   
                   eval {
                      $log->debug( "Copying file to /var/www/html/voevent/" ); 
                      copy($kml, "/var/www/html/voevent/") or die "File cannot be copied.";
                   };
                   
                   if ( $@ ) {
                     my $error = "$@";
                     chomp $error;
                     $log->error( "Error: $error" );
                   }	   

	        } else {
		   $log->warn( "Warning: Unable to understand the RA&Dec" );
		   $log->warn( $message );
		}
		   
              }		
	      $log->print("Done.");
           }
                      
        } elsif ( $bytes_read == 0 && $! != EWOULDBLOCK ) {
          $log->warn( "Warning: Recieved an empty packet on $opt{port} from ".
	              $sock->peerhost() );   
          $log->warn( "Warning: Closing socket connection..." );      
          $flag = undef;
        } elsif ( $bytes_read == 0 ) {
          $log->warn( "Warning: Recieved an empty packet on $opt{port} from ".
	              $sock->peerhost() );   
          $log->warn( "Warning:Closing socket connection..." );      
          $flag = undef;   
        }
   
        unless ( $sock->connected() ) {
         $log->warn( "Warning: Not connected, socket closed...");
         $flag = undef;
        } 
	   
     }  
  
     $log->warn("Warning: Trying to reopen socket connection...");
     redo SOCKET;
   };  

}
