#!/software/perl-5.8.6/bin/perl -w

use strict;
use warnings;

=head1 NAME

gcn_server - A TCP server which deals with packets from the GCN

=head1 SYNOPSIS

  make_observation

=head1 DESCRIPTION

A simple server which sits and listens for packets from the GCN, and
then hands them on to the user agent if they look important.

=head1 AUTHORS

Alasdair Allan (aa@astro.ex.ac.uk)

=head1 REVISION

$Id: gcn_server.pl,v 1.3 2005/02/04 14:28:28 aa Exp $

=head1 COPYRIGHT

Copyright (C) 2005 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut  

use vars qw / $VERSION $log $process %opt /;

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.3 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR Server Software:\n";
      print "GCN Server $VERSION; PERL Version: $]\n";
      exit;
    }
  }
}

# L O A D I N G -------------------------------------------------------------
  
# eSTAR modules
use lib $ENV{ESTAR_PERL5LIB};
use eSTAR::Logging;
use eSTAR::Process;
use eSTAR::Constants qw(:status); 
use eSTAR::Error qw /:try/;

# GCN modules
use GCN::Constants qw(:packet_types);

# General modules
use IO::Socket;
use Errno qw(EWOULDBLOCK EINPROGRESS);
use Net::Domain qw(hostname hostdomain);
use Time::localtime;
use Getopt::Long;
use Data::Dumper;


# tag name of the current process, this identifies where log and 
# status files for this process will be stored.
$process = new eSTAR::Process( "gcn_server" );  

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
$log->header("Starting GCN Server: Version $VERSION");

# C O M M A N D   L I N E   A R G U E M E N T S -----------------------------

# grab options from command line
my $status = GetOptions( "host=s"     => \$opt{"host"},
                         "port=s"     => \$opt{"port"} );

# default hostname
unless ( defined $opt{"host"} ) {
   # localhost.localdoamin
   my $ip = inet_ntoa(scalar(gethostbyname(hostname())));
   $log->debug("This machine as an IP address of $ip");
   $opt{"host"} = $ip;
}

# default port
unless( defined $opt{"port"} ) {
   # default port for the GCN server
   $opt{"port"} = 5184;   
}

# M A I N   C O D E ----------------------------------------------------------
  
my $sock = new IO::Socket::INET( 
                  LocalHost => $opt{"host"},
                  LocalPort => $opt{"port"},
                  Proto     => 'tcp',
                  Listen    => 1,
                  Reuse     => 1,
                  Timeout   => 300,
                  Type      => SOCK_STREAM ); 
                    
die "Could not create socket: $!\n" unless $sock;
#$sock->blocking(0);

$log->debug("Starting server on $opt{host}:$opt{port}...\n");

# wait until socket opens
while ( my $listen = $sock->accept() ) {
    
    $listen->blocking(0);
        
    my $status = 1;    
    while( $status ) {
    
       my $length = 160; # GCN packets are 160 bytes long
       my $buffer;  
       my $bytes_read = sysread( $listen, $buffer, $length);
     
       next unless defined $bytes_read;
       if ( $bytes_read > 0 ) {
 
         $log->debug( "\nRecieved $bytes_read bytes on $opt{port} from " . 
                      $listen->peerhost() );    
                      
          my @message = unpack( "N40", $buffer );
          if ( $message[0] == TYPE_IM_ALIVE ) {
             $log->print("Recieved a TYPE_IM_ALIVE packet at " . ctime() ); 
          } else {
             $log->warn("Recieved a packet of type $message[0] at " . ctime() );
          }

          # echo back the packet so GCN can monitor:
          if( $message[0] != TYPE_KILL_SOCKET ) {
             $log->debug( "Echoing $bytes_read bytes to " . 
                          $listen->peerhost() );
             $listen->flush();
             print $listen $buffer;
             $listen->flush();
          } else {
             $log->print("Recieved a TYPE_KILL_SOCKET packet at " . ctime() );
             $log->warn("Warning: Killing connection...");
             $status = undef;
          }    
       } elsif ( $bytes_read == 0 && $! != EWOULDBLOCK ) {
          $log->warn("\nWarning: Recieved a 0 length packet");
          $listen->flush();
          print $listen $buffer;
          $log->debug( "Echoing $bytes_read bytes to " . $listen->peerhost() );
          $listen->flush();
                          
          $status = undef;
       }
       
       unless ( $listen->connected() ) {
          $log->warn("\nWarning: Not connected, closing socket...");
          $status = undef;
       }    
    
    }   
    $log->warn("Warning: Closing socket connection to client");
    close ($listen);
    
} 
  
  
$log->print("Exiting...");    
exit; 
