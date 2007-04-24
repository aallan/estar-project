#!/Software/perl-5.8.8/bin/perl

use Config::User;
use File::Spec;
use Carp;
use Data::Dumper;
use Socket;
use Net::Domain qw(hostname hostdomain);

use POSIX qw/:sys_wait_h/;
use Errno qw/EAGAIN/;
use IO::Socket;
use Getopt::Long;
use Time::localtime;

use XMLRPC::Lite;
use XMLRPC::Transport::HTTP;

# D A E M O N -------------------------------------------------------------

#my $ip = inet_ntoa(scalar(gethostbyname(hostname())));
my $ip = "localhost";
my $port = '8000';

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
               -> new (LocalPort => $port, LocalHost => $ip )
               -> dispatch_to( 'perform' );  };
              if ( $@ ) {
                 my $error = "$@";
                 croak( "Error: $error" );
              }             
     
              $url = $daemon->url();   
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

# R P C -------------------------------------------------------------------

# Grab an RPC endpoint for the ACR
my $file = File::Spec->catfile( Config::User->Home(), ".plastic" );
croak( "Unable to open file $file" ) unless open(PREFIX, "<$file" );

my @prefix = <PREFIX>;
close( PREFIX );

my $endpoint;
foreach my $i ( 0 ... $#prefix ) {
  if ( $prefix[$i] =~ "plastic.xmlrpc.url" ) {
     my @line = split "=", $prefix[$i];
     chomp($line[1]);
     $endpoint = $line[1];
     $endpoint =~ s/\\//g;
  }    
}
print "Plastic Hub Endpoint: $endpoint\n";

my $rpc = new XMLRPC::Lite();
$rpc->proxy($endpoint);

# R E G I S T E R ----------------------------------------------------------

print "Waiting for server to start...\n";
sleep(2);

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
$list[10] = 'ivo://votech.org/fits/image/loadFromURL';

#my @list = ();

my $register;
eval{ $register = $rpc->call( 'plastic.hub.registerXMLRPC', 
                  'Plastic Forwarder', \@list, "http://$ip:$port/" ); };

if( $@ ) {
   croak( "Error: $@" );
}   

my $id;
unless( $register->fault() ) {
   $id = $register->result();
   print "Got Plastic ID of $id\n";
} else {
   croak( "Error: ". $register->faultstring );
}

# M A I N  L O O P ---------------------------------------------------------

while(1) { };

exit;

# D A E M O N   C A L L B A C K S ##########################################

sub perform {
  Plastic::perform( @_ );
}  

package Plastic;

use Data::Dumper;

sub perform {
  my @args = @_;

  print "Callback from Plastic Hub\n";
  print "Message was $args[2]\n";
  #print Dumper( @args );
  if ($args[2] eq 'ivo://votech.org/test/echo' ) {
     return $args[3];
  }
  if ($args[2] eq 'ivo://votech.org/info/getName' ) {
     return "Plastic Forwarder";
  }
  if ($args[2] eq 'ivo://votech.org/info/getIvorn' ) {
     return "ivo://org.perl";
  }   
  if ($args[2] eq 'ivo://votech.org/info/getVersion' ) {
     return "0.4";
  }
  if ($args[2] eq 'ivo://votech.org/info/getDescription' ) {
     return "A simple gateway to forward image/loadFromURL messages.";
  }
  if ($args[2] eq 'ivo://votech.org/info/getIconURL' ) {
     return "http://www.oreillynet.com/images/perl/sm_perl_id_313_wt.gif";
  }   
  if ($args[2] eq 'ivo://votech.org/hub/event/ApplicationRegistered' ) {
     return 1;
  }   
  if ($args[2] eq 'ivo://votech.org/hub/event/ApplicationUnregistered' ) {
     return 1;
  }   
  if ($args[2] eq 'ivo://votech.org/hub/event/HubStopping' ) {
     print "Warning: Hub Stopping Message\n";
     return 1;
  }   
  if ($args[2] eq 'ivo://votech.org/hub/Exception' ) {
     print "Warning: Hub Exception Message\n";
     print "Warning: $args[3]\n";
     return 1;
  }  
  
  # Handle loadImageFromURL  
  if ($args[2] eq 'ivo://votech.org/fits/image/loadFromURL' ) {
     print "Opening socket\n";
     my $message = "$args[2]\nid=${$args[3]}[0]\nurl=${$args[3]}[1]";
     my $sock = new IO::Socket::INET( 
                           PeerAddr => '134.171.17.70',
                           PeerPort => 6666,
                           Proto    => "tcp",
                           Timeout => 30 );
     my ( $response );                        
     unless ( $sock ) {
      
        # we have an error
        my $error = "$!";
        chomp($error);
        print "Error: $error";

     } else { 
  
        # work out message length
        my $bytes = pack( "N", length($message) );
       
        # send message                                   
        print "Sending " . length($message) . " bytes to remote host\n";
        print $sock $bytes;
        $sock->flush();
        print $sock $message;
        $sock->flush();  
        close($sock);
      
        print "Closing socket\n";  
     }
  
 } 

}
