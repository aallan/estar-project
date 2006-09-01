#!/usr/bin/perl

use Config::User;
use File::Spec;
use Carp;
use Data::Dumper;
use Socket;
use Net::Domain qw(hostname hostdomain);

use POSIX qw/:sys_wait_h/;
use Errno qw/EAGAIN/;

use XMLRPC::Lite;
use XMLRPC::Transport::HTTP;

# R P C -------------------------------------------------------------------

# Grab an RPC endpoint for the ACR
my $file = File::Spec->catfile( Config::User->Home(), ".plastic" );
croak( "Unable to open file $file" ) unless open(PREFIX, "<$file" );

my @prefix = <PREFIX>;
close( PREFIX );
chomp( $prefix );

my $endpoint;
foreach my $i ( 0 ... $#prefix ) {
  if ( $prefix[$i] =~ "plastic.xmlrpc.url" ) {
     my @line = split "=", $prefix[$i];
     chomp($line[1]);
     $endpoint = $line[1];
     $endpoint =~ s/\\//g;
  }    
}
print "Plastic Hub Endpoint: $endpoint\n";

my $rpc = new XMLRPC::Lite();
$rpc->proxy($endpoint);

# M A I N  L O O P ---------------------------------------------------------

print "Sleeping for 5 seconds\n\n";
sleep 5;
# Sleeping for 5 seconds

my $ra = 20.0;
my $dec = 75.0;
my @array;
push @array, $ra;
push @array, $dec;

print "Sending ivo://votech.org/sky/pointAtCoords message to Hub...\n";
eval{ $status = $rpc->call( 'plastic.hub.request', 
          "http://". $ip.":". $port."/",
           "ivo://votech.org/sky/pointAtCoords",
           \@array ); };

if( $@ ) {
   my $error = "$@";
   croak( "Error: $error" );
}   
unless( $status->fault() ) {
   my %hash = %{$status->result()};
   if ( scalar %hash ) {
     foreach my $key ( sort keys %hash ) {
       print "$key => $hash{$key}\n";
     }
   } else {
      $log->error(
         "Error: There were no registered applications"); 
   }  
} else {
   croak( "Error: ". $status->faultstring );
}              


exit;

