#!/software/perl-5.8.8/bin/perl

use strict;

use Config::User;
use File::Spec;
use File::Temp qw(tempfile tempdir);
use File::Find;
use Carp;
use Data::Dumper;
use Net::Domain qw(hostname hostdomain);

use POSIX qw/:sys_wait_h/;
use Errno qw/EAGAIN/;

use HTTP::Daemon;
use HTTP::Status;
use HTTP::Headers;
use HTTP::Response;
  
use vars qw / $VERSION $host $port $in $out /;
$VERSION = sprintf "%d.%d", q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/;

$host = inet_ntoa(scalar(gethostbyname(hostname())));
$port = '8001';
$in = File::Spec->catdir( File::Spec->rootdir(), "var", "spool", "sms", "incoming" );
$out = File::Spec->catdir( File::Spec->rootdir(), "var", "spool", "sms", "outgoing" );

print "GSM Gateway v$VERSION\n\n";

# H T T P   D A E M O N ------------------------------------------------------

print "Starting HTTP Daemon...\n";
my $httpd;
eval { $httpd = new HTTP::Daemon( LocalAddr => $host,
                                  LocalPort => $port,
				  ReuseAddr => 5 ) };
if ( $@ ) {
   my $error = "$@";
   croak( "Error: $error" );
}

unless ( $httpd ) {
   my $error = " HTTP Daemon unable to start";
   croak ( "Error: $error" );
}  	       

print "Daemon started on ". $httpd->url() . "\n";
while (my $connection = $httpd->accept) {
   while (my $request = $connection->get_request() ) {
   
      # Check the white list for an approved host
      print "Connection from " . $connection->peerhost . "\n";
      if ( check_forbidden( $connection->peerhost ) ) {       
         print "Connection attempted from unauthorised host: sending 403 (RC_FORBIDDEN)\n";   
         $connection->send_error(RC_FORBIDDEN);
         print "Done.\n";    
         next;  
      } else {
         print "Connection attempt is from a white listed host...\n";
      }
   
      # check the endpoints
      
      # sendSMS
      # -------
      
      if ($request->method() eq 'GET' and $request->url()->path() eq "/sendSMS") {
         print "Calling sendSMS( )\n";
	  
         my $url = $request->url();
	 my %args = get_arguements( $url );
	 
	 print "Creating temporary file in $out\n";
	 my ($fh, $file) = tempfile( "send_XXXXXX", DIR => $out );
	 print "Created $file\n";
	 
         print "Writing message to file...\n";	 
	 print $fh "To: $args{to}\n\n$args{message}\n";
	 
         print "Chown'ing file to be owned by smsd.dialout...\n";	 
	 system '/bin/chown', 'smsd.dialout', $file;
	 
	 print "Sending '$args{message}' to +$args{to}\n";
	 close( $fh );
	 
	 my $response = new HTTP::Response( RC_OK );
	 $connection->send_response( $response );	 
	 print "Done.\n";

      # getSMS
      # ------
      
      } elsif ($request->method() eq 'GET' and $request->url()->path() eq "/getSMS") {
	 print "Calling getSMS( )\n"; 
	  
         my $url = $request->url();
	 my %args = get_arguements( $url );
	
         if( $args{latest} == 1 ) {
	   print "Retrieving most recent message from $in\n";  
	   my $file = last_modified_file( $in );
	   my $text;
	   {
              local( $/, *FH );
	      unless ( open( FH, $file ) ) {
                 print "File not found: sending 404 (RC_NOT_FOUND)\n";	 
                 $connection->send_error(RC_NOT_FOUND);	 
	      }	         
              $text = <FH>
           }

	   print "Returning contents of $file\n";
	   my $header = new HTTP::Headers( 'Content-Type' => 'text/plain'); 
	   my $response = new HTTP::Response( RC_OK,"OK", $header, $text );
	   $connection->send_response( $response );
	 	 	 
	 } else {
            print "Bad arguements: sending 501 (RC_NOT_IMPLEMENTED)\n";	 
            $connection->send_error(RC_NOT_IMPLEMENTED);
	    	 
	 }	 
	 print "Done.\n";

      # Unknown Method
      # --------------
      
      } else {
         print "Connection attempted to bad endpoint: sending 501 (RC_NOT_IMPLEMENTED)\n";	 
         $connection->send_error(RC_NOT_IMPLEMENTED);
	 print "Done.\n";
      }
   }
   $connection->close();
   undef($connection);
}
  
exit;

sub check_forbidden {
   my $peer = shift;
   my $forbidden = 1;
   
   my @allowed;
   $allowed[0] = "144.173.229.16";  # muttley.astro.ex.ac.uk
   $allowed[1] = "144.173.229.23";  # zilly.astro.ex.ac.uk

   $allowed[2] = "144.173.229.20";  # estar1.astro.ex.ac.uk
   $allowed[3] = "144.173.229.21";  # estar2.astro.ex.ac.uk
   $allowed[4] = "144.173.229.22";  # estar3.astro.ex.ac.uk
   $allowed[5] = "144.173.229.24";  # estar4.astro.ex.ac.uk
   
   $allowed[6] = "144.173.231.43";  # estar5.astro.ex.ac.uk
   $allowed[7] = "144.173.231.44";  # estar6.astro.ex.ac.uk
   $allowed[8] = "144.173.231.45";  # estar7.astro.ex.ac.uk
   $allowed[9] = "144.173.231.46";  # estar8.astro.ex.ac.uk
   $allowed[10] = "144.173.231.41"; # estar9.astro.ex.ac.uk
   
   
   foreach my $i ( 0 ... $#allowed ) {
      $forbidden = 0 if $peer eq $allowed[$i];
   }
   return $forbidden;   
}

sub get_arguements {
   my $buffer = shift;
   my ( $method, $arguements ) = split(/\?/, $buffer );
   my @pairs = split(/&/, $arguements); 

   # Treat all external inputs as suspect, screen and strip out anything 
   # non alphanumeric, sql injection etc. Stripping can give rise to 
   # punctuation issues but extra security judged worthwhile.
   
   my %args;
   foreach my $pair ( @pairs ) { 
      my ($key, $value ) = split (/=/, $pair);
  
      # Swap space for + and convert from hex
      $key =~ tr/+/ /;         
      $key =~ s/%([a-fA-F0-9] [a-fA-F0-9])/pack("C", hex($1))/eg;      
      $key =~ s/[\<\>\"\'\%\;\(\)\&\+]//g; 

      # Swap space for + and convert from hex
      $value =~ tr/+/ /; 
      $value =~ s/%([a-fA-F0-9] [a-fA-F0-9])/pack("C", hex($1))/eg; 

      # Eliminate any server side include script attempts
      $value =~s/<!--(.|\n)*-->//g;

      $value=~ s/%40/\@/; 
      $value=~ s/%20/ /g; 
      $value=~ s/%27/'/g; 
      $value=~ s/%23/#/g; 
      $value=~ s/%26/\&/g; 
      $value=~ s/%28/(/g; 
      $value=~ s/%29/)/g; 
      $value=~ s/%2B/+/g; 
      $value=~ s/%2C/,/g; 
      $value=~ s/%2d/-/g; 
      $value=~ s/%2f/\//g; 
      $value=~ s/%A3//g;  # Sterling
      $value=~ s/%80//g;  # Euro
      $value=~ s/%21/!/g; 
      $value=~ s/%5E/\^/g;
      $value =~ s/[\<\>\"\%\;\+]//g;

      $args{$key} = $value; 
   }
   
   return %args;

}

sub last_modified_file {
    my $dir = shift;
    
    my %files;
    File::Find::find (
        sub {
            my $name = $File::Find::name;
            $files{$name} = (stat $name)[9] if -f $name;
        }, $dir
    );
    ( sort { $files{$a} <=> $files{$b} } keys %files )[-1];
}
