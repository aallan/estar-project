#!/software/perl-5.8.6/bin/perl

use strict;
use File::Spec;
use Astro::VO::VOEvent;
use Data::Dumper;
use SOAP::Lite;
use Digest::MD5 'md5_hex';
use URI;
use HTTP::Cookies;
use Getopt::Long;
use Net::Domain qw(hostname hostdomain);
use Socket;

use lib $ENV{"ESTAR_PERL5LIB"};     
use eSTAR::Util;

# contact details for the event broker
my $host = 'estar.astro.ex.ac.uk';
my $port = 9099;
my $urn = 'event_broker';
my $method = 'handle_voevent';
my $name = 'eSTAR';
$urn = "urn:/" . $urn;

# generate a list of VOEvents from the mail message on <STDIN>
my @events;
my @message = <STDIN>;
foreach my $i ( 0 ... $#message ) {
   if( $message[$i] =~ "OGLE Early Warning System has detected another microlensing candidate event" ) {
     my %event;
     if( $message[$i+2] =~ "OGLE" && $message[$i+2] =~ "BLG" ) {
        $event{name} = $message[$i+2];
        
        my $field = $message[$i+4];
        $field =~ s/Field//;
        $field =~ s/^\s+//;
        $field =~ s/\s+$//;
        $event{field} = $field;
        
        my $starno = $message[$i+5];
        $starno =~ s/StarNo//;
        $starno =~ s/^\s+//;
        $starno =~ s/\s+$//;
        $event{starno} = $starno;

        my $ra = $message[$i+6];
        $ra =~ s/RA\(J2000\.0\)//;
        $ra =~ s/^\s+//;
        $ra =~ s/\s+$//;
        $event{ra} = $ra;

        my $dec = $message[$i+7];
        $dec =~ s/Dec\(J2000\.0\)//;
        $dec =~ s/^\s+//;
        $dec =~ s/\s+$//;
        $event{dec} = $dec;
	
	if( $message[$i+8] =~ "Remarks" ) {
	   my $tmax = $message[$i+10];
           $tmax =~ s/Tmax//;
           $tmax =~ s/^\s+//;
           $tmax =~ s/\s+$//;	   
	   my @tmax = split " ", $tmax;
           $event{tmax} = $tmax[0];
           $event{"tmax error"} = $tmax[1];

	   my $tau = $message[$i+11];
           $tau =~ s/tau//;
           $tau =~ s/^\s+//;
           $tau =~ s/\s+$//;	   
	   my @tau = split " ", $tau;
           $event{tau} = $tau[0];
           $event{"tau error"} = $tau[1];

	   my $umin = $message[$i+12];
           $umin =~ s/umin//;
           $umin =~ s/^\s+//;
           $umin =~ s/\s+$//;	   
	   my @umin = split " ", $umin;
           $event{umin} = $umin[0];
           $event{"umin error"} = $umin[1];

	   my $Amax = $message[$i+13];
           $Amax =~ s/Amax//;
           $Amax =~ s/^\s+//;
           $Amax =~ s/\s+$//;	   
	   my @Amax = split " ", $Amax;
           $event{Amax} = $Amax[0];
           $event{"Amax error"} = $Amax[1];

	   my $Dmag = $message[$i+14];
           $Dmag =~ s/Dmag//;
           $Dmag =~ s/^\s+//;
           $Dmag =~ s/\s+$//;	   
	   my @Dmag = split " ", $Dmag;
           $event{Dmag} = $Dmag[0];
           $event{"Dmag error"} = $Dmag[1];

	   my $fbl = $message[$i+15];
           $fbl =~ s/fbl//;
           $fbl =~ s/^\s+//;
           $fbl =~ s/\s+$//;	   
	   my @fbl = split " ", $fbl;
           $event{fbl} = $fbl[0];
           $event{"fbl error"} = $fbl[1];

	   my $I_bl = $message[$i+16];
           $I_bl =~ s/I_bl//;
           $I_bl =~ s/^\s+//;
           $I_bl =~ s/\s+$//;	   
	   my @I_bl = split " ", $I_bl;
           $event{I_bl} = $I_bl[0];
           $event{"I_bl error"} = $I_bl[1];

	   my $I0 = $message[$i+17];
           $I0 =~ s/I0//;
           $I0 =~ s/^\s+//;
           $I0 =~ s/\s+$//;	   
	   my @I0 = split " ", $I0;
           $event{I0} = $I0[0];
           $event{"I0 error"} = $I0[1];
	   
	   my $tmax_epoch = $message[$i+19];
	   $tmax_epoch =~ s/Tmax epoch corresponds to//;
           $tmax_epoch =~ s/^\s+//;
           $tmax_epoch =~ s/\s+$//;
           $tmax_epoch =~ s/\.+$//;
	   $event{"tmax epoch"} = $tmax_epoch;
	   
	   my $finding_url = $message[$i+24];
	   $event{"finding chart"} = $finding_url;
	   
	   my $voevent = new Astro::VO::VOEvent();
	   my $xml = $voevent->build( 
	Role => 'observation',
	ID   => 'ivo://uk.org.estar/pl.edu.ogle#'.$event{name},
	Description => "The OGLE early warning system (EWS) has detected a ".
		       "candidate micro-lensing transient event. For more ".
		       "information about the OGLE EWS see the OGLE website.",
	Who => { 
	   Publisher => "ivo://uk.org.estar/pl.edu.ogle#",
	   Contact => {  Name        => "Andrzej Udalski",
                         Institution => "OGLE III Project (via eSTAR Project)",
                         Email       => 'udalski@astrouw.edu.pl'  },
	       },	
	WhereWhen => { RA => $event{ra},
	               Dec => $event{dec},
	               Time => $event{"tmax epoch"} 
		     },
        What	    => [ { Name  => 'Field',
        		   Value => $event{field} },
        		 { Name  => 'StarNo',
        		   Value => $event{starno} },
        	         { Group => [ { Name  => 'tmax',
        		              Value => $event{tmax} },
		                    { Name  => 'error',
        		              Value => $event{'tmax error'} } ], },
        	         { Group => [ { Name  => 'tau',
                                        UCD => 'time.scale',
        		              Value => $event{tau} },
		                    { Name  => 'error',
                                        UCD => 'time.interval',
        		              Value => $event{'tau error'} } ], },
        		 { Name  => 'Finding Chart',
        		   Value => $event{"finding chart"} },
		       ],
        Why  => { Classification => { 
        			  Probability  => "0.9",
        			  Type         => "microlensing",
        			  Description  => "Microlensing Event" }, }				
	
	   );	       
           push @events, $xml;
	}   
     }
   }
}

# Connect to the event broker once per event and forward them to the broker

foreach my $j ( 0 ... $#events ) {

  # end point
  my $endpoint = "http://" . $host . ":" . $port;
  my $uri = new URI($endpoint);
  print "End Point       : " . $endpoint . "\n";
  
  # create a user/passwd cookie
  my $cookie = eSTAR::Util::make_cookie( "agent", "InterProcessCommunication" );
  
  my $cookie_jar = HTTP::Cookies->new();
  $cookie_jar->set_cookie(0, user => $cookie, '/', $uri->host(), $uri->port());


  # create SOAP connection
  my $soap = new SOAP::Lite();
  
  $soap->uri($urn); 
  $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
  # report
  print "Calling: $method( )\n";
    
  # grab result 
  my $result;
  eval { $result = $soap->$method( $name, $events[$j] ); };
  if ( $@ ) {
     print "Error: $@";
     exit;   
  }
  
  # Check for errors
  print "Transport Status: " . $soap->transport()->status() . "\n";
  
  unless ($result->fault() ) {
    print "SOAP Result     : " . $result->result() . "\n";
  } else {
    print "Fault Code      : " . $result->faultcode() ."\n";
    print "Fault String    : " . $result->faultstring() ."\n";
  }  


}

exit;
  