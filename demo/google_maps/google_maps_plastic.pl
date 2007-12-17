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
  
use vars qw / $VERSION $host $port $http $html $key $counter $rpc /;
$VERSION = sprintf "%d.%d", q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/;

#$ip = inet_ntoa(scalar(gethostbyname(hostname())));
$host = 'localhost';
$port = '8000';
$http = '8001';
$html = File::Spec->catfile( Config::User->Home(), ".plastic.html" );
$key = 
  'ABQIAAAAE-fH9yAlvJ5m2wOajR_KXRRUgtyaeRWcbA6tCuT6LqkYsW1vRxQqdKdonJtbO3KydYRLRVo93DM7Xg';
$counter = 1;

print "Google Maps for Sky Plastic v$VERSION\n\n";

print "Unlinking $html if present...\n";
unlink( $html );

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
         print "Connection to webserver, sending Maps page...\n";
	 print "Sending file = $html\n";
         $connection->send_file_response( $html );
	 print "Done.\n";
      } elsif ($request->method() eq 'GET' and $request->url()->path() eq "/sendPoint") {
         print "Connection from Google Maps link...\n";
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
     return "A Plastic client which will plot points on a Google Map for Sky via Plastic.";
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
     #my $long = - $ra + 180;
     #print "RA - 180 deg = $long\n";
 
     # write to disk.
     # --------------
     if ( open ( HTML, "$main::html" )) {
     	 
     	print "Slurping from $main::html\n";
     	my @lines;
     	{
     	   $/ = "\n";
     	   @lines = <HTML>;
     	}	   
     	close( HTML );
     	
     	print "Updating content...\n";
     	my $string = 
	  '	   var point'.$main::counter.' = new RADec( '.$ra.','.$dec.');'."\n".
          '	   var marker = createMarker(point'.$main::counter.','.
	  ' '."'".'Co-ordinates sent'.
	  ' via Plastic.<br><a href="http://'.$main::host.':'.
	  $main::http.'/sendPoint?ra='.$ra.'&dec='.$dec.
	  '">Send this point back to the Plastic hub</a>.'."'".' );'."\n".
          '	   map.addOverlay(marker);'."\n".
	  "\n";
     	
     	my $line = $#lines - 9;
     	$lines[$line] = $string;
     	
     	print "Unlinking old file...\n";
     	unlink $main::html;
     	
     	print "Writing new HTML file...\n";
     	open ( HTML, ">$main::html" );
     	foreach my $i ( 0 ... $#lines ) {
     	   print HTML $lines[$i];
	   #print $lines[$i];
     	}
     	close( HTML );	    
	
     	print "Incrementing counter\n";
        $main::counter = $main::counter + 1;
		
	print "Done.\n";
     	 
     } else {
     	print "Creating $main::html\n";
     	open ( HTML, ">$main::html" );
     			   
     	my $string = 
	     '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"'."\n".
             ' "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">'."\n".
             '<html xmlns="http://www.w3.org/1999/xhtml">'."\n".
             '<head>'."\n".
             '<meta http-equiv="content-type" content="text/html;charset=utf-8"/>'."\n".
             '<title>Google Maps for Sky</title>'."\n".
             '<script src="http://maps.google.com/maps?file=api&amp;v=2.95&amp;'."\n".
	     'key='.$main::key.'" type="text/javascript"></script>'."\n".
             '<script type="text/javascript">'."\n".
             "\n".
             '//<![CDATA['."\n".
             "\n".
             '    RADec = function(ra, dec) {'."\n".
             '      this.ra  = ra;'."\n".
             '      this.dec = dec;'."\n".
             '      GLatLng.call(this, dec, -ra + 180);'."\n".
             '    };'."\n".
             '    derive(RADec, GLatLng);'."\n".
             "\n".
             '    function createMarker(point,html) {'."\n".
             '      var marker = new GMarker(point);'."\n".
             '     GEvent.addListener(marker, "click", function() {'."\n".
             '        marker.openInfoWindowHtml(html);'."\n".
             '      });'."\n".
             '      return marker;'."\n".
             '    } '."\n".
             "\n".
             '    function load() {'."\n".
             '      if (GBrowserIsCompatible()) {'."\n".
             '        var map = new GMap2(document.getElementById("map"), {'."\n".
             '        mapTypes : G_SKY_MAP_TYPES'."\n".
             '        });'."\n".
	     "\n".
             '        map.setCenter(new GLatLng(0,90),1);'."\n".
             '        map.addControl(new GMapTypeControl());'."\n".
             '        map.addControl(new GLargeMapControl());'."\n".
	     "\n".
	     '        var point'.$main::counter.' = new RADec( '.$ra.','.$dec.');'."\n".
             '	   var marker = createMarker(point'.$main::counter.','.
	     ' '."'".'Co-ordinates sent'.
	     ' via Plastic.<br><a href="http://'.$main::host.':'.
	     $main::http.'/sendPoint?ra='.$ra.'&dec='.$dec.
	     '">Send this point back to the Plastic hub</a>.'."'".' );'."\n".
             '        map.addOverlay(marker);'."\n".
	     "\n".
             '      }'."\n".
             '    }'."\n".
             '    //]]>'."\n".
             '    </script>'."\n".
             '  </head>'."\n".
             '  <body onload="load()" onunload="GUnload()">'."\n".
             '    <div id="map" style="width: 800px; height: 500px"></div>'."\n".
             '  </body>'."\n".
             '</html>'."\n";

     	print "Writing new HTML file...\n";
     	print HTML $string;
     	close ( HTML );
	
     	print "Incrementing counter\n";
        $main::counter = $main::counter + 1;
	
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
