#!/home/perl/bin/perl
  
  #use strict;
  use threads; 
  use threads::shared;
  
  #use SOAP::Lite +trace => all;
  use SOAP::Lite;
  use SOAP::MIME;  
  
  use Digest::MD5 'md5_hex';
  use URI;
  use HTTP::Cookies;
  use Getopt::Long;
  use Net::Domain qw(hostname hostdomain);
  use Socket;
  use POSIX qw/:sys_wait_h/;
  
  use lib $ENV{"ESTAR3_PERL5LIB"};     
  use eSTAR::Util;

  unless ( scalar @ARGV >= 1 ) {
     die "USAGE: $0 -file filename [-host host] [-port port]\n";
  }

  my ( $host, $port, $file );   
  my $status = GetOptions( "file=s" => \$file,
                           "host=s" => \$host,
			   "port=s" => \$port );

  # default hostname
  unless ( defined $host ) {
     # localhost.localdoamin
     $host = "127.0.0.1";
  } 

  # default port
  unless( defined $port ) {
     # default port for the data mining process
     $port = 8006;   
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
  }

  # START SOAP SERVER
  # -----------------

  my $ip = inet_ntoa(scalar(gethostbyname(hostname())));  
  my $server_host = $ip;
  my $server_port = 8005;
  
  # anonymous subroutine which starts a SOAP server which will accept
  # incoming SOAP requests and route them to the appropriate module
  my $soap_server = sub {
    my $daemon = new SOAP::Transport::HTTP::Daemon(
                     LocalAddr => $server_host, LocalPort => $server_port);
    $daemon->dispatch_with({ 'urn:/wfcam_agent' => 'Callback' });
    $daemon->handle;
  };

  my $listener_thread = threads->create( $soap_server );
  
  # SOAP CLIENT CONNECTION
  # ----------------------
               
  # end point
  my $endpoint = "http://" . $host . ":" . $port;
  my $uri = new URI($endpoint);
  
  # create a user/passwd cookie
  my $cookie = eSTAR::Util::make_cookie("agent", "InterProcessCommunication");
  
  my $cookie_jar = HTTP::Cookies->new();
  $cookie_jar->set_cookie(0, user => $cookie, '/', $uri->host(), $uri->port());

  # MAKE SOAP CONNECTION
  # --------------------

  # create SOAP connection
  my $soap = new SOAP::Lite();
  
  $urn = "data_miner" unless defined $urn;
  $urn = "urn:/" . $urn;
  
  $soap->uri($urn); 
  $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
  # report
  my $context = "TEST";
  print "Calling handle_object( \$context, \$host, \$port, \$xml )\n";
    
  # grab result 
  my $result;
  eval { $result = $soap->handle_objects( $context, $server_host, 
                                          $server_port, $xml ); };
  if ( $@ ) {
     print "Error: $@";
     exit;   
  }

  unless ($result->fault() ) {
    print "Returned message (" . $result->result() . ")\n";
  } else {
    print "Fault Code (" . $result->faultcode() .")\n";
    print "Fault: " . $result->faultstring() ."\n";
  }  
 
  print "Server thread listening for response...\n";
  $status = $listener_thread->join() if defined $listener_thread;
  print "Error: Server thread terminated with status ($status)\n";
  exit;

  # CALLBACK CLASS
  # --------------
  
  package Callback;
  
  sub callback {
     my $process = shift;
     my @args = @_;
     
     print "Message passed to callback( )\n";
     foreach my $i ( 0 ... $#args ) {
        print "$i = $args[$i]\n";
     }	     
     return "ACK";
  }
