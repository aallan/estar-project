#!/software/perl-5.8.6/bin/perl
  
  #use strict;
  
  use SOAP::Lite +trace => all;
  #use SOAP::Lite;
  
  use Digest::MD5 'md5_hex';
  use URI;
  use HTTP::Cookies;
  use Getopt::Long;
  use Net::Domain qw(hostname hostdomain);
  use Socket;
  use Data::Dumper;

  use lib $ENV{"ESTAR_PERL5LIB"};     
  use eSTAR::Util;

  unless ( scalar @ARGV >= 1 ) {
     die "USAGE: $0 -method method [-file filename] [-arg1 arg] [-arg2 arg]" .
         " [-host host] [-port port] [-urn urn] [-user user] [-pass password]\n";
  }

  my ( $host, $port, $urn, $method, $file, $args, $user, $pass );   
  my $status = GetOptions( "host=s"       => \$host,
                           "port=s"       => \$port,
                           "urn=s"        => \$urn,
                           "method=s"     => \$method,
                           "file=s"       => \$file,
                           "arg1=s"       => \$arg1,
                           "arg2=s"       => \$arg2,
			   "user=s"	  => \$user,
			   "pass=s"	  => \$pass );

  # default hostname
  unless ( defined $host ) {
     # localhost.localdoamin
     $host = inet_ntoa(scalar(gethostbyname(hostname())));
  } 

  # default port
  unless( defined $port ) {
     # default port for the survey agent (e.g. WFCAM agent)
     $port = 8000;   
  }
  
  # need method
  unless ( defined $method ) {
     die "USAGE: $0 -method method [-file filename] [-arg1 arg] [-arg2 arg]" .
         " [-host host] [-port port] [-urn urn] [-user user] [-pass password]\n";
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

     if ( defined $arg1 ) {
       $arg2 = $xml;
     } else {
       $arg1 = $xml;
     }    
  }
  
  print "---\n".$xml."\n---\n";
               
  # end point
  $endpoint = "http://" . $host . ":" . $port;
  my $uri = new URI($endpoint);
  print "End Point       : " . $endpoint . "\n";
  
  # create a user/passwd cookie
  $user = "agent" unless defined $user;
  $pass = "InterProcessCommunication" unless defined $pass;
  my $cookie = eSTAR::Util::make_cookie( $user,$pass );
 
  #print Dumper( $cookie );
  
  my $cookie_jar = HTTP::Cookies->new();
  $cookie_jar->set_cookie(0, user => $cookie, '/', $uri->host(), $uri->port());


  # create SOAP connection
  my $soap = new SOAP::Lite();
  
  $urn = "user_agent" unless defined $urn;
  $urn = "urn:/" . $urn;
  print "URN             : " . $urn . "\n";
  
  $soap->uri($urn); 
  $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
  # report
  print "Calling         : $method( $arg1 $arg2 )\n";
    
  # grab result 
  my $result;
  eval { $result = $soap->$method( $arg1, $arg2 ); };
  
  # Needed for the Java NodeAgent
  #$arg1 =~ s/</&lt;/g;
  #eval { $result = $soap->$method( SOAP::Data->name('query', $arg1 )->type('xsd:string') ); };
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
