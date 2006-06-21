#!/software/perl-5.8.6/bin/perl -w

use strict;
use warnings;

=head1 NAME

gcn_server - Converts packets from GCN binary to VOEvent XML

=head1 SYNOPSIS

  gcn_server -port port_number

=head1 DESCRIPTION

A simple server which sits and listens for packets from the GCN, and
then converts them to VOEvent XML format.

=head1 AUTHORS

Alasdair Allan (aa@astro.ex.ac.uk)

=head1 REVISION

$Id: gcn_vo_server.pl,v 1.2 2006/06/21 20:33:13 aa Exp $

=head1 COPYRIGHT

Copyright (C) 2005 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut  

use vars qw / $VERSION %opt /;

BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/;
}

# L O A D I N G -------------------------------------------------------------

# Threading code (ithreads)
use threads;
use threads::shared;
use lib $ENV{GCN_PERL5LIB};

# GCN modules
use Astro::GCN::Parse;
use Astro::GCN::Constants qw(:packet_types);

# VO modules
use Astro::VO::VOEvent;

# General modules
use IO::Socket;
use Errno qw(EWOULDBLOCK EINPROGRESS);
use Net::Domain qw(hostname hostdomain);
use Time::localtime;
use Getopt::Long;
use Data::Dumper;

# Get date and time
my $date = scalar(localtime);

# S T A R T   U P -----------------------------------------------------------

print "eSTAR GCN Software\n";
print "------------------\n";
print "GCN XML Server $VERSION\n";
print "PERL Version: $]\n\n";

# C O M M A N D   L I N E   A R G U E M E N T S -----------------------------

my $port;   
my $options_status = GetOptions( "port=s" => \$opt{"port"} );  

# M A I N   O P T I O N S   H A N D L I N G ---------------------------------

# grab current IP address
my $ip = inet_ntoa(scalar(gethostbyname(hostname())));
print "This machine as an IP address of $ip\n";

$opt{"host"} = $ip;
unless ( defined $opt{"port"} ) { 
   print "Warning: Using default port number\n";
   $opt{"port"} = 5286;
}
print "Using port $opt{port} for TCP/IP server...\n";

$opt{"timeout"} = 5;
$opt{"proxy"} = "NONE";


# T C P / I P   S E R V E R   C O D E --------------------------------------
 
# TCP/IP SERVER CALLBACK
# ----------------------

# Conenction callback for the TCP/IP socket, this grabs 
# the incoming message from the GCN and handles it before
# passing filtered observing requests to the user_agent.pl

my $tcp_callback = sub { 
   my $message = shift; 

    
  if ( $message->type() == TYPE_IM_ALIVE ) {
      print "Recieved a TYPE_IM_ALIVE packet at " . ctime() ."\n"; 
               
  } elsif ( $message->type() >= 60 && $message->type() <= 83 ) {
      print "Recieved a SWIFT (type " .
             $message->type() . ") packet at " . ctime() ."\n"; 
  } else {
     print "Recieved a " . $message->type() . " packet at " . ctime() ."\n"; 
  
  }
  
  
  if ( $message->is_swift() ) {
      
      # The following types don't have an RA or Dec attached
      if ( $message->type() == 60 || $message->type == 62 ||
           ( $message->type() >= 74 && $message->type <= 75 ) ) {
           return undef;
      }   

      my $id = "ivo:/uk.org.estar/gcn.gsfc.nasa#swift/trigger_" . 
               $message->trigger_num() . "/obs_" .
               $message->obs_num() . "/" . $message->serial_number();
  
      my $what_name = "bat_ipeak";
      my $what_ucd = "phot.count";
      my $what_value = $message->bat_ipeak();
      my $what_units = "counts"; 
  
      my $object = new Astro::VO::VOEvent( );
   
      my $document = $object->build( 
        Type => $message->type(), 
        Role => 'alert',
        ID   => $id,
        Who  => { Publisher => 'ivo://gcn.gsfc.nasa/',
                  Date => ctime(),
                  Contact => { Name => 'Scott Barthelmy',
                                   Institution => 'GSFC/NASA',
                                   Email => 'scott.barthelmy@gsfc.nasa.gov' } },
        WhereWhen => { RA => $message->ra_degrees(), 
                       Dec => $message->dec_degrees() , 
                       Error => $message->burst_error_degrees(),
                       Time => $message->tjd() },  
        How => { Name => 'SWIFT' },
        What => [ { Name  => $what_name,
                    UCD   => $what_ucd,
                    Value => $what_value,
                    Units => $what_units } ]  );   
  
        print "------ VOEVENT DOCUMENT ------\n\n";
        print "$document";
        print "\n\n------ VOEVENT DOCUMENT ------\n\n";
   
   } else {
      return undef;
   }   
   
};

   
# TCP/IP SERVER
# -------------

# daemon process
my $sock;

# the thread in which we run the server process
my $tcpip_thread;

# anonymous subroutine which starts a SOAP server which will accept
# incoming SOAP requests and route them to the appropriate module
my $tcpip_server = sub {
   my $thread_name = "TCP/IP Thread"; 
  
   print "Starting server on $opt{host}:$opt{port} " .
         " (\$tid = ".threads->tid().")\n";  
   
   my $sock = new IO::Socket::INET( 
                  LocalHost => $opt{"host"},
                  LocalPort => $opt{"port"},
                  Proto     => 'tcp',
                  Listen    => 1,
                  Reuse     => 1,
                  Timeout   => 300,
                  Type      => SOCK_STREAM ); 
   
   unless ( $sock ) {
      # If we restart the node agent process quickly after a crash the port 
      # will still be blocked by the operating system and we won't be able 
      # to start the daemon. Other than the port being in use I can't see
      # why we're going to end up here.
      my $error = "$@";
      chomp($error);
      return "$error";
   };                    

   # wait until socket opens
   print "Reading unbuffered from TCP/IP socket... \n";
   while ( my $listen = $sock->accept() ) {
    
      $listen->blocking(0);
        
       my $status = 1;    
       while( $status ) {
    
          my $length = 160; # GCN packets are 160 bytes long
          my $buffer;  
          my $bytes_read = sysread( $listen, $buffer, $length);
     
          next unless defined $bytes_read;
          
          print "\nRecieved a packet...\n";
          if ( $bytes_read > 0 ) {
 
            print "Recieved $bytes_read bytes on $opt{port} from " . 
                         $listen->peerhost() . "\n";    
                      
             
             my $message = new Astro::GCN::Parse( Packet => $buffer );
             if ( $message->type() == TYPE_KILL_SOCKET ) {
                print "Recieved a TYPE_KILL_SOCKET packet at " . ctime() ."\n";
                print "Warning: Killing connection...\n";
                $status = undef;
             } 
             
             print "Echoing $bytes_read bytes to " . $listen->peerhost() ."\n";
             $listen->flush();
             print $listen $buffer;
             $listen->flush();
             
             # callback to handle incoming RTML     
             print "Detaching thread...\n";
             my $callback_thread =  threads->create ( $tcp_callback, $message );
             $callback_thread->detach(); 
                             
          } elsif ( $bytes_read == 0 && $! != EWOULDBLOCK ) {
             print "Recieved an empty packet on $opt{port} from " . 
                         $listen->peerhost() . "\n";   
             $listen->flush();
             print $listen $buffer;
             print "Echoing empty packet to " . $listen->peerhost() . "\n";
             $listen->flush();
             print "Closing socket connection...\n";      
             $status = undef;
          }
       
          unless ( $listen->connected() ) {
             print "\nWarning: Not connected, socket closed...\n";
             $status = undef;
          }    
    
       }   
       #close ($listen);
    
   } 
   
   return $@;

};  

# M A I N   L O O P ---------------------------------------------------------

my $exit_code;
while ( !$exit_code ) {

   # Spawn the inital TCP/IP server thread
   print "Spawning TCP/IP Server thread...\n";
   $tcpip_thread = threads->create( $tcpip_server );
  
   my $thread_exit_code = $tcpip_thread->join() if defined $tcpip_thread;
   print "Warning: Server exiting...\n";

   # respawn on timeout
   if ( $thread_exit_code eq "accept: timeout" ) {
      print "Warning: The socket has timed out waiting for connection\n";
      #print "Warning: Respawing server...\n";
      
   } else { 
      $exit_code = 1;
      print "Error: $thread_exit_code\n";
   }  
}

print "Exiting...\n\n";    
exit; 
