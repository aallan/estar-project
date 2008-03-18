#!/software/perl-5.8.6/bin/perl

=head1 NAME

time_server.pl - encapsulated time server for a virtual telescope network

=head1 SYNOPSIS

  perl ${ESTAR_BIN}/time_server.pl

=head1 DESCRIPTION

A time server to provide a consistent 'network time' for a virtual telescope
network. This allows the virtual network to be run in an accelerated time-frame.

=head1 AUTHORS

Eric Saunders (saunders@astro.ex.ac.uk)

=head1 REVISION

$Id: time_server.pl,v 1.4 2008/03/18 16:55:19 saunders Exp $

=head1 COPYRIGHT

Copyright (C) 2006 Particle Physics and Astronomy Research Council.
All Rights Reserved.

=cut

use strict;
use warnings;
use vars qw ( $VERSION $log );

# H A N D L E  V E R S I O N ----------------------------------------------- 

#  Version number - do this before anything else so that we dont have to 
#  wait for all the modules to load - very quick
BEGIN {
  $VERSION = sprintf "%d.%d", q$Revision: 1.4 $ =~ /(\d+)\.(\d+)/;
 
  #  Check for version number request - do this before real options handling
  foreach (@ARGV) {
    if (/^-vers/) {
      print "\neSTAR User Agent Software:\n";
      print "Network Time Server $VERSION; Perl Version: $]\n";
      exit;
    }
  }
}

use threads;
use threads::shared;


# eSTAR modules...
use lib $ENV{ESTAR_PERL5LIB};
use eSTAR::Constants qw( :status );
use eSTAR::ADP::Util qw( init_logging str2datetime );

# Other modules...
use IO::Socket::INET;
use DateTime;
use DateTime::Format::ISO8601;

my $acc_factor = shift || 1;
my $sim_start_time_str = shift;

my $sim_start_time = $sim_start_time_str ? str2datetime($sim_start_time_str) 
                                         : DateTime->now;


# Set up logging...
my $log_verbosity = ESTAR__DEBUG;
$log = init_logging('Network Time Server', $VERSION, $log_verbosity);

# Initialise the TCP/IP socket...
my $tcp_port = 6667;
my $tcp_daemon = new IO::Socket::INET( 
                                        LocalPort => $tcp_port,
                                        Proto     => 'tcp',
                                        Listen    => 5,
                                        Reuse     => 1,
                                      );

# Instantiate the time server...
my $get_accelerated_time = new_time_server($acc_factor, $sim_start_time);


# Returns the current time to the requester...
my $return_current_time = sub {
   my $incoming = shift;
   my $thread_name = 'Incoming Message Thread';

   # Grab peerhost and peerport and send reply...
   my $peer_host = $incoming->peerhost;
   my $peer_port = $incoming->peerport;
   $log->thread2( $thread_name,  "Time requested by $peer_host:$peer_port" ); 

   # Get the simulation time...
   my $time_now = $get_accelerated_time->();


#   use Data::Dumper;print Dumper($time_now);
   print $incoming $time_now;
   $incoming->shutdown(1);

   $log->thread2( $thread_name,  "DateTime info sent at " . $time_now );

   return;
};


# Thread-on-accept...
my $thread_name = 'Time Server';
while ( my $incoming = $tcp_daemon->accept ) {
   $log->thread( $thread_name,  "Reading from TCP/IP socket... " );

   # Thread on accept...
   $log->thread( $thread_name,
                 "Spawning sub-thread to handle incoming message..." );

   my $time_thread = threads->create( $return_current_time, $incoming );
   $time_thread->detach;                        
}


sub new_time_server {
   my $acc_factor     = shift;
   my $sim_start_time = shift;
   my $start_time = DateTime->now;

   return sub {

      # Find the real time that has passed since the server instantiated...
      my $current_real_time = DateTime->now;      
      my $real_time_elapsed = $current_real_time - $start_time;      
      
      # Calculate the sim time that has passed, and the current sim time...
      my $sim_time_elapsed = $real_time_elapsed->multiply($acc_factor);
      my $current_sim_time = $sim_start_time + $sim_time_elapsed;

      # A load of useful info to print... (debug)
      my %deltas_of = $real_time_elapsed->deltas;
      my %sim_deltas_of = $sim_time_elapsed->deltas;

      print "Start time = $start_time\n";
      print "Current real time = $current_real_time\n";
      print "Elapsed real time = \n";
      foreach my $interval (keys %deltas_of) {
         print "$interval => $deltas_of{$interval}\n";
      }
      print "\nElapsed sim time = \n";
      foreach my $interval (keys %sim_deltas_of) {
         print "$interval => $sim_deltas_of{$interval}\n";
      }
      print "Current sim time = $current_sim_time\n";
      
      return $current_sim_time;
   };
}
