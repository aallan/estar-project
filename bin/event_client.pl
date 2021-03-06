#!/software/perl-5.8.6/bin/perl
  
#use strict;

use IO::Socket;
use POSIX qw/:sys_wait_h/;
use Errno qw/EAGAIN/;
use Getopt::Long;
use Time::localtime;

use Astro::VO::VOEvent;

unless ( scalar @ARGV >= 2 ) {
   die "USAGE: $0 [-host hostname] [-port portname]\n";
}

my ( $host, $port );   
my $status = GetOptions( "host=s"	=> \$host,
			 "port=s"	=> \$port  ); 

unless ( defined $host && defined $port ) {
   $host = "127.0.0.1";
   $port = "9999";
}   
 
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
       
         my $object = new Astro::VO::VOEvent( XML => $message );
	 
	 my $response;
	 if ( $object->role() eq "iamalive" ) {
	    $response = $message;
         } else {
	    $response = "<?xml version = '1.0' encoding = 'UTF-8'?>\n" .
  '<voe:VOEvent role="ack" version= "1.1" '.
  'ivorn="ivo://uk.org.estar/estar.broker#ack" '.
  'xmlns:voe="http://www.ivoa.net/xml/VOEvent/v1.1" '.
  'xmlns:xlink="http://www.w3.org/1999/xlink" '.
  'xsi:schemaLocation="http://www.ivoa.net/xml/VOEvent/v1.1'.
  ' http://www.ivoa.net/internal/IVOA/IvoaVOEvent/VOEvent-v1.1-060425.xsd" '. 
  'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'."\n".  
  '<Who>' . "\n" . 
  '   <AuthorIVORN>ivo://uk.org.estar/estar.broker#</AuthorIVORN>' . "\n" . 
  '</Who>' . "\n" . 
  '</voe:VOEvent>' . "\n";
	 }
	 
	 my $bytes = pack( "N", length($response) ); 
         print "Sending " . length($response) . "bytes to socket\n";
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
  
