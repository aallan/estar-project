#!/home/perl/bin/perl
  
  #use strict;
  
  #use SOAP::Lite +trace => all;
  use SOAP::Lite;
  use SOAP::MIME;  
  
  use Digest::MD5 'md5_hex';
  use URI;
  use HTTP::Cookies;
  use Getopt::Long;
  
  use lib $ENV{"ESTAR3_PERL5LIB"};     
  use eSTAR::Util;

  unless ( scalar @ARGV >= 1 ) {
     die "USAGE: $0 -method method [-file filename] [-arg args]" .
         " [-host host] [-port port] [-urn urn]\n";
  }

  my ( $host, $port, $urn, $method, $file, $args );   
  my $status = GetOptions( "host=s"       => \$host,
                           "port=s"       => \$port,
                           "urn=s"        => \$urn,
                           "method=s"     => \$method,
                           "file=s"       => \$file,
                           "arg=s"        => \$args );

  # default hostname
  unless ( defined $host ) {
     # localhost.localdoamin
     $host = "127.0.0.1";
  } 

  # default port
  unless( defined $port ) {
     # default port for the survey agent (e.g. WFCAM agent)
     $port = 8005;   
  }
  
  # need method
  unless ( defined $method ) {
     die "USAGE: $0 -method method [-file filename] [-arg args]" .
         " [-host host] [-port port] [-urn urn]\n";
  }
         
  # if we have a file
  my $xml;
  if( defined $file ) {
     unless ( open ( FILE, "<$file") ) {
        die "ERROR: Cannot open $file\n";
     }
     undef $/;
     $xml = <FILE>;
     close FILE;

     $args = $xml;
  }
               
  # end point
  $endpoint = "http://" . $host . ":" . $port;
  my $uri = new URI($endpoint);
  print "End Point       : " . $endpoint . "\n";
  
  # create a user/passwd cookie
  my $cookie = make_cookie( "agent", "InterProcessCommunication" );
  
  my $cookie_jar = HTTP::Cookies->new();
  $cookie_jar->set_cookie(0, user => $cookie, '/', $uri->host(), $uri->port());


  # create SOAP connection
  my $soap = new SOAP::Lite();
  
  $urn = "wfcam_agent" unless defined $urn;
  $urn = "urn:/" . $urn;
  print "URN             : " . $urn . "\n";
  
  $soap->uri($urn); 
  $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
  # report
  print "Calling         : $method( $args )\n";
    
  # grab result 
  my $result;
  eval { $result = $soap->$method( $args ); };
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
 
  exit;
