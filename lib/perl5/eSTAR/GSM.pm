package eSTAR::GSM;

use strict;
use warnings;

require Exporter;

use vars qw/$VERSION @EXPORT_OK @ISA /;

use Data::Dumper;
use Digest::MD5 'md5_hex';
use Fcntl qw(:DEFAULT :flock);
use Net::SMTP;
use Config::Simple;
use Config::IniFiles;
use LWP::UserAgent;

use eSTAR::Constants qw /:all/;
use eSTAR::Logging;
use eSTAR::Process;
use eSTAR::Config;
use eSTAR::Error qw /:try/;
use eSTAR::Util;

@ISA = qw/Exporter/;
@EXPORT_OK = qw/ send_sms /;

'$Revision: 1.3 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);


sub send_sms {
   my $to = shift;
   my $body = shift;

   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();
   my $config = eSTAR::Config::get_reference();
   my $ua = eSTAR::UserAgent::get_reference();
   
   my $agent = $ua->get_ua();
   unless ( defined $agent ) {
      my $lwp = new LWP::UserAgent( 
                timeout => $config->get_option( "connection.timeout" ));

      $lwp->env_proxy();
      $lwp->agent( "eSTAR::Util /$VERSION (" 
                    . hostname() . "." . hostdomain() .")");

      $ua->set_ua( $lwp );
   } 
  
   #$log->debug( "Sending SMS message to +$to" ); 
   
   my $response;
   eval {
      $response = $agent->get( 
        "http://estar6.astro.ex.ac.uk:8001/sendSMS?to=". 
	$to . "&message=" . $body );
   };
   
   my $return;
   if ($@) {
      $return = "500 Failed";
   }
   $return = $response->status_line() unless defined $return;
   
   return $return;
};

1;
