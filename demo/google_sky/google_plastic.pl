#!/usr/bin/perl

use strict;

use Config::User;
use File::Spec;
use Carp;
use Data::Dumper;
use Net::Domain qw(hostname hostdomain);

use POSIX qw/:sys_wait_h/;
use Errno qw/EAGAIN/;

use XMLRPC::Lite;
use XMLRPC::Transport::HTTP;

use HTTP::Daemon;
use HTTP::Status;
  
use vars qw / $VERSION $host $port $http $kml $rpc /;
$VERSION = sprintf "%d.%d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/;

#$ip = inet_ntoa(scalar(gethostbyname(hostname())));
$host = 'localhost';
$port = '8000';
$http = '8001';
$kml = File::Spec->catfile( Config::User->Home(), ".plastic.kml" );

print "Google Sky Plastic v$VERSION\n\n";

print "Unlinking $kml if present...\n";
unlink( $kml );

# X M L - R P C  D A E M O N -----------------------------------------------------

print "Forking...\n";

my ( $pid, $dead );
$dead = waitpid ($pid, &WNOHANG);
#  $dead = $pid when the process dies
#  $dead = -1 if the process doesn't exist
#  $dead = 0 if the process isn't dead yet
if ( $dead != 0 ) {
    FORK: {
        if ($pid = fork) {
             print "Continuing... pid = $pid\n";
        } elsif ( defined $pid && $pid == 0 ) {
              print "Forking daemon process... pid = $pid\n";
              my $daemon;
              eval { $daemon = XMLRPC::Transport::HTTP::Daemon
               -> new (LocalPort => $port, LocalHost => $host )
               -> dispatch_to( 'perform' );  };
              if ( $@ ) {
                 my $error = "$@";
                 croak( "Error: $error" );
              }             
     
              my $url = $daemon->url();   
              print "Starting XMLRPC server at $url\n";

              eval { $daemon->handle; };  
              if ( $@ ) {
                my $error = "$@";
                croak( "Error: $error" );
              }  
  
          } elsif ($! == EAGAIN ) {
              # This is a supposedly recoverable fork error
              print "Error: recoverable fork error\n";
              sleep 5;
              redo FORK;
       } else {
              # Fall over and die screaming
              croak("Unable to fork(), this is fairly odd.");
       }
    }
}

# R E G I S T E R   WI T H   H U B  ##########################################

print "Waiting for server to start...\n";
sleep(5);

my $status = Plastic::register( $host, $port );
if ( $status != 1 ) {
   croak( "Unable to register with Hub. Status is $status" );
} else {
   print "Entering main loop...\n";
}   

# H T T P   D A E M O N ------------------------------------------------------

print "Starting HTTP Daemon...\n";
my $httpd;
eval { $httpd = new HTTP::Daemon( LocalAddr => $host,
                                  LocalPort => $http ) };
if ( $@ ) {
   my $error = "$@";
   croak( "Error: $error" );
}	       

print "Daemon started on ". $httpd->url() . "\n";
while (my $connection = $httpd->accept) {
   while (my $request = $connection->get_request() ) {
      if ($request->method() eq 'GET' and $request->url()->path() eq "/getPoints") {
         print "Connection from Google Sky...\n";
	 print "Sending file = $kml\n";
         $connection->send_file_response( $kml );
	 print "Done.\n";
      } elsif ($request->method() eq 'GET' and $request->url()->path() eq "/sendPoint") {
         print "Connection from Google Sky...\n";
	 my $url = $request->url();
         print "Got $url\n";
	 my @fragments = split /\?/, $url;
	 my ($ra, $dec ) = split /&/, $fragments[1];
	 $ra =~ s/ra=//;
	 $dec =~ s/dec=//;
	 print "RA = $ra, Dec = $dec\n";
         my $status;
	 my @array;
	 push @array, $ra;
	 push @array, $dec;
         eval{ $status = $main::rpc->call( 'plastic.hub.request', 
         	   "http://".$host.":". $port ."/",
	 	    "ivo://votech.org/sky/pointAtCoords",
	 	    \@array ); };

         if( $@ ) {
            my $error = "$@";
            croak( "Error: $error" );
         }   
         unless( $status->fault() ) {
            my %hash = %{$status->result()};
	    if ( scalar %hash ) {
	      print "Submitted event to hub...\n";
	      #print Dumper( %hash );
	      foreach my $key ( sort keys %hash ) {
	 	print "$key => $hash{$key}\n";
	      }
	    } else {
	       print "Error: There were no registered applications\n"; 
	    }  
         } else {
            croak( "Error: ". $status->faultstring );
         }		       
	 print "Sending 200 (OK)\n";
         $connection->send_status_line( );
	 print "Done.\n";
      } else {
         print "Connection attempted, but not to /getPoints\n";
         print "Sending 403 (RC_FORBIDDEN)\n";	 
         $connection->send_error(RC_FORBIDDEN);
	 print "Done.\n";
      }
   }
   $connection->close();
   undef($connection);
}
  
exit;

# D A E M O N   C A L L B A C K S ##########################################

sub perform {
  Plastic::perform( @_ );
}  

#  P L A S T I C   ########################################################

package Plastic;

use Data::Dumper;

my $id;  # Plastic ID

sub perform {
  my @args = @_;

  print "Passing ". $args[2] ." to perform( )\n";
  #print Dumper( @args );
  if ($args[2] eq 'ivo://votech.org/test/echo' ) {
     return $args[3];
  }
  if ($args[2] eq 'ivo://votech.org/info/getName' ) {
     return "Google Sky";
  }
  if ($args[2] eq 'ivo://votech.org/info/getIvorn' ) {
     return "ivo://uk.org.estar/google.sky/";
  }   
  if ($args[2] eq 'ivo://votech.org/info/getVersion' ) {
     return "0.4";
  }
  if ($args[2] eq 'ivo://votech.org/info/getDescription' ) {
     return "A Plastic client which will pass catalogues to Google Sky via a KML file.";
  }
  if ($args[2] eq 'ivo://votech.org/info/getIconURL' ) {
     return "http://www.google.com/intl/en_ALL/images/logo.gif";
  }   
  if ($args[2] eq 'ivo://votech.org/hub/event/ApplicationRegistered' ) {
     return 1;
  }   
  if ($args[2] eq 'ivo://votech.org/hub/event/ApplicationUnregistered' ) {
     return 1;
  }   
  if ($args[2] eq 'ivo://votech.org/hub/event/HubStopping' ) {
     print "Warning: Hub Stopping Message\n";
     print "Shutting down application...\n";
     kill 9, $pid;
  }   
  if ($args[2] eq 'ivo://votech.org/hub/Exception' ) {
     print "Warning: Hub Exception Message\n";
     print "Warning: $args[3]\n";
     return 1;
  }   
  
  if($args[2] eq 'ivo://votech.org/sky/pointAtCoords' ) {
     my $ra = ${$args[3]}[0];
     my $dec = ${$args[3]}[1];
     print "Recieved co-ordinates ($ra, $dec)\n";
     my $long = $ra - 180;
     print "RA - 180 deg = $long\n";
 
     # write to disk.
     # --------------
     if ( open ( KML, "$main::kml" )) {
     	 
     	print "Slurping from $main::kml\n";
     	my @lines;
     	{
     	   $/ = "\n";
     	   @lines = <KML>;
     	}	   
     	close( KML );
     	
     	print "Updating content...\n";
     	my $string = 
     	'  <Placemark>'."\n".
     	'    <name>('.$ra.', '.$dec.')</name>'."\n".
     	'    <description><![CDATA[Co-ordinates sent via Plastic.<br><a href="http://'.$main::host.':'.$main::http.'/sendPoint?ra='.$ra.'&dec='.$dec.'">Send this point back to the Plastic hub</a>.]]></description>'."\n".
     	'    <Point>'."\n".
     	'      <coordinates>'.$long.','.$dec.',0</coordinates>'."\n".
     	'    </Point>'."\n".
     	'  </Placemark>'."\n".
     	'  </Folder>'."\n";
     	
     	my $line = $#lines - 1;
     	$lines[$line] = $string;
     	
     	print "Unlinking old file...\n";
     	unlink $main::kml;
     	
     	print "Writing new KML file...\n";
     	open ( KML, ">$main::kml" );
     	foreach my $i ( 0 ... $#lines ) {
     	   print KML $lines[$i];
     	}
     	close( KML );	    
	
	print "Done.\n";
     	 
     } else {
     	print "Creating $main::kml\n";
     	open ( KML, ">$main::kml" );
     			   
     	my $string = '<?xml version="1.0" encoding="UTF-8"?>'."\n".
     	'<kml xmlns="http://earth.google.com/kml/2.1">'."\n".
     	'  <Folder>'."\n".
     	'  <Placemark>'."\n".
     	'    <name>('.$ra.', '.$dec.')</name>'."\n".
     	'    <description><![CDATA[Co-ordinates sent via Plastic.<br><a href="http://'.$main::host.':'.$main::http.'/sendPoint?ra='.$ra.'&dec='.$dec.'">Send this point back to the Plastic hub</a>.]]></description>'."\n".
     	'    <Point>'."\n".
     	'      <coordinates>'.$long.','.$dec.',0</coordinates>'."\n".
     	'    </Point>'."\n".
     	'  </Placemark>'."\n".
     	'  </Folder>'."\n".
     	'</kml>'."\n";
     	print "Writing new KML file...\n";
     	print KML $string;
     	close ( KML );
	
	print "Done.\n";
     } 
     
     my $return = XMLRPC::Data->type( boolean => 'true' );    
     return $return;
  }  

}

sub register {
   my $host = shift;
   my $port = shift;
      
   REGISTER: {
   
   print "In Plastic::register()\n";
   print "Attempting to register with Plastic Hub...\n";

   # R P C -------------------------------------------------------------------

   my $endpoint;
   while ( !defined $endpoint ) {
      
      # Grab an RPC endpoint for the ACR
      my $file = File::Spec->catfile( Config::User->Home(), ".plastic" );
      unless ( open(PREFIX, "<$file" ) )  {
         print "File $file not found\n";
	 print "Re-trying in 5 seconds...\n";
	 sleep 5;
	 next;
      }	 

      my @prefix = <PREFIX>;
      close( PREFIX );

      foreach my $i ( 0 ... $#prefix ) {
        if ( $prefix[$i] =~ "plastic.xmlrpc.url" ) {
           my @line = split "=", $prefix[$i];
           chomp($line[1]);
           $endpoint = $line[1];
           $endpoint =~ s/\\//g;
        }    
      }
      print "Plastic Hub Endpoint: $endpoint\n";
   }
   
   print "Building XMLRPC::Lite object\n";
   $main::rpc = new XMLRPC::Lite();
   $main::rpc->proxy($endpoint);

   # R E G I S T E R ----------------------------------------------------------
   
   my @list;
   $list[0] = 'ivo://votech.org/test/echo';
   $list[1] = 'ivo://votech.org/info/getName';
   $list[2] = 'ivo://votech.org/info/getIvorn';
   $list[3] = 'ivo://votech.org/info/getVersion';
   $list[4] = 'ivo://votech.org/info/getDescription';
   $list[5] = 'ivo://votech.org/info/getIconURL';
   $list[6] = 'ivo://votech.org/hub/event/ApplicationRegistered';
   $list[7] = 'ivo://votech.org/hub/event/ApplicationUnregistered';
   $list[8] = 'ivo://votech.org/hub/event/HubStopping';
   $list[9] = 'ivo://votech.org/hub/Exception';
   $list[10] = 'ivo://votech.org/sky/pointAtCoords';

   print "Calling plastic.hub.registerXMLRPC for $host:$port\n";
   my $return;
   eval{ $return = $main::rpc->call( 'plastic.hub.registerXMLRPC', 
                     'Google Sky', \@list, "http://$host:$port/" ); };

   if( $@ ) {
      croak( "Error: $@" );
   }   

   unless( $return->fault() ) {
      $id = $return->result();
      print "Got Plastic ID of $id\n";
   } else {
      print "Warning: " . $return->faultstring . "\n";
      print "Warning: Sleeping for 5 seconds...\n";
      sleep 5;
      redo REGISTER;
   }
   
   } # end of REGISTER block
   
   return 1;
}   
