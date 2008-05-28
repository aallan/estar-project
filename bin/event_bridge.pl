#!/software/perl-5.8.8/bin/perl


#use strict;

use IO::Socket;
use POSIX qw/:sys_wait_h/;
use Errno qw/EAGAIN/;
use Getopt::Long;
use Time::localtime;

use URI;
use HTTP::Cookies;
use Digest::MD5 'md5_hex';
use SOAP::Lite;

#use Astro::VO::VOEvent;

unless ( scalar @ARGV >= 2 ) {
   die "USAGE: $0 [-host hostname] [-port portname]\n";
}

my ( $host, $port );   
my $status = GetOptions( "host=s"	=> \$host,
			 "port=s"	=> \$port  ); 

unless ( defined $host ) {
   $host = "127.0.0.1";
}
unless ( defined $port ) {
   $port = "8080";
}   

my $feed_name = 'GCN';
 
SOCKET: { 
       
print "Opening client connection to $host:$port\n";    
my $sock = new IO::Socket::INET( PeerAddr => $host,
                                 PeerPort => $port,
                                 Proto    => "tcp" );

unless ( $sock ) {
    my $error = "$@";
    chomp($error);
    print "Warning: $error\n";
    print "Warning: Trying to reopen socket connection...\n";
    sleep 5;
    redo SOCKET;
};           


my $message;
print "Socket open, listening...\n";
my $flag = 1;    
while( $flag ) {

   my $length;  
   my $bytes_read = read( $sock, $length, 4 );

   next unless defined $bytes_read;
   
   print "\nRecieved a packet from $host...\n";
   print "Time at recieving host is " . ctime() . "\n";
   if ( $bytes_read > 0 ) {

      print "Recieved $bytes_read bytes on $port from ".$sock->peerhost()."\n";
          
      $length = unpack( "N", $length );
      if ( $length > 512000 ) {
        print "Error: Message length is > 512000 characters\n";
        print "Error: Message claims to be $length long\n";
        print "Warning: Discarding bogus message\n";
      } else {   
         
         print "Message is $length characters\n";               
         $bytes_read = read( $sock, $message, $length); 
      
         print "Read $bytes_read characters from socket\n";
      
         # callback to handle incoming Events     
	 print $message . "\n";	 
         #my $object = new Astro::VO::VOEvent( XML => $message );
	 
	 my $response;
	 #if ( $object->role() eq "iamalive" ) {
	 if ( $message =~ "iamalive" ) {
	    $response = $message;
         } else {

            my $status = forward_message( $message );

	    my $what = "";
	    unless ( $status ) {
	      $what = 
	       '<What>'. "\n".
 	       '  <Param name="ERROR" value="Not Forwarded" />'. "\n".
	       '</What>'. "\n";
	    }
	    $response = 
  "<?xml version = '1.0' encoding = 'UTF-8'?>\n" .
  '<voe:VOEvent role="ack" version= "1.1" '.
  'ivorn="ivo://uk.org.estar/estar.bridge#ack" '.
  'xmlns:voe="http://www.ivoa.net/xml/VOEvent/v1.1" '.
  'xmlns:xlink="http://www.w3.org/1999/xlink" '.
  'xsi:schemaLocation="http://www.ivoa.net/xml/VOEvent/v1.1'.
  ' http://www.ivoa.net/internal/IVOA/IvoaVOEvent/VOEvent-v1.1-060425.xsd" '. 
  'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'."\n".  
  '<Who>' . "\n" . 
  '   <AuthorIVORN>ivo://uk.org.estar/estar.bridge#</AuthorIVORN>' . "\n" . 
  '</Who>' . "\n" . $what . 
  '</voe:VOEvent>' . "\n";

	 }
	 
	 my $bytes = pack( "N", length($response) ); 
         print "Sending " . length($response) . " bytes to socket\n";
         print $sock $bytes;
         $sock->flush();
         print $sock $response;
	 print "$response\n";
         $sock->flush(); 
	 print "Done.\n";
	  
      }
                      
   } elsif ( $bytes_read == 0 && $! != EWOULDBLOCK ) {
      print "Recieved an empty packet on $port from ".$sock->peerhost()."\n";   
      print "Closing socket connection...";      
      $flag = undef;
   } elsif ( $bytes_read == 0 ) {
      print "Recieved an empty packet on $port from ".$sock->peerhost()."\n";   
      print "Closing socket connection...";      
      $flag = undef;   
   }
   
   unless ( $sock->connected() ) {
      print "Warning: Not connected, socket closed...\n";
      $flag = undef;
   }    

}  
  
print "Warning: Trying to reopen socket connection...\n";
redo SOCKET;

   
}  
exit; 

                                    
sub make_cookie {
   my ($user, $passwd) = @_;
   my $cookie = $user . "::" . md5_hex($passwd);
   $cookie =~ s/(.)/sprintf("%%%02x", ord($1))/ge;
   $cookie =~ s/%/%25/g;
   $cookie;
}

sub timestamp {
   # ISO format 2006-01-05T08:00:00
		   
   my $year = 1900 + localtime->year();
 
   my $month = localtime->mon() + 1;
   $month = "0$month" if $month < 10;
 
   my $day = localtime->mday();
   $day = "0$day" if $day < 10;
 
   my $hour = localtime->hour();
   $hour = "0$hour" if $hour < 10;
 
   my $min = localtime->min();
   $min = "0$min" if $min < 10;
 
   my $sec = localtime->sec();
   $sec = "0$sec" if $sec < 10;
 
   my $timestamp = $year ."-". $month ."-". $day ."T". 
		   $hour .":". $min .":". $sec;

   return $timestamp;
} 

sub forward_message {
  my $event = shift;
  print "Forwarding message to remote host...\n";

  # EVENT BROKER
  my $exeter_host = 'estar6.astro.ex.ac.uk';
  my $exeter_port = 9099;
  my $exeter_urn = 'urn:/event_broker';

  my $endpoint = "http://" . $exeter_host . ":" . $exeter_port;
  my $uri = new URI($endpoint);
  print "End Point is " . $endpoint . "\n";

  my $cookie = make_cookie( "agent", "InterProcessCommunication" );
  my $cookie_jar = new HTTP::Cookies( );
  $cookie_jar->set_cookie(0, user => $cookie, '/', $uri->host(), $uri->port());

  # create SOAP connection
  my $soap = new SOAP::Lite();
  
  print "URN is $exeter_urn\n";
  $soap->uri($exeter_urn); 
  $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
  # report
  print "Calling handle_voevent( )\n";
    
  # grab result 
  my $result;
  eval { $result = $soap->handle_voevent( $feed_name, $event ); };
  if ( $@ ) {
     print "Error: $@";
     exit;   
  }
  
  # Check for errors
  print "Transport status was " . $soap->transport()->status() . "\n";
  
  my $status = 0;
  unless ($result->fault() ) {
    print "SOAP result = '" . $result->result() . "'\n";
    $status = 1;
  } else {
    print "SOAP error = " . $result->faultstring() ."\n";
  }
  
  return $status;
}
