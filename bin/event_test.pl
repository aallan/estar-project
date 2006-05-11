#!/software/perl-5.8.6/bin/perl
  
use strict;
use threads;

use IO::Socket;
use POSIX qw/:sys_wait_h/;
use Data::Dumper;
use Net::Domain qw(hostname hostdomain);
use Time::localtime;
use Getopt::Long;

my $quit;
my ( $port, $wait );   
my $status = GetOptions( "wait=s"	=> \$wait,
			 "port=s"	=> \$port  ); 
                         
unless ( defined $port ) {
   $port = "9999";
}

unless ( defined $wait ) {
   $wait = "5";
}      

$SIG{PIPE} = sub { 
		print "Disconnect\n";
                     
             };
	     
$SIG{INT} = sub {
		print "Interrupt\n";
		$quit = 1;
	     };	 

print "Starting server...\n";
my $ip = inet_ntoa(scalar(gethostbyname(hostname())));
my $sock = new IO::Socket::INET( 
		  LocalHost => $ip,
		  LocalPort => $port,
		  Proto     => 'tcp',
		  Listen    => 10,
		  Reuse     => 1 ); 
		    
die "Could not create socket: $!\n" unless $sock;
while( !$quit ) {
  next unless my $c = $sock->accept();
  
  print "Accepted connection from " . $c->peerhost() . "\n"; 
  my $thread = threads->new( \&callback, $c );
  $thread->detach;
  
} 
  
print "Exiting...\n";
exit;

sub callback {
    my $c = shift;
    my $peer = $c->peerhost();
    
    my $counter = 1;
    
    # read from data block
    my @buffer = <DATA>;

    my $pid = getpgrp();

    my $xml = "";
    foreach my $i ( 0 ... $#buffer ) {
       $xml = $xml . $buffer[$i];
    }

    while ( 1 ) {
      print "THREAD: Sleeping for $wait seconds...\n";
      sleep $wait;
      $counter = $counter + 1;
      my $ra = 0.2;
      $ra = $ra + 10*$counter;
      my $dec = 75.2;

      # SMC
      #my $ra = "13.273740468478499";
      #my $dec ="-72.80148644174551";
      
      # LMC
      #my $ra = "79.94189584185203",
      #my $dec = "-68.83347100046278";  
      
      my $connect = $c->connected();
      unless( defined $connect ) {
	 print "THREAD: Closing socket from $peer\n";
	 print "THREAD: Done...\n";
	 last;
      }	 

      my $previous = $counter - 1;
      my $xml = 
  "<?xml version = '1.0' encoding = 'UTF-8'?>\n".
  '<VOEvent role="test" version="1.1" '.
  'ivorn="ivo://uk.org.estar/estar.ex#test/'. $pid . ".". $counter .'" '.
  'xmlns="http://www.ivoa.net/xml/VOEvent/v1.1" '.
  'xsi:schemaLocation="http://www.ivoa.net/xml/STC/stc-v1.20.xsd'. 
  ' http://hea-www.harvard.edu/~arots/nvometa/v1.2/stc-v1.20.xsd'. 
  ' http://www.ivoa.net/xml/STC/STCcoords/v1.20'. 
  ' http://hea-www.harvard.edu/~arots/nvometa/v1.2/coords-v1.20.xsd'.
  ' http://www.ivoa.net/xml/VOEvent/v1.1 '. 
  ' http://www.ivoa.net/internal/IVOA/IvoaVOEvent/VOEvent-v1.0.xsd" '. 
  'xmlns:stc="http://www.ivoa.net/xml/STC/stc-v1.20.xsd" '. 
  'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '. 
  'xmlns:crd="http://www.ivoa.net/xml/STC/STCcoords/v1.20">'."\n".
  '<Citations>'."\n".
  '  <EventID cite="supersedes">ivo://uk.org.estar/estar.ex#test/'. $pid . "." . $previous . 
  '</EventID>' . "\n".
  '</Citations>'. "\n".
  '<Who>'. "\n".
  '  <PublisherID>ivo://uk.org.estar/estar.ex#</PublisherID>'. "\n".
  '  <Date>'.time_iso().'</Date>'. "\n".
  '</Who>'. "\n".
  '   <WhereWhen type="simple">'. "\n".
  '      <RA units="deg">'. "\n".
  '          <Coord>'.$ra.'</Coord>'. "\n".
  '          <Error value="4" units="arcmin" />'. "\n".
  '      </RA>'. "\n".
  '      <Dec units="deg">'. "\n".
  '          <Coord>'.$dec.'</Coord>'. "\n".
  '          <Error value="4" units="arcmin" />'. "\n".
  '      </Dec>'. "\n".
  '      <Epoch value="J2000.0" />'. "\n".
  '      <Equinox value="2000.0" />'. "\n".
  '      <Time>'. "\n".
  '          <Value>2005-04-15T23:59:59</Value>'. "\n".
  '          <Error value="30" units="s" />'. "\n".
  '      </Time>'. "\n".
  '  </WhereWhen>'. "\n".
  '<What>'. "\n".
  '  <Param value="test" name="TYPE" />'. "\n".
  '  <Param value="'.$counter.'" name="COUNTER" />'. "\n".
  '  <Group name="Test Server Parameters" >'. "\n".
  '    <Param value="'.$pid.'" name="PID" />'. "\n".
  '    <Param value="'.$ip.'" name="HOST" />'. "\n".
  '    <Param value="9999" name="PORT" />'. "\n".
  '  </Group>'. "\n".
  '</What>'. "\n".
  '<Why importance="0.0">'. "\n".
  '  <Inference probability="1.0" >'. "\n".
  '    <Concept>Test Packet</Concept>'. "\n".
  '    <Name>test</Name>'. "\n".
  '    <Description>An esSTAR test packet</Description>'. "\n".
  '  </Inference>'. "\n".
  '</Why>'. "\n".
  '</VOEvent>'. "\n"; 
      
      my $bytes = pack( "N", length($xml) );
      print $c $bytes;
      print "THREAD: Sending message\n";
      print "$xml\n";
      $c->flush();
      print $c $xml;
      $c->flush();

      print "THREAD: Reading reply\n";
      my $length;  
      my $bytes_read = read( $c, $length, 4 );      
      $length = unpack( "N", $length );
     
      my $response;
      $bytes_read = read( $c, $response, $length); 
      print "THREAD: Read $bytes_read characters from socket\n";
      print "$response\n";
      print "THREAD: Done.\n\n";
    
   }
}    


sub time_iso {
   # ISO format
   		     
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
