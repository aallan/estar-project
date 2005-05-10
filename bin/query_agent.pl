#!/software/perl-5.8.6/bin/perl
  
  use strict;
  use lib $ENV{"ESTAR_PERL5LIB"};     

  use SOAP::Lite;
  use Digest::MD5 'md5_hex';
  use URI;
  use HTTP::Cookies;
  use Getopt::Long;
  use Net::Domain qw(hostname hostdomain);
  use Socket;
  use Data::Dumper;
  
  use eSTAR::Config;
  use eSTAR::Util;

  unless ( scalar @ARGV >= 2 ) {
     die "USAGE: $0 -option option [-host host] [-port port]\n";
  }

  my ( $host, $port, $option, $value );   
  my $status = GetOptions( "host=s"       => \$host,
                           "port=s"       => \$port,
                           "option=s"     => \$option );  

  # default hostname
  unless ( defined $host ) {
     # localhost.localdoamin
     $host = inet_ntoa(scalar(gethostbyname(hostname())));

  } 

  # default port
  unless( defined $port ) {
     # default port for the user agent
     $port = 8000;   
  }
  
  # build endpoint
  my $endpoint = "http://$host:$port";
  my $uri = new URI($endpoint);         
  print "End Point is " . $endpoint . "\n";
  
  # create authentication cookie
  my $cookie =  
      eSTAR::Util::make_cookie( "agent", "InterProcessCommunication" );
  my $cookie_jar = HTTP::Cookies->new();
  $cookie_jar->set_cookie(0, 
                  user => $cookie, '/', $uri->host(), $uri->port()); 
                            
 
  # create SOAP connection
  my $soap = new SOAP::Lite();
  $soap->uri('urn:/user_agent'); 
  $soap->proxy($endpoint, cookie_jar => $cookie_jar);

 
  print "Calling get_option( $option )\n";
  my $result;
  eval { $result = $soap->get_option( $option ); };
                                        
  if ( $@ ) {
     print "Warning: Problem connecting to user agent\n";
     print "Error: $@";
  } else {
     print "$option = " . $result->result() . "\n"; 
  }                                       
  

  exit;
  
